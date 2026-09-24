import 'package:flutter/material.dart';

import '../models/continue_watching.dart';
import 'cover_image.dart';
import 'episode_list.dart' show formatDuration;

/// Home view: the next-up episode of every show in progress, as cover cards.
class ContinueWatchingShelf extends StatelessWidget {
  final List<ContinueWatching> items;
  final ValueChanged<ContinueWatching> onPlay;
  final ValueChanged<ContinueWatching> onOpenShow;

  const ContinueWatchingShelf({super.key, required this.items, required this.onPlay, required this.onOpenShow});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(padding: const EdgeInsets.all(20), children: [
      Text('Continue watching', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
      const SizedBox(height: 16),
      if (items.isEmpty)
        const Text('Nothing in progress. Pick a show from the library to start watching.')
      else
        Wrap(spacing: 16, runSpacing: 16, children: [
          for (final c in items) _ShelfCard(item: c, onPlay: () => onPlay(c), onOpenShow: () => onOpenShow(c)),
        ]),
    ]);
  }
}

class _ShelfCard extends StatelessWidget {
  static const double width = 180;

  final ContinueWatching item;
  final VoidCallback onPlay;
  final VoidCallback onOpenShow;

  const _ShelfCard({required this.item, required this.onPlay, required this.onOpenShow});

  @override
  Widget build(BuildContext context) {
    final episode = item.episode;
    final progress = episode.progress;
    final resumable = progress != null && progress.started && !episode.completed && progress.duration > Duration.zero;
    final subtitle = resumable
        ? '${episode.code} · ${formatDuration(progress.duration - progress.position)} left'
        : 'Next: ${episode.code}';

    return SizedBox(
      width: width,
      child: Material(
        color: Colors.white12,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPlay,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Stack(children: [
              CoverImage(
                path: item.entry.item.coverPath,
                url: item.entry.item.imageLarge ?? item.entry.item.imageMedium,
                width: width,
                height: 250,
                borderRadius: 0,
              ),
              const Positioned.fill(
                  child: Center(child: Icon(Icons.play_circle_fill, size: 56, color: Colors.white70))),
              Positioned(
                top: 4,
                right: 4,
                child: IconButton.filledTonal(
                  tooltip: 'Open show',
                  onPressed: onOpenShow,
                  icon: const Icon(Icons.info_outline),
                ),
              ),
            ]),
            if (resumable) LinearProgressIndicator(value: progress.fraction, minHeight: 4),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(item.entry.item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(subtitle, style: const TextStyle(color: Colors.white70, fontSize: 13)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
