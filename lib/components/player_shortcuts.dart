import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// What the player's keyboard shortcuts can do.
class PlayerShortcutActions {
  final VoidCallback play;
  final VoidCallback pause;
  final VoidCallback playOrPause;
  final void Function(Duration offset) seekBy;
  final void Function(double delta) changeVolume;
  final VoidCallback toggleFullscreen;

  /// Leave fullscreen, or go back to the library when not fullscreen.
  final VoidCallback escape;
  final VoidCallback nextEpisode;
  final VoidCallback previousEpisode;

  const PlayerShortcutActions({
    required this.play,
    required this.pause,
    required this.playOrPause,
    required this.seekBy,
    required this.changeVolume,
    required this.toggleFullscreen,
    required this.escape,
    required this.nextEpisode,
    required this.previousEpisode,
  });
}

/// Keyboard shortcuts for `MaterialDesktopVideoControls`.
///
/// A custom `keyboardShortcuts` map replaces media_kit_video's defaults
/// entirely, so the defaults of the locked version (1.2.4) are restated
/// unchanged: space / media play-pause keys, J and I (±10 s), ← → (±2 s),
/// ↑ ↓ (volume ±5), F (fullscreen).
///
/// Added on top, since the defaults lack them:
/// - N, Shift+N and the media "next track" key: next episode.
/// - P, Shift+P and the media "previous track" key: previous episode. (The
///   defaults map these media keys to mpv's playlist, which is always a
///   single file here, so they did nothing.)
/// - Esc: go back to the library. It still leaves fullscreen first.
Map<ShortcutActivator, VoidCallback> playerShortcuts(PlayerShortcutActions a) => {
  // media_kit_video defaults.
  const SingleActivator(LogicalKeyboardKey.mediaPlay): a.play,
  const SingleActivator(LogicalKeyboardKey.mediaPause): a.pause,
  const SingleActivator(LogicalKeyboardKey.mediaPlayPause): a.playOrPause,
  const SingleActivator(LogicalKeyboardKey.space): a.playOrPause,
  const SingleActivator(LogicalKeyboardKey.keyJ): () => a.seekBy(const Duration(seconds: -10)),
  const SingleActivator(LogicalKeyboardKey.keyI): () => a.seekBy(const Duration(seconds: 10)),
  const SingleActivator(LogicalKeyboardKey.arrowLeft): () => a.seekBy(const Duration(seconds: -2)),
  const SingleActivator(LogicalKeyboardKey.arrowRight): () => a.seekBy(const Duration(seconds: 2)),
  const SingleActivator(LogicalKeyboardKey.arrowUp): () => a.changeVolume(5),
  const SingleActivator(LogicalKeyboardKey.arrowDown): () => a.changeVolume(-5),
  const SingleActivator(LogicalKeyboardKey.keyF): a.toggleFullscreen,
  // Added.
  const SingleActivator(LogicalKeyboardKey.escape): a.escape,
  const SingleActivator(LogicalKeyboardKey.mediaTrackNext): a.nextEpisode,
  const SingleActivator(LogicalKeyboardKey.keyN): a.nextEpisode,
  const SingleActivator(LogicalKeyboardKey.keyN, shift: true): a.nextEpisode,
  const SingleActivator(LogicalKeyboardKey.mediaTrackPrevious): a.previousEpisode,
  const SingleActivator(LogicalKeyboardKey.keyP): a.previousEpisode,
  const SingleActivator(LogicalKeyboardKey.keyP, shift: true): a.previousEpisode,
};
