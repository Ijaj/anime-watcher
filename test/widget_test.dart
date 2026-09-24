import 'dart:io';

import 'package:anime_watcher/components/add_item_dialog.dart';
import 'package:anime_watcher/components/bulk_import_dialog.dart';
import 'package:anime_watcher/components/library_sidebar.dart';
import 'package:anime_watcher/data/app_database.dart';
import 'package:anime_watcher/data/library_repository.dart';
import 'package:anime_watcher/models/episode.dart';
import 'package:anime_watcher/models/item.dart';
import 'package:anime_watcher/pages/home.dart';
import 'package:anime_watcher/pages/settings_page.dart';
import 'package:anime_watcher/services/mal_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'fakes.dart';

void main() {
  late LibraryRepository repo;

  setUpAll(sqfliteFfiInit);

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('com.alexmercerind/flutter_acrylic'), (_) async => null);
  });

  /// The database runs on a real isolate, so let it answer outside fake time.
  Future<void> settle(WidgetTester tester, {int rounds = 5}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
  }

  /// Like [settle], but keeps going (up to ~5 s) until [finder] matches.
  Future<void> settleUntil(WidgetTester tester, Finder finder) async {
    for (var i = 0; i < 100 && finder.evaluate().isEmpty; i++) {
      await settle(tester, rounds: 1);
    }
  }

  Future<void> pumpApp(WidgetTester tester, Widget home) async {
    tester.view.physicalSize = const Size(1333, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(theme: ThemeData(brightness: Brightness.dark, useMaterial3: true), home: home));
    await settle(tester);
  }

  testWidgets('empty library shows the empty state', (tester) async {
    await tester.runAsync(() async => repo = LibraryRepository(await AppDatabase.open(path: inMemoryDatabasePath)));
    await pumpApp(tester, HomePage(repository: repo, malClient: MalClient(), autoRescan: false));

    expect(find.textContaining('Your library is empty'), findsOneWidget);
    expect(find.text('Click + to add a show folder.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('library item shows the continue shelf, then header, seasons and next-up episode', (tester) async {
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
    await pumpApp(tester, HomePage(repository: repo, malClient: MalClient(), autoRescan: false));

    // Nothing selected: the home view shows the continue-watching shelf.
    expect(find.text('Continue watching'), findsOneWidget);
    expect(find.text('S01E02 · 19:00 left'), findsOneWidget);
    expect(find.text('Frieren'), findsNWidgets(2)); // sidebar + shelf card
    expect(tester.takeException(), isNull);

    await tester.tap(find.descendant(of: find.byType(LibrarySidebar), matching: find.text('Frieren')));
    await settle(tester);

    expect(find.text('Continue watching'), findsNothing);
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
    await pumpApp(tester, HomePage(repository: repo, malClient: MalClient(), autoRescan: false));

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
    // FilledButton.icon is a private subclass on older Flutter versions, so match by `is`, not by exact type.
    final addButton = tester.widget<FilledButton>(find.ancestor(
        of: find.text('Add Without Metadata'), matching: find.byWidgetPredicate((w) => w is FilledButton)));
    expect(addButton.onPressed, isNull, reason: 'nothing selected yet');
    expect(tester.takeException(), isNull);
  });

  testWidgets('bulk import reviews sub-folders and adds the chosen ones', (tester) async {
    late Directory tmp;
    await tester.runAsync(() async {
      repo = LibraryRepository(await AppDatabase.open(path: inMemoryDatabasePath));
      tmp = await Directory.systemTemp.createTemp('bulk_widget');
      for (final f in ['Frieren/01.mkv', 'Mob Psycho 100/01.mkv', 'Empty/notes.txt']) {
        await File(p.join(tmp.path, f)).create(recursive: true);
      }
    });
    addTearDown(() => tmp.deleteSync(recursive: true));
    final mal = FakeMalClient({
      'frieren': const [MalSearchResult(id: 1, title: 'Sousou no Frieren')],
    });
    await pumpApp(tester, Scaffold(body: BulkImportDialog(repository: repo, malClient: mal)));

    await tester.enterText(find.byType(TextField), tmp.path);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settleUntil(tester, find.text('Add 2 Shows'));

    expect(find.text('3 new folders'), findsOneWidget);
    expect(find.text('Sousou no Frieren'), findsOneWidget);
    expect(find.text('No metadata — add as "Mob Psycho 100"'), findsOneWidget);
    expect(find.textContaining('No video files'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Add 2 Shows'));
    List<String>? titles;
    for (var i = 0; i < 100 && (titles?.length ?? 0) < 2; i++) {
      await settle(tester, rounds: 1);
      titles = await tester.runAsync(() async => [for (final e in await repo.entries()) e.item.title]);
    }
    expect(titles, ['Mob Psycho 100', 'Sousou no Frieren']);
  });

  testWidgets('startup rescan adds new files and reports it once', (tester) async {
    late Directory tmp;
    await tester.runAsync(() async {
      repo = LibraryRepository(await AppDatabase.open(path: inMemoryDatabasePath));
      tmp = await Directory.systemTemp.createTemp('rescan_widget');
      for (final f in ['Show - 01.mkv', 'Show - 02.mkv']) {
        await File(p.join(tmp.path, f)).create();
      }
      await repo.addItem(LibraryItem(type: MediaType.anime, title: 'Show', rootPath: tmp.path),
          [ScannedEpisode(season: 1, number: 1, path: p.join(tmp.path, 'Show - 01.mkv'))]);
      await repo.addItem(LibraryItem(type: MediaType.anime, title: 'Unplugged', rootPath: p.join(tmp.path, 'nope')),
          const [ScannedEpisode(season: 1, number: 1, path: '/nope/1.mkv')]);
    });
    addTearDown(() => tmp.deleteSync(recursive: true));
    await pumpApp(tester, HomePage(repository: repo, malClient: MalClient()));

    final snack = find.text('Library updated in 1 show. New: 1 episode · 1 folder unavailable');
    await settleUntil(tester, snack);
    expect(snack, findsOneWidget);
    expect(find.text('0/2'), findsOneWidget, reason: 'Show now has 2 episodes');
    expect(tester.takeException(), isNull);
  });

  testWidgets('settings page saves the client ID and clears history', (tester) async {
    late int episodeId;
    await tester.runAsync(() async {
      repo = LibraryRepository(await AppDatabase.open(path: inMemoryDatabasePath));
      final item = await repo.addItem(LibraryItem(type: MediaType.anime, title: 'Show', rootPath: '/show'),
          const [ScannedEpisode(season: 1, number: 1, path: '/show/1.mkv')]);
      episodeId = (await repo.episodes(item.id!)).single.id!;
      await repo.setWatched(episodeId, true);
    });
    final mal = MalClient();
    await pumpApp(tester, SettingsPage(repository: repo, malClient: mal));

    expect(find.text('Using the built-in client ID'), findsOneWidget);
    expect(find.text('Mark an episode as watched after 90 % of it has played'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.enterText(find.widgetWithText(TextField, 'Client ID'), 'my-id');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await settle(tester);
    expect(mal.clientId, 'my-id');
    expect(find.text('Using your client ID'), findsOneWidget);

    await tester.tap(find.text('Clear Watch History'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear History'));
    await settleUntil(tester, find.text('Watch history cleared'));
    final eps = await tester.runAsync(() => repo.episodes(1));
    expect(eps!.single.progress, isNull);
    expect(find.text('Watch history cleared'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
