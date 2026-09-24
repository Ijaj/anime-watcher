import 'dart:convert';

enum MediaType {
  anime,
  movie,
  series;

  String get label => switch (this) {
        MediaType.anime => 'Anime',
        MediaType.movie => 'Movie',
        MediaType.series => 'TV Series',
      };

  static MediaType fromName(String name) =>
      MediaType.values.firstWhere((t) => t.name == name, orElse: () => MediaType.anime);
}

/// A show or movie in the library, backed by a folder on disk.
class LibraryItem {
  final int? id;
  final int? malId;
  final MediaType type;
  final String title;
  final String rootPath;
  final List<String> genres;
  final String? synopsis;
  final String? imageMedium;
  final String? imageLarge;
  final bool airing;
  final int? totalEpisodes;
  final double? score;
  final DateTime addedAt;

  LibraryItem({
    this.id,
    this.malId,
    required this.type,
    required this.title,
    required this.rootPath,
    this.genres = const [],
    this.synopsis,
    this.imageMedium,
    this.imageLarge,
    this.airing = false,
    this.totalEpisodes,
    this.score,
    DateTime? addedAt,
  }) : addedAt = addedAt ?? DateTime.now();

  /// Builds an item from a MyAnimeList `GET /anime/{id}` response.
  factory LibraryItem.fromMal(
    Map<String, dynamic> r, {
    required String rootPath,
    MediaType type = MediaType.anime,
  }) {
    final picture = r['main_picture'] as Map<String, dynamic>?;
    final numEpisodes = r['num_episodes'] as int?;
    return LibraryItem(
      malId: r['id'] as int?,
      type: type,
      title: r['title'] as String,
      rootPath: rootPath,
      genres: [
        for (final g in (r['genres'] as List<dynamic>? ?? const [])) g['name'] as String,
      ],
      synopsis: r['synopsis'] as String?,
      imageMedium: picture?['medium'] as String?,
      imageLarge: picture?['large'] as String?,
      airing: r['status'] == 'currently_airing',
      totalEpisodes: numEpisodes == null || numEpisodes == 0 ? null : numEpisodes,
      score: (r['mean'] as num?)?.toDouble(),
    );
  }

  factory LibraryItem.fromMap(Map<String, Object?> m) => LibraryItem(
        id: m['id'] as int?,
        malId: m['mal_id'] as int?,
        type: MediaType.fromName(m['type'] as String),
        title: m['title'] as String,
        rootPath: m['root_path'] as String,
        genres: (jsonDecode(m['genres'] as String? ?? '[]') as List<dynamic>).cast<String>(),
        synopsis: m['synopsis'] as String?,
        imageMedium: m['image_medium'] as String?,
        imageLarge: m['image_large'] as String?,
        airing: (m['airing'] as int? ?? 0) == 1,
        totalEpisodes: m['total_episodes'] as int?,
        score: (m['score'] as num?)?.toDouble(),
        addedAt: DateTime.fromMillisecondsSinceEpoch(m['added_at'] as int),
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'mal_id': malId,
        'type': type.name,
        'title': title,
        'root_path': rootPath,
        'genres': jsonEncode(genres),
        'synopsis': synopsis,
        'image_medium': imageMedium,
        'image_large': imageLarge,
        'airing': airing ? 1 : 0,
        'total_episodes': totalEpisodes,
        'score': score,
        'added_at': addedAt.millisecondsSinceEpoch,
      };

  LibraryItem copyWith({int? id}) => LibraryItem(
        id: id ?? this.id,
        malId: malId,
        type: type,
        title: title,
        rootPath: rootPath,
        genres: genres,
        synopsis: synopsis,
        imageMedium: imageMedium,
        imageLarge: imageLarge,
        airing: airing,
        totalEpisodes: totalEpisodes,
        score: score,
        addedAt: addedAt,
      );
}

/// A library item together with its on-disk episode and watched counts.
class LibraryEntry {
  final LibraryItem item;
  final int episodeCount;
  final int watchedCount;

  /// When any episode of this item last had its progress saved.
  final DateTime? lastWatchedAt;

  const LibraryEntry({
    required this.item,
    required this.episodeCount,
    required this.watchedCount,
    this.lastWatchedAt,
  });

  double get progress => episodeCount == 0 ? 0 : watchedCount / episodeCount;
}

/// Sidebar ordering.
enum LibrarySort {
  title,
  recentlyWatched,
  recentlyAdded;

  String get label => switch (this) {
        LibrarySort.title => 'Title',
        LibrarySort.recentlyWatched => 'Recently watched',
        LibrarySort.recentlyAdded => 'Recently added',
      };

  static LibrarySort fromName(String? name) =>
      LibrarySort.values.firstWhere((s) => s.name == name, orElse: () => LibrarySort.title);
}
