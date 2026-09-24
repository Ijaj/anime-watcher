import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../config.dart';
import '../models/episode.dart';
import '../models/item.dart';

class DuplicateItemException implements Exception {
  final String rootPath;
  const DuplicateItemException(this.rootPath);

  @override
  String toString() => 'This folder is already in your library:\n$rootPath';
}

/// All reads and writes of library data. Notifies listeners whenever the
/// library, episode list, or watched state changes.
class LibraryRepository extends ChangeNotifier {
  final Database _db;

  LibraryRepository(this._db);

  Future<void> close() => _db.close();

  // ---------------------------------------------------------------- items

  Future<List<LibraryEntry>> entries() async {
    final rows = await _db.rawQuery('''
      SELECT i.*,
        (SELECT COUNT(*) FROM episodes e WHERE e.item_id = i.id) AS episode_count,
        (SELECT COUNT(*) FROM episodes e JOIN watch_progress w ON w.episode_id = e.id
           WHERE e.item_id = i.id AND w.completed = 1) AS watched_count
      FROM items i
      ORDER BY i.title COLLATE NOCASE''');
    return [
      for (final r in rows)
        LibraryEntry(
          item: LibraryItem.fromMap(r),
          episodeCount: r['episode_count'] as int,
          watchedCount: r['watched_count'] as int,
        ),
    ];
  }

  Future<LibraryItem?> item(int id) async {
    final rows = await _db.query('items', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : LibraryItem.fromMap(rows.first);
  }

  Future<bool> containsPath(String rootPath) async {
    final rows = await _db.query('items', columns: ['id'], where: 'root_path = ?', whereArgs: [rootPath]);
    return rows.isNotEmpty;
  }

  /// Stores [item] and its [episodes]. Throws [DuplicateItemException] if the
  /// folder is already in the library.
  Future<LibraryItem> addItem(LibraryItem item, List<ScannedEpisode> episodes) async {
    if (await containsPath(item.rootPath)) throw DuplicateItemException(item.rootPath);
    final saved = await _db.transaction((txn) async {
      final id = await txn.insert('items', item.toMap()..remove('id'));
      final batch = txn.batch();
      for (final e in episodes) {
        batch.insert('episodes', _episodeRow(id, e), conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      await batch.commit(noResult: true);
      return item.copyWith(id: id);
    });
    notifyListeners();
    return saved;
  }

  Future<void> removeItem(int id) async {
    await _db.delete('items', where: 'id = ?', whereArgs: [id]);
    notifyListeners();
  }

  // ------------------------------------------------------------- episodes

  Future<List<Episode>> episodes(int itemId) async {
    final rows = await _db.rawQuery('''
      SELECT e.*, w.position_ms, w.duration_ms, w.completed, w.updated_at
      FROM episodes e LEFT JOIN watch_progress w ON w.episode_id = e.id
      WHERE e.item_id = ?
      ORDER BY e.season = 0, e.season, e.number, e.path''', [itemId]);
    return rows.map(Episode.fromMap).toList();
  }

  /// Syncs the stored episodes of [itemId] with a fresh scan: new files are
  /// added, missing files are removed (with their progress), and moved
  /// season/episode numbers are updated. Returns (added, removed).
  Future<(int, int)> syncEpisodes(int itemId, List<ScannedEpisode> scanned) async {
    final result = await _db.transaction((txn) async {
      final existing = {
        for (final r in await txn.query('episodes', where: 'item_id = ?', whereArgs: [itemId])) r['path'] as String: r,
      };
      final seen = <String>{};
      var added = 0;
      final batch = txn.batch();
      for (final e in scanned) {
        seen.add(e.path);
        final row = existing[e.path];
        if (row == null) {
          batch.insert('episodes', _episodeRow(itemId, e), conflictAlgorithm: ConflictAlgorithm.ignore);
          added++;
        } else if (row['season'] != e.season || row['number'] != e.number) {
          batch.update('episodes', {'season': e.season, 'number': e.number}, where: 'id = ?', whereArgs: [row['id']]);
        }
      }
      final missing = existing.keys.where((path) => !seen.contains(path)).toList();
      for (final path in missing) {
        batch.delete('episodes', where: 'id = ?', whereArgs: [existing[path]!['id']]);
      }
      await batch.commit(noResult: true);
      return (added, missing.length);
    });
    notifyListeners();
    return result;
  }

  Map<String, Object?> _episodeRow(int itemId, ScannedEpisode e) =>
      {'item_id': itemId, 'season': e.season, 'number': e.number, 'path': e.path};

  // ------------------------------------------------------------- progress

  /// Records playback position. Once an episode is completed it stays
  /// completed until [setWatched] clears it.
  Future<void> saveProgress(int episodeId, {required Duration position, required Duration duration}) async {
    final completed =
        duration > Duration.zero && position.inMilliseconds >= duration.inMilliseconds * AppConfig.watchedThreshold;
    final before =
        await _db.query('watch_progress', columns: ['completed'], where: 'episode_id = ?', whereArgs: [episodeId]);
    await _db.rawInsert('''
      INSERT INTO watch_progress (episode_id, position_ms, duration_ms, completed, updated_at)
      VALUES (?, ?, ?, ?, ?)
      ON CONFLICT(episode_id) DO UPDATE SET
        position_ms = excluded.position_ms,
        duration_ms = excluded.duration_ms,
        completed = MAX(completed, excluded.completed),
        updated_at = excluded.updated_at''', [
      episodeId,
      position.inMilliseconds,
      duration.inMilliseconds,
      completed ? 1 : 0,
      DateTime.now().millisecondsSinceEpoch,
    ]);
    final wasCompleted = before.isNotEmpty && before.first['completed'] == 1;
    // Only list-level state (watched counts) needs a refresh; skip the
    // periodic position saves to avoid rebuilding the UI every few seconds.
    if (before.isEmpty || completed != wasCompleted) notifyListeners();
  }

  Future<void> setWatched(int episodeId, bool watched) async {
    if (watched) {
      await _db.rawInsert('''
        INSERT INTO watch_progress (episode_id, position_ms, duration_ms, completed, updated_at)
        VALUES (?, 0, 0, 1, ?)
        ON CONFLICT(episode_id) DO UPDATE SET completed = 1, updated_at = excluded.updated_at''',
          [episodeId, DateTime.now().millisecondsSinceEpoch]);
    } else {
      await _db.delete('watch_progress', where: 'episode_id = ?', whereArgs: [episodeId]);
    }
    notifyListeners();
  }

  /// Picks the episode to play next from an ordered episode list: the most
  /// recently touched episode if it is unfinished, otherwise the first
  /// unfinished episode after it, otherwise the first unfinished episode.
  /// Returns null when everything is watched.
  static Episode? nextUp(List<Episode> episodes) {
    if (episodes.isEmpty) return null;
    var lastIndex = -1;
    DateTime? lastTime;
    for (var i = 0; i < episodes.length; i++) {
      final t = episodes[i].progress?.updatedAt;
      if (t != null && (lastTime == null || t.isAfter(lastTime))) {
        lastTime = t;
        lastIndex = i;
      }
    }
    if (lastIndex >= 0 && !episodes[lastIndex].completed) return episodes[lastIndex];
    for (var i = lastIndex + 1; i < episodes.length; i++) {
      if (!episodes[i].completed) return episodes[i];
    }
    for (final e in episodes) {
      if (!e.completed) return e;
    }
    return null;
  }

  // ------------------------------------------------------------- settings

  Future<String?> setting(String key) async {
    final rows = await _db.query('settings', where: 'key = ?', whereArgs: [key]);
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  Future<void> setSetting(String key, String? value) =>
      _db.insert('settings', {'key': key, 'value': value}, conflictAlgorithm: ConflictAlgorithm.replace);
}
