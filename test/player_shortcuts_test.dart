import 'package:anime_watcher/components/player_shortcuts.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final calls = <String>[];
  final shortcuts = playerShortcuts(PlayerShortcutActions(
    play: () => calls.add('play'),
    pause: () => calls.add('pause'),
    playOrPause: () => calls.add('playOrPause'),
    seekBy: (d) => calls.add('seek ${d.inSeconds}'),
    changeVolume: (v) => calls.add('volume ${v.round()}'),
    toggleFullscreen: () => calls.add('fullscreen'),
    escape: () => calls.add('escape'),
    nextEpisode: () => calls.add('next'),
    previousEpisode: () => calls.add('previous'),
  ));

  setUp(calls.clear);

  String press(LogicalKeyboardKey key, {bool shift = false}) {
    calls.clear();
    // SingleActivator has no value equality, so match on its fields.
    final match = shortcuts.entries.where((e) {
      final a = e.key as SingleActivator;
      return a.trigger == key && a.shift == shift;
    });
    match.single.value();
    return calls.single;
  }

  test('keeps media_kit_video defaults', () {
    expect(press(LogicalKeyboardKey.space), 'playOrPause');
    expect(press(LogicalKeyboardKey.mediaPlayPause), 'playOrPause');
    expect(press(LogicalKeyboardKey.mediaPlay), 'play');
    expect(press(LogicalKeyboardKey.mediaPause), 'pause');
    expect(press(LogicalKeyboardKey.keyJ), 'seek -10');
    expect(press(LogicalKeyboardKey.keyI), 'seek 10');
    expect(press(LogicalKeyboardKey.arrowLeft), 'seek -2');
    expect(press(LogicalKeyboardKey.arrowRight), 'seek 2');
    expect(press(LogicalKeyboardKey.arrowUp), 'volume 5');
    expect(press(LogicalKeyboardKey.arrowDown), 'volume -5');
    expect(press(LogicalKeyboardKey.keyF), 'fullscreen');
  });

  test('adds episode navigation and Esc', () {
    expect(press(LogicalKeyboardKey.keyN), 'next');
    expect(press(LogicalKeyboardKey.keyN, shift: true), 'next');
    expect(press(LogicalKeyboardKey.mediaTrackNext), 'next');
    expect(press(LogicalKeyboardKey.keyP), 'previous');
    expect(press(LogicalKeyboardKey.keyP, shift: true), 'previous');
    expect(press(LogicalKeyboardKey.mediaTrackPrevious), 'previous');
    expect(press(LogicalKeyboardKey.escape), 'escape');
  });

  testWidgets('key events reach the actions through CallbackShortcuts', (tester) async {
    await tester.pumpWidget(CallbackShortcuts(
      bindings: shortcuts,
      child: const Focus(autofocus: true, child: SizedBox()),
    ));
    calls.clear();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(calls, ['next', 'previous', 'escape']);
  });
}
