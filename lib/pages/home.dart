import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';

import 'package:flutter_acrylic/flutter_acrylic.dart';
import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:flutter_acrylic/widgets/visual_effect_subview_container/visual_effect_subview_container.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

enum InterfaceBrightness {
  light,
  dark,
  auto,
}

extension InterfaceBrightnessExtension on InterfaceBrightness {
  bool getIsDark(BuildContext? context) {
    if (this == InterfaceBrightness.light) return false;
    if (this == InterfaceBrightness.auto) {
      if (context == null) return true;

      return MediaQuery.of(context).platformBrightness == Brightness.dark;
    }

    return true;
  }

  Color getForegroundColor(BuildContext? context) {
    return getIsDark(context) ? Colors.white : Colors.black;
  }
}

class _HomePageState extends State<HomePage> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  static const double titleHeight = 150;
  static const double padding = 8.0;
  static const double tileOpacity = .6;

  BoxDecoration containerDecoration(BuildContext context){
    return BoxDecoration(
      color: Theme.of(context).scaffoldBackgroundColor.withOpacity(tileOpacity),
      borderRadius: BorderRadius.circular(12.0),
    );
  }

  WindowEffect effect = Platform.isWindows ? WindowEffect.acrylic : WindowEffect.transparent;
  Color color = Platform.isWindows ? const Color(0xCC222222) : Colors.transparent;
  InterfaceBrightness brightness =
  Platform.isMacOS ? InterfaceBrightness.auto : InterfaceBrightness.dark;
  MacOSBlurViewState macOSBlurViewState = MacOSBlurViewState.followsWindowActiveState;

  void setWindowEffect(WindowEffect? value) {
    Window.setEffect(
      effect: value!,
      color: color,
      dark: brightness == InterfaceBrightness.dark,
    );
    if (Platform.isMacOS) {
      if (brightness != InterfaceBrightness.auto) {
        Window.overrideMacOSBrightness(
          dark: brightness == InterfaceBrightness.dark,
        );
      }
    }
    setState(() => effect = value);
  }

  void setBrightness(InterfaceBrightness brightness) {
    this.brightness = brightness;
    if (this.brightness == InterfaceBrightness.dark) {
      color = Platform.isWindows ? const Color(0xCC222222) : Colors.transparent;
    } else {
      color = Platform.isWindows ? const Color(0x22DDDDDD) : Colors.transparent;
    }
    setWindowEffect(effect);
  }

  @override
  void initState() {
    super.initState();
    setWindowEffect(effect);
    _controller = AnimationController(vsync: this);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    BoxDecoration decoration = containerDecoration(context);
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        backgroundBlendMode: BlendMode.modulate,
      ),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 50.0, sigmaY: 50.0, tileMode: TileMode.clamp),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.start,
          mainAxisSize: MainAxisSize.max,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 400,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(padding, padding, padding, 0),
                    child: Container(
                      height: titleHeight,
                      width: double.infinity,
                      decoration: decoration,
                      child: const Center(child: Text('__TITLE__')),
                    ),
                  ),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        return Padding(
                          padding: const EdgeInsets.all(padding),
                          child: Container(
                            // color: Theme.of(context).scaffoldBackgroundColor.withOpacity(.8),
                            height: constraints.maxHeight - titleHeight - (padding * 2 * 2) + padding, // Subtract the height of the title container
                            decoration: decoration,
                            child: SingleChildScrollView(
                              child: Column(
                                children: [
                                  ...[0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20]
                                      .map(
                                        (e) => Padding(
                                      padding: const EdgeInsets.all(padding),
                                      child: Container(
                                        height: 100.0,
                                        width: double.infinity,
                                        decoration: BoxDecoration(
                                          color: e % 2 == 0
                                              ? Colors.deepPurpleAccent
                                              : Colors.white12,
                                          borderRadius: BorderRadius.circular(12.0),
                                        ),
                                        child: InkWell(
                                          splashColor: Theme.of(context).primaryColor,
                                          highlightColor: Theme.of(context).highlightColor,
                                          radius: 20,
                                          onTap: (){
                                            print('tapped/clicked $e');
                                          },
                                          child: Row(
                                            children: [
                                              const SizedBox(width: 10),
                                              const Icon(Icons.person, size: 32,),
                                              const SizedBox(width: 10),
                                              Text(
                                                "Anime $e",
                                                style: TextStyle(color: e % 2 == 0 ? Colors.black : Colors.white, fontSize: 22, decoration: TextDecoration.none),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SizedBox(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(0, padding, padding, 0),
                      child: Container(
                        width: double.infinity,
                        height: titleHeight,
                        decoration: decoration,
                        child: const Center(child: Text('__ANIME HEADER__')),
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(0, padding, padding, padding),
                        child: Container(
                          decoration: decoration,
                          child: const Center(child: Text('__MAIN CONTENT__')),
                        ),
                      ),
                    )
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
