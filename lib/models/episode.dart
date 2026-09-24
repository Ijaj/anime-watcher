import 'package:path/path.dart' as p;

/// Playback progress for one episode.
class WatchProgress {
  final Duration position;
  final Duration duration;
  final bool completed;
  final DateTime updatedAt;

  const WatchProgress({
    required this.position,
    required this.duration,
    required this.completed,
    required this.updatedAt,
  });

  double get fraction {
    if (completed) return 1;
    if (duration <= Duration.zero) return 0;
    return (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
  }

  bool get started => completed || position > Duration.zero;
}

/// A video file on disk that belongs to a library item.
class Episode {
  final int? id;
  final int itemId;
  final int season;
  final int number;
  final String path;
  final WatchProgress? progress;

  const Episode({
    this.id,
    required this.itemId,
    required this.season,
    required this.number,
    required this.path,
    this.progress,
  });

  String get fileName => p.basename(path);

  bool get completed => progress?.completed ?? false;

  /// e.g. `S01E05`, or `SP03` for specials.
  String get code {
    final ep = number.toString().padLeft(2, '0');
    if (season == 0) return 'SP$ep';
    return 'S${season.toString().padLeft(2, '0')}E$ep';
  }

  factory Episode.fromMap(Map<String, Object?> m) {
    final updatedAt = m['updated_at'] as int?;
    return Episode(
      id: m['id'] as int?,
      itemId: m['item_id'] as int,
      season: m['season'] as int,
      number: m['number'] as int,
      path: m['path'] as String,
      progress: updatedAt == null
          ? null
          : WatchProgress(
              position: Duration(milliseconds: m['position_ms'] as int? ?? 0),
              duration: Duration(milliseconds: m['duration_ms'] as int? ?? 0),
              completed: (m['completed'] as int? ?? 0) == 1,
              updatedAt: DateTime.fromMillisecondsSinceEpoch(updatedAt),
            ),
    );
  }
}

/// An episode found by the scanner, before it is stored.
class ScannedEpisode {
  final int season;
  final int number;
  final String path;

  const ScannedEpisode({required this.season, required this.number, required this.path});

  @override
  String toString() => 'S${season}E$number $path';
}
