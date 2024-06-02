import 'package:flutter/material.dart';
import 'package:fullscreen_window/fullscreen_window.dart';
import 'package:toastification/toastification.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

class  PlayVideoScreen  extends  StatefulWidget {
  const  PlayVideoScreen({super.key});

  @override
  State<PlayVideoScreen> createState() =>  _PlayVideoScreenState();
}

class  _PlayVideoScreenState extends State<PlayVideoScreen> {
  late final player = Player();
  late final controller = VideoController(player);
  String screenSizeText = "";

  void setFullScreen(bool isFullScreen) {
    FullScreenWindow.setFullScreen(isFullScreen);
  }

  void showScreenSize(BuildContext context) async {
    Size logicalSize = await FullScreenWindow.getScreenSize(context);
    Size physicalSize = await FullScreenWindow.getScreenSize(null);
    setState(() {
      screenSizeText = "Screen size (logical pixel): ${logicalSize.width} x ${logicalSize.height}\n";
      screenSizeText += "Screen size (physical pixel): ${physicalSize.width} x ${physicalSize.height}\n";
      toastification.show(
        context: context,
        title: Text(screenSizeText),
        autoCloseDuration: const Duration(seconds: 5),
      );
    });
  }

  @override
  void  initState() {
    super.initState();
    // player.open(Media('https://user-images.githubusercontent.com/28951144/229373695-22f88f13-d18f-4288-9bf1-c3e078d83722.mp4'));
    // player.open(Media('H:\\3.Body.Problem.S01.1080p.NF.WEB-DL.DDP5.1.Atmos.H.264-FLUX\\3.Body.Problem.S01E03.Destroyer.of.Worlds.1080p.NF.WEB-DL.DDP5.1.Atmos.H.264-FLUX.mkv'));
  }

  @override
  void  dispose() {
    super.dispose();
    player.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SizedBox(
          width: MediaQuery.of(context).size.width,
          height: MediaQuery.of(context).size.width * 9.0 / 16.0,
          // Use [Video] widget to display video output.
          child: Video(controller: controller),
        ),
      ),
    );
  }
}
