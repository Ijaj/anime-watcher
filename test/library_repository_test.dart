import 'dart:io';

import 'package:anime_watcher/config.dart';
import 'package:anime_watcher/data/app_database.dart';
import 'package:anime_watcher/data/library_repository.dart';
import 'package:anime_watcher/models/episode.dart';
import 'package:anime_watcher/models/item.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late LibraryRepository repo;

  setUpAll(sqfliteFfiInit);
  setUp(() async => repo = LibraryRepository(await AppDatabase.open(path: inMemoryDatabasePath)));
  tearDown(() => repo.close());

  LibraryItem item(String root) =>
      LibraryItem(type: MediaType.anime, title: 'Show', rootPath: root, genres: ['Action']);
  const scanned = [
    ScannedEpisode(season: 1, number: 1, path: '/show/e1.mkv'),
    ScannedEpisode(season: 1, number: 2, path: '/show/e2.mkv'),
    ScannedEpisode(season: 0, number: 1, path: '/show/sp1.mkv'),
  ];

  test('add, list and remove', () async {
    final saved = await repo.addItem(item('/show'), scanned);
    expect(saved.id, isNotNull);

    final entries = await repo.entries();
    expect(entries.single.item.genres, ['Action']);
    expect(entries.single.episodeCount, 3);

    final eps = await repo.episodes(saved.id!);
    expect(eps.map((e) => e.code), ['S01E01', 'S01E02', 'SP01'], reason: 'specials sort last');

    await expectLater(repo.addItem(item('/show'), const []), throwsA(isA<DuplicateItemException>()));

    await repo.removeItem(saved.id!);
    expect(await repo.entries(), isEmpty);
  });

  test('progress becomes completed at the threshold and stays completed', () async {
    final saved = await repo.addItem(item('/show'), scanned);
    final ep = (await repo.episodes(saved.id!)).first;

    await repo.saveProgress(ep.id!, position: const Duration(minutes: 10), duration: const Duration(minutes: 24));
    var p = (await repo.episodes(saved.id!)).first.progress!;
    expect(p.completed, isFalse);
    expect(p.position, const Duration(minutes: 10));

    await repo.saveProgress(ep.id!, position: const Duration(minutes: 22), duration: const Duration(minutes: 24));
    await repo.saveProgress(ep.id!, position: const Duration(minutes: 1), duration: const Duration(minutes: 24));
    p = (await repo.episodes(saved.id!)).first.progress!;
    expect(p.completed, isTrue);
    expect((await repo.entries()).single.watchedCount, 1);

    await repo.setWatched(ep.id!, false);
    expect((await repo.episodes(saved.id!)).first.progress, isNull);
  });

  test('watched threshold is configurable and persisted', () async {
    final saved = await repo.addItem(item('/show'), scanned);
    final ep = (await repo.episodes(saved.id!)).first;
    await repo.setWatchedThreshold(0.5);
    await repo.saveProgress(ep.id!, position: const Duration(minutes: 13), duration: const Duration(minutes: 24));
    expect((await repo.episodes(saved.id!)).first.completed, isTrue);

    await repo.setWatchedThreshold(0.1);
    expect(repo.watchedThreshold, LibraryRepository.minWatchedThreshold, reason: 'clamped');
    await repo.setWatchedThreshold(0.8);
    expect(await repo.setting(LibraryRepository.watchedThresholdKey), '0.8');
  });

  test('loadSettings reads the stored threshold', () async {
    expect(repo.watchedThreshold, AppConfig.watchedThreshold);
    await repo.setSetting(LibraryRepository.watchedThresholdKey, '0.75');
    await repo.loadSettings();
    expect(repo.watchedThreshold, 0.75);
    await repo.setSetting(LibraryRepository.watchedThresholdKey, 'garbage');
    await repo.loadSettings();
    expect(repo.watchedThreshold, AppConfig.watchedThreshold);
  });

  test('MAL client ID override falls back to the default', () async {
    expect(await repo.malClientId(), AppConfig.malClientId);
    await repo.setMalClientId('  abc123 ');
    expect(await repo.malClientIdOverride(), 'abc123');
    expect(await repo.malClientId(), 'abc123');
    await repo.setMalClientId('   ');
    expect(await repo.malClientIdOverride(), isNull);
    expect(await repo.malClientId(), AppConfig.malClientId);
  });

  test('clearWatchHistory forgets all progress', () async {
    final saved = await repo.addItem(item('/show'), scanned);
    final eps = await repo.episodes(saved.id!);
    await repo.setWatched(eps[0].id!, true);
    await repo.saveProgress(eps[1].id!, position: const Duration(minutes: 3), duration: const Duration(minutes: 24));
    var notified = false;
    repo.addListener(() => notified = true);

    await repo.clearWatchHistory();
    expect((await repo.episodes(saved.id!)).every((e) => e.progress == null), isTrue);
    expect((await repo.entries()).single.watchedCount, 0);
    expect(notified, isTrue);
  });

  test('syncEpisodes adds new files and drops missing ones', () async {
    final saved = await repo.addItem(item('/show'), scanned);
    final (added, removed) = await repo.syncEpisodes(saved.id!, const [
      ScannedEpisode(season: 1, number: 1, path: '/show/e1.mkv'),
      ScannedEpisode(season: 1, number: 3, path: '/show/e2.mkv'),
      ScannedEpisode(season: 1, number: 4, path: '/show/e4.mkv'),
    ]);
    expect((added, removed), (1, 1));
    final eps = await repo.episodes(saved.id!);
    expect(eps.map((e) => e.code), ['S01E01', 'S01E03', 'S01E04']);
  });

  test('syncAll syncs every item, skips unavailable ones and notifies once', () async {
    final a = await repo.addItem(item('/a'), const [ScannedEpisode(season: 1, number: 1, path: '/a/1.mkv')]);
    await repo.addItem(item('/b'), const [ScannedEpisode(season: 1, number: 1, path: '/b/1.mkv')]);
    await repo.addItem(item('/gone'), const [ScannedEpisode(season: 1, number: 1, path: '/gone/1.mkv')]);
    await repo.addItem(item('/broken'), const []);
    var notified = 0;
    repo.addListener(() => notified++);

    final summary = await repo.syncAll(
      (entry) async => switch (entry.item.rootPath) {
        '/a' => const [
          ScannedEpisode(season: 1, number: 1, path: '/a/1.mkv'),
          ScannedEpisode(season: 1, number: 2, path: '/a/2.mkv'),
          ScannedEpisode(season: 1, number: 3, path: '/a/3.mkv'),
        ],
        '/b' => const [],
        '/broken' => throw const FileSystemException('denied'),
        _ => null,
      },
    );
    expect((summary.added, summary.removed, summary.changedShows, summary.unavailable), (2, 1, 2, 2));
    expect(summary.changed, isTrue);
    expect(notified, 1);
    expect((await repo.episodes(a.id!)).length, 3);
    final gone = (await repo.entries()).firstWhere((e) => e.item.rootPath == '/gone');
    expect(gone.episodeCount, 1, reason: 'unavailable folders keep their episodes');

    final unchanged = await repo.syncAll((entry) async => null);
    expect(unchanged.changed, isFalse);
    expect(notified, 1, reason: 'no change, no notification');
  });

  test('RescanSummary.describe', () {
    expect(
      const RescanSummary(added: 3, removed: 1, changedShows: 2, unavailable: 1).describe(),
      'Library updated in 2 shows. New: 3 episodes, removed: 1 episode · 1 folder unavailable',
    );
    expect(const RescanSummary(added: 1, changedShows: 1).describe(), 'Library updated in 1 show. New: 1 episode');
  });

  test('entries report when an item was last watched', () async {
    final a = await repo.addItem(item('/a'), const [ScannedEpisode(season: 1, number: 1, path: '/a/1.mkv')]);
    await repo.addItem(item('/b'), const [ScannedEpisode(season: 1, number: 1, path: '/b/1.mkv')]);
    final ep = (await repo.episodes(a.id!)).single;
    await repo.saveProgress(ep.id!, position: const Duration(minutes: 1), duration: const Duration(minutes: 24));

    final entries = await repo.entries();
    expect(entries.firstWhere((e) => e.item.rootPath == '/a').lastWatchedAt, isNotNull);
    expect(entries.firstWhere((e) => e.item.rootPath == '/b').lastWatchedAt, isNull);
  });

  test('continueWatching lists next-up episodes, most recently watched show first', () async {
    Future<List<Episode>> add(String root, int count) async {
      final saved = await repo.addItem(item(root), [
        for (var n = 1; n <= count; n++) ScannedEpisode(season: 1, number: n, path: '$root/$n.mkv'),
      ]);
      return repo.episodes(saved.id!);
    }

    expect(await repo.continueWatching(), isEmpty);
    final a = await add('/a', 3);
    final b = await add('/b', 2);
    final done = await add('/done', 1);
    await add('/untouched', 2);

    await repo.setWatched(a[0].id!, true);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await repo.setWatched(done[0].id!, true);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await repo.saveProgress(b[1].id!, position: const Duration(minutes: 3), duration: const Duration(minutes: 24));

    final shelf = await repo.continueWatching();
    expect(
      [for (final c in shelf) '${c.entry.item.rootPath} ${c.episode.code}'],
      ['/b S01E02', '/a S01E02'],
      reason: 'fully watched and never-watched shows are left out',
    );
    expect(shelf.first.episode.progress!.position, const Duration(minutes: 3));
  });

  group('filterAndSort', () {
    LibraryEntry entry(String title, {int added = 0, int? watched}) => LibraryEntry(
      item: LibraryItem(
        type: MediaType.anime,
        title: title,
        rootPath: '/$title',
        addedAt: DateTime.fromMillisecondsSinceEpoch(added),
      ),
      episodeCount: 1,
      watchedCount: 0,
      lastWatchedAt: watched == null ? null : DateTime.fromMillisecondsSinceEpoch(watched),
    );
    final entries = [
      entry('Kaguya-sama: Love Is War', added: 3, watched: 10),
      entry('attack on titan', added: 1),
      entry('Frieren', added: 2, watched: 20),
    ];
    List<String> titles(List<LibraryEntry> es) => [for (final e in es) e.item.title];

    test('title sort is case-insensitive', () {
      expect(titles(LibraryRepository.filterAndSort(entries)), [
        'attack on titan',
        'Frieren',
        'Kaguya-sama: Love Is War',
      ]);
    });
    test('recently watched first, never-watched last by title', () {
      expect(titles(LibraryRepository.filterAndSort(entries, sort: LibrarySort.recentlyWatched)), [
        'Frieren',
        'Kaguya-sama: Love Is War',
        'attack on titan',
      ]);
    });
    test('recently added first', () {
      expect(titles(LibraryRepository.filterAndSort(entries, sort: LibrarySort.recentlyAdded)), [
        'Kaguya-sama: Love Is War',
        'Frieren',
        'attack on titan',
      ]);
    });
    test('query matches every word, ignoring case and punctuation', () {
      expect(titles(LibraryRepository.filterAndSort(entries, query: 'KAGUYA sama war')), ['Kaguya-sama: Love Is War']);
      expect(titles(LibraryRepository.filterAndSort(entries, query: 'kaguya-sama')), ['Kaguya-sama: Love Is War']);
      expect(titles(LibraryRepository.filterAndSort(entries, query: 'titan')), ['attack on titan']);
      expect(LibraryRepository.filterAndSort(entries, query: 'naruto'), isEmpty);
      expect(LibraryRepository.filterAndSort(entries, query: '  '), hasLength(3));
    });
  });

  group('nextUp', () {
    Episode ep(int n, {bool done = false, int? touched, int pos = 0}) => Episode(
      id: n,
      itemId: 1,
      season: 1,
      number: n,
      path: '/e$n',
      progress: touched == null
          ? null
          : WatchProgress(
              position: Duration(seconds: pos),
              duration: const Duration(minutes: 24),
              completed: done,
              updatedAt: DateTime.fromMillisecondsSinceEpoch(touched),
            ),
    );

    test('nothing watched → first episode', () {
      expect(LibraryRepository.nextUp([ep(1), ep(2)])!.number, 1);
    });
    test('resumes a partially watched episode', () {
      expect(LibraryRepository.nextUp([ep(1, done: true, touched: 1), ep(2, touched: 2, pos: 60), ep(3)])!.number, 2);
    });
    test('continues after the most recently finished episode', () {
      expect(LibraryRepository.nextUp([ep(1), ep(2, done: true, touched: 5), ep(3)])!.number, 3);
    });
    test('wraps around to an earlier gap', () {
      expect(LibraryRepository.nextUp([ep(1), ep(2, done: true, touched: 5)])!.number, 1);
    });
    test('all watched → null', () {
      expect(LibraryRepository.nextUp([ep(1, done: true, touched: 1)]), isNull);
    });
  });
}
