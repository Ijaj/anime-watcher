import 'dart:io';

import 'package:anime_watcher/data/app_database.dart';
import 'package:anime_watcher/data/library_repository.dart';
import 'package:anime_watcher/models/item.dart';
import 'package:anime_watcher/services/bulk_importer.dart';
import 'package:anime_watcher/services/mal_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'fakes.dart';

void main() {
  late Directory tmp;
  late LibraryRepository repo;
  final mal = FakeMalClient({
    'frieren': const [MalSearchResult(id: 1, title: 'Sousou no Frieren'), MalSearchResult(id: 2, title: 'Frieren 2')],
    'mob psycho': const [MalSearchResult(id: 3, title: 'Mob Psycho 100 III')],
  });

  setUpAll(sqfliteFfiInit);
  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('bulk_test');
    repo = LibraryRepository(await AppDatabase.open(path: inMemoryDatabasePath));
  });
  tearDown(() async {
    await repo.close();
    await tmp.delete(recursive: true);
  });

  Future<String> show(String name, [List<String> files = const ['01.mkv']]) async {
    for (final f in files) {
      await File(p.join(tmp.path, name, f)).create(recursive: true);
    }
    if (files.isEmpty) await Directory(p.join(tmp.path, name)).create(recursive: true);
    return p.join(tmp.path, name);
  }

  test('showFolders skips library, hidden and system folders and sorts naturally', () async {
    await show('Show 10');
    await show('Show 2');
    await show('.hidden');
    await show(r'$RECYCLE.BIN');
    final existing = await show('Already Added');
    await File(p.join(tmp.path, 'loose.mkv')).create();
    await repo.addItem(LibraryItem(type: MediaType.anime, title: 'x', rootPath: existing), const []);

    final (folders, skipped) = await BulkImporter(repo, mal).showFolders(tmp.path);
    expect(folders.map(p.basename), ['Show 2', 'Show 10']);
    expect(skipped, 1);
  });

  test('showFolders throws for a missing folder', () {
    expect(BulkImporter(repo, mal).showFolders(p.join(tmp.path, 'nope')), throwsA(isA<FileSystemException>()));
  });

  test('prepare scans and picks the top match', () async {
    final c = await BulkImporter(repo, mal).prepare(await show('[Grp] Frieren S01 1080p', ['01.mkv', '02.mkv']));
    expect(c.folderTitle, 'Frieren');
    expect(c.episodes, hasLength(2));
    expect(c.match?.id, 1);
    expect(c.matches, hasLength(2));
    expect(c.include, isTrue);
    expect(c.error, isNull);
  });

  test('prepare keeps unmatched folders but excludes ones without videos', () async {
    final importer = BulkImporter(repo, mal);
    final unmatched = await importer.prepare(await show('Unknown Show'));
    expect(unmatched.match, isNull);
    expect(unmatched.include, isTrue);
    expect(unmatched.title, 'Unknown Show');
    expect(unmatched.error, 'No MyAnimeList match');

    final empty = await importer.prepare(await show('Empty', const []));
    expect(empty.include, isFalse);
    expect(empty.error, 'No video files');
  });

  test('addAll saves included candidates with MAL details, falling back to the search result', () async {
    final importer = BulkImporter(repo, mal);
    final frieren = await importer.prepare(await show('Frieren'));
    final mob = await importer.prepare(await show('Mob Psycho 100 S03'));
    final plain = await importer.prepare(await show('Home Videos'));
    final skipped = await importer.prepare(await show('Skipped Show'))
      ..include = false;
    frieren.match = frieren.matches[1]; // user picked a different match

    var progress = 0;
    final result = await importer.addAll([frieren, mob, plain, skipped], onProgress: (n) => progress = n);
    expect(result.added, 3);
    expect(result.failures, isEmpty);
    expect(progress, 3);

    final entries = await repo.entries();
    expect(entries.map((e) => e.item.title), ['Frieren 2', 'Home Videos', 'Mob Psycho 100 III']);
    expect(entries.first.item.genres, ['Action']);
    expect(entries.first.episodeCount, 1);

    final offline =
        await BulkImporter(repo, FakeMalClient(mal.results, failDetails: true)).prepare(await show('Frieren Again'));
    final second = await BulkImporter(repo, FakeMalClient(mal.results, failDetails: true)).addAll([offline, frieren]);
    expect(second.added, 1);
    expect(second.failures.single, contains('already in the library'));
    final saved = (await repo.entries()).firstWhere((e) => e.item.rootPath == offline.path).item;
    expect((saved.title, saved.malId), ('Sousou no Frieren', 1));
    expect(saved.genres, isEmpty, reason: 'details failed, so only search-result fields are saved');
  });
}
