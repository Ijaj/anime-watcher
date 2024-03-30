import 'package:anime_watcher/pages/home.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:json_theme/json_theme.dart';
import 'dart:convert'; // For jsonDecode
import 'package:flutter_acrylic/flutter_acrylic.dart';
import 'dart:io';
import 'package:bitsdojo_window/bitsdojo_window.dart';


void main() async{
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  final themeStr = await rootBundle.loadString('assets/purple_dark.json');
  final themeJson = jsonDecode(themeStr);
  final theme = ThemeDecoder.decodeThemeData(themeJson)!;
  Window.initialize();
  if (Platform.isWindows) {
    // await Window.hideWindowControls();
  }
  runApp(MyApp(theme: theme));
  if (Platform.isWindows) {
    doWhenWindowReady(() {
      appWindow
        ..minSize = const Size(640, 360)
        ..size = const Size(720, 540)
        ..alignment = Alignment.center
        ..show();
    });
  }

}

class MyApp extends StatelessWidget {
  final ThemeData theme;
  const MyApp({super.key, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
        shortcuts: <LogicalKeySet, Intent>{
          LogicalKeySet(LogicalKeyboardKey.select): const ActivateIntent(),
        },
        child: MaterialApp(
          title: 'Better player demo',
          supportedLocales: const [
            Locale('en', 'US'),
            Locale('pl', 'PL'),
          ],
          theme: ThemeData(
            colorSchemeSeed: const Color(0x00006c7b),
            brightness: Brightness.light,
            useMaterial3: true
          ),
          darkTheme: ThemeData(
              colorSchemeSeed: const Color(0x00006c7b),
              brightness: Brightness.dark,
              useMaterial3: true
          ),
          home: const Scaffold(
            backgroundColor: Colors.transparent,
            body: HomePage(),
          ),
        )
    );
  }
}
