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
