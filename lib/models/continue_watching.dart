import 'episode.dart';
import 'item.dart';

/// A show with watch history and the episode to play next.
class ContinueWatching {
  final LibraryEntry entry;
  final Episode episode;

  const ContinueWatching({required this.entry, required this.episode});
}
