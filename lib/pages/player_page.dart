import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../components/player_shortcuts.dart';
import '../data/library_repository.dart';
import '../models/episode.dart';
import '../models/item.dart';

/// Plays [playlist] starting at [startIndex], resuming from saved progress
/// and recording progress as it goes.
class PlayerPage extends StatefulWidget {
  final LibraryRepository repository;
  final LibraryItem item;
  final List<Episode> playlist;
  final int startIndex;

  const PlayerPage({
    super.key,
    required this.repository,
    required this.item,
    required this.playlist,
    required this.startIndex,
  });

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  static const _saveInterval = Duration(seconds: 5);

  /// Don't bother resuming if less than this was watched.
  static const _minResume = Duration(seconds: 10);

  late final Player _player = Player();
  late final VideoController _controller = VideoController(_player);
  final List<StreamSubscription<Object?>> _subscriptions = [];
  Timer? _saveTimer;

  late int _index = widget.startIndex;
  Duration? _pendingSeek;

  /// True while switching files, when the player state may still describe
  /// the previous episode.
  bool _switching = false;
  String? _error;

  Episode get _episode => widget.playlist[_index];

  @override
  void initState() {
    super.initState();
    _subscriptions.addAll([
      _player.stream.duration.listen(_onDuration),
      _player.stream.completed.listen((done) {
        if (done) _onCompleted();
      }),
      _player.stream.error.listen((e) {
        if (mounted) setState(() => _error = e);
      }),
    ]);
    _saveTimer = Timer.periodic(_saveInterval, (_) => _save());
    _open(_index);
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    for (final s in _subscriptions) {
      s.cancel();
    }
    _save();
    _player.dispose();
    super.dispose();
  }

  Future<void> _open(int index) async {
    await _save();
    _switching = true;
    final episode = widget.playlist[index];
    final progress = episode.progress;
    setState(() {
      _index = index;
      _error = null;
      _pendingSeek = progress != null && !progress.completed && progress.position > _minResume
          ? progress.position
          : null;
    });
    try {
      // open() stops the previous file first, resetting position/duration.
      await _player.open(Media(episode.path));
    } finally {
      _switching = false;
    }
  }

  /// Seeks to the resume point once the file's duration is known (seeking
  /// before the file is loaded is ignored by mpv).
  void _onDuration(Duration duration) {
    final seek = _pendingSeek;
    if (seek == null || duration <= Duration.zero) return;
    _pendingSeek = null;
    if (seek < duration) _player.seek(seek);
  }

  Future<void> _save() async {
    final id = _episode.id;
    final position = _player.state.position;
    final duration = _player.state.duration;
    // Nothing loaded yet, or we are still waiting to seek to the resume
    // point — saving now would overwrite the stored position with ~0.
    if (id == null || _switching || duration <= Duration.zero || _pendingSeek != null) return;
    await widget.repository.saveProgress(id, position: position, duration: duration);
  }

  Future<void> _onCompleted() async {
    final id = _episode.id;
    if (id != null) {
      final duration = _player.state.duration;
      await widget.repository.saveProgress(id, position: duration, duration: duration);
    }
    if (!mounted) return;
    if (_index + 1 < widget.playlist.length) {
      await _open(_index + 1);
    } else {
      Navigator.of(context).maybePop();
    }
  }

  bool get _hasPrev => _index > 0;
  bool get _hasNext => _index + 1 < widget.playlist.length;

  /// [videoContext] is inside the controls, so it knows whether the video is
  /// fullscreen (fullscreen is a separate route that rebuilds the controls).
  PlayerShortcutActions _shortcutActions(BuildContext videoContext) => PlayerShortcutActions(
    play: _player.play,
    pause: _player.pause,
    playOrPause: _player.playOrPause,
    seekBy: (offset) => _player.seek(_player.state.position + offset),
    changeVolume: (delta) => _player.setVolume((_player.state.volume + delta).clamp(0.0, 100.0)),
    toggleFullscreen: () => toggleFullscreen(videoContext),
    escape: () {
      if (isFullscreen(videoContext)) {
        exitFullscreen(videoContext);
      } else {
        Navigator.of(context).maybePop();
      }
    },
    nextEpisode: () {
      if (_hasNext) _open(_index + 1);
    },
    previousEpisode: () {
      if (_hasPrev) _open(_index - 1);
    },
  );

  Widget _controls(VideoState state) => Builder(
    builder: (videoContext) {
      final shortcuts = playerShortcuts(_shortcutActions(videoContext));
      return MaterialDesktopVideoControlsTheme(
        normal: kDefaultMaterialDesktopVideoControlsThemeData.copyWith(keyboardShortcuts: shortcuts),
        fullscreen: kDefaultMaterialDesktopVideoControlsThemeDataFullscreen.copyWith(keyboardShortcuts: shortcuts),
        child: MaterialDesktopVideoControls(state),
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    final hasPrev = _hasPrev;
    final hasNext = _hasNext;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Column(
        children: [
          Material(
            color: Colors.black,
            child: SizedBox(
              height: 48,
              child: Row(
                children: [
                  const BackButton(color: Colors.white),
                  Expanded(
                    child: Text(
                      '${widget.item.title}  ·  ${_episode.code}  ·  ${_episode.fileName}',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Previous episode (P)',
                    color: Colors.white,
                    onPressed: hasPrev ? () => _open(_index - 1) : null,
                    icon: const Icon(Icons.skip_previous),
                  ),
                  IconButton(
                    tooltip: 'Next episode (N)',
                    color: Colors.white,
                    onPressed: hasNext ? () => _open(_index + 1) : null,
                    icon: const Icon(Icons.skip_next),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: Video(controller: _controller, controls: _controls),
                ),
                if (_error != null)
                  Positioned(
                    left: 16,
                    right: 16,
                    top: 16,
                    child: Material(
                      color: Colors.red.shade900,
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(_error!, style: const TextStyle(color: Colors.white)),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
