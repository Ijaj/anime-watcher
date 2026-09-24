import 'dart:io';

import 'package:anime_watcher/data/app_database.dart';
import 'package:anime_watcher/data/library_repository.dart';
import 'package:anime_watcher/pages/home.dart';
import 'package:anime_watcher/services/cover_cache.dart';
import 'package:anime_watcher/services/mal_client.dart';
import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart';
import 'package:media_kit/media_kit.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() async {
  sqfliteFfiInit();
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  await Window.initialize();
  final repository = LibraryRepository(await AppDatabase.open());
  await repository.loadSettings();
  final malClient = MalClient(clientId: await repository.malClientId());

  runApp(MyApp(repository: repository, malClient: malClient, coverCache: await CoverCache.open()));
  if (Platform.isWindows) {
    doWhenWindowReady(() {
      appWindow
        ..minSize = const Size(1333, 768)
        ..size = const Size(1333, 768)
        ..alignment = Alignment.center
        ..show();
    });
  }
}

class MyApp extends StatelessWidget {
  final LibraryRepository repository;
  final MalClient malClient;
  final CoverCache coverCache;

  const MyApp({super.key, required this.repository, required this.malClient, required this.coverCache});

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: <LogicalKeySet, Intent>{
        LogicalKeySet(LogicalKeyboardKey.select): const ActivateIntent(),
      },
      child: MaterialApp(
        title: 'Anime Watcher',
        theme: ThemeData(
          colorSchemeSeed: const Color(0x00006c7b),
          brightness: Brightness.light,
          useMaterial3: true,
        ),
        darkTheme: ThemeData(
          colorSchemeSeed: const Color(0x00006c7b),
          brightness: Brightness.dark,
          useMaterial3: true,
        ),
        // The acrylic window effect is always dark, so match it.
        themeMode: ThemeMode.dark,
        home: HomePage(repository: repository, malClient: malClient, coverCache: coverCache),
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}
