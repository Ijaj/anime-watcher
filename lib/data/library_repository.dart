import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../config.dart';
import '../models/continue_watching.dart';
import '../models/episode.dart';
import '../models/item.dart';

class DuplicateItemException implements Exception {
  final String rootPath;
  const DuplicateItemException(this.rootPath);

  @override
  String toString() => 'This folder is already in your library:\n$rootPath';
}

/// Outcome of [LibraryRepository.syncAll].
class RescanSummary {
  final int added;
  final int removed;

  /// Shows that gained or lost episodes.
  final int changedShows;

  /// Shows skipped because their folder could not be scanned.
  final int unavailable;

  const RescanSummary({this.added = 0, this.removed = 0, this.changedShows = 0, this.unavailable = 0});

  bool get changed => added + removed > 0;

  RescanSummary copyWith({int? added, int? removed, int? changedShows, int? unavailable}) => RescanSummary(
        added: added ?? this.added,
        removed: removed ?? this.removed,
        changedShows: changedShows ?? this.changedShows,
        unavailable: unavailable ?? this.unavailable,
      );

  /// e.g. "Library updated in 2 shows. New: 3 episodes, removed: 1 episode · 1 folder unavailable".
  String describe() {
    String plural(int n, String word) => '$n $word${n == 1 ? '' : 's'}';
    final parts = [
      if (added > 0) 'New: ${plural(added, 'episode')}',
      if (removed > 0) 'removed: ${plural(removed, 'episode')}',
    ];
    final text = StringBuffer('Library updated in ${plural(changedShows, 'show')}. ${parts.join(', ')}');
    if (unavailable > 0) text.write(' · ${plural(unavailable, 'folder')} unavailable');
    return text.toString();
  }
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
           WHERE e.item_id = i.id AND w.completed = 1) AS watched_count,
        (SELECT MAX(w.updated_at) FROM episodes e JOIN watch_progress w ON w.episode_id = e.id
           WHERE e.item_id = i.id) AS last_watched
      FROM items i
      ORDER BY i.title COLLATE NOCASE''');
    return [
      for (final r in rows)
        LibraryEntry(
          item: LibraryItem.fromMap(r),
          episodeCount: r['episode_count'] as int,
          watchedCount: r['watched_count'] as int,
          lastWatchedAt:
              r['last_watched'] == null ? null : DateTime.fromMillisecondsSinceEpoch(r['last_watched'] as int),
        ),
    ];
  }

  /// Entries whose title contains every word of [query] (case- and
  /// punctuation-insensitive), ordered by [sort]. Ties, and never-watched
  /// items when sorting by recently watched, fall back to title order.
  static List<LibraryEntry> filterAndSort(List<LibraryEntry> entries,
      {String query = '', LibrarySort sort = LibrarySort.title}) {
    final words = _normalize(query).split(' ').where((w) => w.isNotEmpty).toList();
    final result = [
      for (final e in entries)
        if (words.every(_normalize(e.item.title).contains)) e,
    ];
    int byTitle(LibraryEntry a, LibraryEntry b) => a.item.title.toLowerCase().compareTo(b.item.title.toLowerCase());
    int newestFirst(DateTime? a, DateTime? b) {
      if (a == b) return 0;
      if (a == null) return 1;
      if (b == null) return -1;
      return b.compareTo(a);
    }

    result.sort((a, b) {
      final c = switch (sort) {
        LibrarySort.title => 0,
        LibrarySort.recentlyWatched => newestFirst(a.lastWatchedAt, b.lastWatchedAt),
        LibrarySort.recentlyAdded => newestFirst(a.item.addedAt, b.item.addedAt),
      };
      return c != 0 ? c : byTitle(a, b);
    });
    return result;
  }

  static String _normalize(String s) => s.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ');

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

  static const _episodeSelect = '''
      SELECT e.*, w.position_ms, w.duration_ms, w.completed, w.updated_at
      FROM episodes e LEFT JOIN watch_progress w ON w.episode_id = e.id''';

  /// Seasons in order with specials last, then episode number.
  static const _episodeOrder = 'e.season = 0, e.season, e.number, e.path';

  Future<List<Episode>> episodes(int itemId) async {
    final rows = await _db.rawQuery('$_episodeSelect WHERE e.item_id = ? ORDER BY $_episodeOrder', [itemId]);
    return rows.map(Episode.fromMap).toList();
  }

  /// The next-up episode ([nextUp]) of every show with watch history, most
  /// recently watched show first. Fully watched shows are left out.
  Future<List<ContinueWatching>> continueWatching() async {
    final started = (await entries()).where((e) => e.lastWatchedAt != null).toList()
      ..sort((a, b) => b.lastWatchedAt!.compareTo(a.lastWatchedAt!));
    if (started.isEmpty) return const [];
    final ids = [for (final e in started) e.item.id!];
    final rows = await _db.rawQuery(
        '$_episodeSelect WHERE e.item_id IN (${List.filled(ids.length, '?').join(',')}) ORDER BY e.item_id, $_episodeOrder',
        ids);
    final byItem = <int, List<Episode>>{};
    for (final r in rows) {
      final episode = Episode.fromMap(r);
      byItem.putIfAbsent(episode.itemId, () => []).add(episode);
    }
    return [
      for (final entry in started)
        if (nextUp(byItem[entry.item.id] ?? const []) case final next?) ContinueWatching(entry: entry, episode: next),
    ];
  }

  /// Syncs the stored episodes of [itemId] with a fresh scan: new files are
  /// added, missing files are removed (with their progress), and moved
  /// season/episode numbers are updated. Returns (added, removed).
  Future<(int, int)> syncEpisodes(int itemId, List<ScannedEpisode> scanned) async {
    final (added, removed, _) = await _sync(itemId, scanned);
    notifyListeners();
    return (added, removed);
  }

  /// Syncs every library item with the episodes [scan] returns for it (see
  /// [syncEpisodes]); when [scan] returns null the item is left untouched.
  /// Listeners are notified once, at the end, and only if anything changed.
  Future<RescanSummary> syncAll(Future<List<ScannedEpisode>?> Function(LibraryEntry entry) scan) async {
    var summary = const RescanSummary();
    var anyChange = false;
    for (final entry in await entries()) {
      final List<ScannedEpisode>? scanned;
      try {
        scanned = await scan(entry);
      } catch (_) {
        summary = summary.copyWith(unavailable: summary.unavailable + 1);
        continue;
      }
      if (scanned == null) {
        summary = summary.copyWith(unavailable: summary.unavailable + 1);
        continue;
      }
      final (added, removed, renumbered) = await _sync(entry.item.id!, scanned);
      anyChange |= added + removed + renumbered > 0;
      if (added + removed > 0) {
        summary = summary.copyWith(
          added: summary.added + added,
          removed: summary.removed + removed,
          changedShows: summary.changedShows + 1,
        );
      }
    }
    if (anyChange) notifyListeners();
    return summary;
  }

  /// Returns (added, removed, renumbered).
  Future<(int, int, int)> _sync(int itemId, List<ScannedEpisode> scanned) {
    return _db.transaction((txn) async {
      final existing = {
        for (final r in await txn.query('episodes', where: 'item_id = ?', whereArgs: [itemId])) r['path'] as String: r,
      };
      final seen = <String>{};
      var added = 0;
      var renumbered = 0;
      final batch = txn.batch();
      for (final e in scanned) {
        seen.add(e.path);
        final row = existing[e.path];
        if (row == null) {
          batch.insert('episodes', _episodeRow(itemId, e), conflictAlgorithm: ConflictAlgorithm.ignore);
          added++;
        } else if (row['season'] != e.season || row['number'] != e.number) {
          batch.update('episodes', {'season': e.season, 'number': e.number}, where: 'id = ?', whereArgs: [row['id']]);
          renumbered++;
        }
      }
      final missing = existing.keys.where((path) => !seen.contains(path)).toList();
      for (final path in missing) {
        batch.delete('episodes', where: 'id = ?', whereArgs: [existing[path]!['id']]);
      }
      await batch.commit(noResult: true);
      return (added, missing.length, renumbered);
    });
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
