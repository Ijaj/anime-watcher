import 'dart:io';

import 'package:path/path.dart' as p;

import '../data/library_repository.dart';
import '../models/episode.dart';
import '../models/item.dart';
import 'library_scanner.dart';
import 'mal_client.dart';
import 'title_parser.dart';

/// One show folder found by a bulk import, with its scan and MAL match.
class ImportCandidate {
  final String path;

  /// Title parsed from the folder name; used when there is no MAL match.
  final String folderTitle;
  final List<ScannedEpisode> episodes;
  List<MalSearchResult> matches;

  /// The chosen MAL entry, or null to add with [folderTitle] only.
  MalSearchResult? match;
  bool include;

  /// Why scanning or matching failed, if it did.
  String? error;

  ImportCandidate({
    required this.path,
    required this.folderTitle,
    this.episodes = const [],
    this.matches = const [],
    this.match,
    bool? include,
    this.error,
  }) : include = include ?? episodes.isNotEmpty;

  String get folderName => p.basename(path);

  /// Title the item will be saved under.
  String get title => match?.title ?? folderTitle;
}

class BulkImportResult {
  final int added;
  final List<String> failures;

  const BulkImportResult(this.added, this.failures);
}

/// Adds every show folder inside a parent folder: lists the sub-folders,
/// scans and auto-matches each one, then saves the ones the user keeps.
class BulkImporter {
  static const _systemFolders = {'system volume information', r'$recycle.bin', 'lost+found'};

  final LibraryRepository repository;
  final MalClient malClient;

  BulkImporter(this.repository, this.malClient);

  /// Immediate sub-folders of [parent] that are not in the library yet, in
  /// natural name order, plus how many were skipped because they are.
  /// Hidden and system folders are ignored.
  Future<(List<String>, int)> showFolders(String parent) async {
    final dir = Directory(parent);
    if (!await dir.exists()) throw FileSystemException('Folder not found', parent);
    final folders = <String>[];
    var existing = 0;
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! Directory) continue;
      final name = p.basename(entity.path);
      if (name.startsWith('.') || _systemFolders.contains(name.toLowerCase())) continue;
      if (await repository.containsPath(entity.path)) {
        existing++;
      } else {
        folders.add(entity.path);
      }
    }
    folders.sort((a, b) => LibraryScanner.naturalCompare(p.basename(a), p.basename(b)));
    return (folders, existing);
  }

  /// Scans [path] and picks the top MAL search result for its title. Never
  /// throws: failures are recorded in [ImportCandidate.error]. Folders
  /// without video files start excluded; a failed MAL lookup does not
  /// exclude the folder (it can still be added without metadata).
  Future<ImportCandidate> prepare(String path) async {
    final parsed = TitleExtractor.extract(p.basename(path));
    final title = parsed.title.isEmpty ? p.basename(path) : parsed.title;
    final List<ScannedEpisode> episodes;
    try {
      episodes = await LibraryScanner.scan(path);
    } on FileSystemException catch (e) {
      return ImportCandidate(path: path, folderTitle: title, error: 'Could not scan: ${e.message}');
    }
    if (episodes.isEmpty) {
      return ImportCandidate(path: path, folderTitle: title, error: 'No video files');
    }
    try {
      final matches = await malClient.search(title);
      return ImportCandidate(
        path: path,
        folderTitle: title,
        episodes: episodes,
        matches: matches,
        match: matches.isEmpty ? null : matches.first,
        error: matches.isEmpty ? 'No MyAnimeList match' : null,
      );
    } on MalException catch (e) {
      return ImportCandidate(path: path, folderTitle: title, episodes: episodes, error: e.message);
    }
  }

  /// Saves every included candidate. Full MAL details are fetched for
  /// matched ones; if that fails the item is saved from the search result.
  Future<BulkImportResult> addAll(List<ImportCandidate> candidates, {void Function(int done)? onProgress}) async {
    var added = 0;
    var done = 0;
    final failures = <String>[];
    for (final c in candidates) {
      if (!c.include) continue;
      try {
        await repository.addItem(await _toItem(c), c.episodes);
        added++;
      } on DuplicateItemException {
        failures.add('${c.folderName}: already in the library');
      } catch (e) {
        failures.add('${c.folderName}: $e');
      }
      onProgress?.call(++done);
    }
    return BulkImportResult(added, failures);
  }

  Future<LibraryItem> _toItem(ImportCandidate c) async {
    final match = c.match;
    if (match == null) return LibraryItem(type: MediaType.anime, title: c.folderTitle, rootPath: c.path);
    try {
      return LibraryItem.fromMal(await malClient.details(match.id), rootPath: c.path);
    } on MalException {
      return LibraryItem(
        malId: match.id,
        type: MediaType.anime,
        title: match.title,
        rootPath: c.path,
        imageMedium: match.imageMedium,
      );
    }
  }
}
