import 'package:anime_watcher/components/add_item_dialog.dart';
import 'package:anime_watcher/data/app_database.dart';
import 'package:anime_watcher/data/library_repository.dart';
import 'package:anime_watcher/models/episode.dart';
import 'package:anime_watcher/models/item.dart';
import 'package:anime_watcher/pages/home.dart';
import 'package:anime_watcher/services/mal_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late LibraryRepository repo;

  setUpAll(sqfliteFfiInit);

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('com.alexmercerind/flutter_acrylic'), (_) async => null);
  });

  Future<void> pumpApp(WidgetTester tester, Widget home) async {
    tester.view.physicalSize = const Size(1333, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(theme: ThemeData(brightness: Brightness.dark, useMaterial3: true), home: home));
    // The database runs on a real isolate, so let it answer outside fake time.
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
  }

  testWidgets('empty library shows the empty state', (tester) async {
    await tester.runAsync(() async => repo = LibraryRepository(await AppDatabase.open(path: inMemoryDatabasePath)));
    await pumpApp(tester, HomePage(repository: repo, malClient: MalClient()));

    expect(find.textContaining('Your library is empty'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('library item shows header, seasons and next-up episode', (tester) async {
    await tester.runAsync(() async {
      repo = LibraryRepository(await AppDatabase.open(path: inMemoryDatabasePath));
      final item = await repo.addItem(
        LibraryItem(
          type: MediaType.anime,
          title: 'Frieren',
          rootPath: '/frieren',
          genres: ['Adventure', 'Fantasy'],
          totalEpisodes: 28,
          score: 9.3,
          synopsis: 'An elf mage outlives her party.',
        ),
        const [
          ScannedEpisode(season: 1, number: 1, path: '/frieren/e1.mkv'),
          ScannedEpisode(season: 1, number: 2, path: '/frieren/e2.mkv'),
          ScannedEpisode(season: 0, number: 1, path: '/frieren/sp1.mkv'),
        ],
      );
      final eps = await repo.episodes(item.id!);
      await repo.setWatched(eps.first.id!, true);
      await repo.saveProgress(eps[1].id!, position: const Duration(minutes: 5), duration: const Duration(minutes: 24));
    });
    await pumpApp(tester, HomePage(repository: repo, malClient: MalClient()));

    expect(find.text('Frieren'), findsNWidgets(2)); // sidebar + header
    expect(find.text('Season 1'), findsOneWidget);
    expect(find.text('Specials'), findsOneWidget);
    expect(find.text('Continue S01E02'), findsOneWidget);
    expect(find.text('1 / 3 watched'), findsOneWidget);
    expect(find.text('05:00 / 24:00'), findsOneWidget);
    expect(find.text('Adventure'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sidebar search filters the library', (tester) async {
    await tester.runAsync(() async {
      repo = LibraryRepository(await AppDatabase.open(path: inMemoryDatabasePath));
      for (final title in ['Frieren', 'Mob Psycho 100', 'One Piece']) {
        await repo.addItem(LibraryItem(type: MediaType.anime, title: title, rootPath: '/$title'), const []);
      }
    });
    await pumpApp(tester, HomePage(repository: repo, malClient: MalClient()));

    await tester.enterText(find.widgetWithText(TextField, 'Search library'), 'psycho');
    await tester.pump();
    expect(find.text('Mob Psycho 100'), findsWidgets);
    expect(find.text('One Piece'), findsNothing);

    await tester.enterText(find.widgetWithText(TextField, 'Search library'), 'zzz');
    await tester.pump();
    expect(find.text('No shows match your search.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('add dialog lays out without overflow', (tester) async {
    await tester.runAsync(() async => repo = LibraryRepository(await AppDatabase.open(path: inMemoryDatabasePath)));
    await pumpApp(tester, Scaffold(body: AddItemDialog(repository: repo, malClient: MalClient())));

    expect(find.text('Add to Library'), findsOneWidget);
    final addButton = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Add Without Metadata'));
    expect(addButton.onPressed, isNull, reason: 'nothing selected yet');
    expect(tester.takeException(), isNull);
  });
}
