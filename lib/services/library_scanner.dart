import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/episode.dart';
import '../models/item.dart';
import 'title_parser.dart';

/// Finds the video files of a show on disk and works out their season and
/// episode numbers.
class LibraryScanner {
  static const videoExtensions = {
    '.mkv',
    '.mp4',
    '.avi',
    '.mov',
    '.wmv',
    '.m4v',
    '.webm',
    '.flv',
    '.ts',
    '.m2ts',
    '.mpg',
    '.mpeg',
  };

  static const _ignoredFolders = {'sample', 'samples', 'featurettes', 'trailers', 'bonus', 'nc', 'ncop', 'nced'};

  static bool isVideo(String path) => videoExtensions.contains(p.extension(path).toLowerCase());

  /// Scans [rootPath] recursively. Season comes from (in order) an
  /// `S01E05`-style file name, the nearest season-named folder
  /// (`Season 2`, `Show.S02.1080p`, `Specials`), the root folder name, or 1.
  static Future<List<ScannedEpisode>> scan(String rootPath) async {
    final root = Directory(rootPath);
    if (!await root.exists()) {
      throw FileSystemException('Folder not found', rootPath);
    }
    final rootSeason = TitleExtractor.seasonFromFolderName(p.basename(rootPath)) ?? 1;

    final files = <String>[];
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File || !isVideo(entity.path)) continue;
      final relative = p.split(p.relative(entity.path, from: rootPath));
      final folders = relative.sublist(0, relative.length - 1);
      if (folders.any((f) => _ignoredFolders.contains(f.toLowerCase()))) continue;
      if (RegExp(
        r'(^|[\s._-])sample([\s._-]|$)',
        caseSensitive: false,
      ).hasMatch(p.basenameWithoutExtension(entity.path))) {
        continue;
      }
      files.add(entity.path);
    }
    return assign(rootPath, files, rootSeason: rootSeason);
  }

  /// Scan for the startup rescan ([LibraryRepository.syncAll]): returns
  /// null, leaving the item untouched, when its folder is missing (e.g. an
  /// unplugged drive) or when a folder that had episodes now has none, which
  /// usually means a drive or network share is only partly available —
  /// syncing that would wipe the show's episodes and watch history.
  static Future<List<ScannedEpisode>?> rescan(LibraryEntry entry) async {
    if (!await Directory(entry.item.rootPath).exists()) return null;
    final episodes = await scan(entry.item.rootPath);
    if (episodes.isEmpty && entry.episodeCount > 0) return null;
    return episodes;
  }

  /// Assigns season/episode numbers to [files] under [rootPath]. Split out
  /// from [scan] so the numbering rules can be tested without a filesystem.
  static List<ScannedEpisode> assign(String rootPath, List<String> files, {int rootSeason = 1}) {
    final bySeason = <int, List<(String, int?)>>{};
    for (final path in files) {
      final parsed = EpisodeParser.parse(p.basename(path));
      final season = parsed.season ?? _folderSeason(rootPath, path) ?? rootSeason;
      bySeason.putIfAbsent(season, () => []).add((path, parsed.episode));
    }

    final result = <ScannedEpisode>[];
    for (final season in bySeason.keys.toList()..sort()) {
      final entries = bySeason[season]!..sort((a, b) => naturalCompare(p.basename(a.$1), p.basename(b.$1)));
      final used = <int>{};
      final unnumbered = <String>[];
      for (final (path, number) in entries) {
        if (number != null && used.add(number)) {
          result.add(ScannedEpisode(season: season, number: number, path: path));
        } else {
          unnumbered.add(path);
        }
      }
      // Files without a usable number go after the highest numbered one.
      var next = used.isEmpty ? 1 : used.reduce((a, b) => a > b ? a : b) + 1;
      for (final path in unnumbered) {
        result.add(ScannedEpisode(season: season, number: next++, path: path));
      }
    }
    result.sort((a, b) => a.season != b.season ? a.season.compareTo(b.season) : a.number.compareTo(b.number));
    return result;
  }

  /// Season from the closest folder between [rootPath] and the file.
  static int? _folderSeason(String rootPath, String filePath) {
    final folders = p.split(p.relative(p.dirname(filePath), from: rootPath));
    for (final folder in folders.reversed) {
      if (folder == '.') continue;
      final season = TitleExtractor.seasonFromFolderName(folder);
      if (season != null) return season;
    }
    return null;
  }

  /// Compares strings so that "Ep 2" sorts before "Ep 10".
  static int naturalCompare(String a, String b) {
    final chunk = RegExp(r'\d+|\D+');
    final ca = chunk.allMatches(a.toLowerCase()).map((m) => m.group(0)!).toList();
    final cb = chunk.allMatches(b.toLowerCase()).map((m) => m.group(0)!).toList();
    for (var i = 0; i < ca.length && i < cb.length; i++) {
      final na = int.tryParse(ca[i]);
      final nb = int.tryParse(cb[i]);
      final c = na != null && nb != null ? na.compareTo(nb) : ca[i].compareTo(cb[i]);
      if (c != 0) return c;
    }
    return ca.length.compareTo(cb.length);
  }
}
