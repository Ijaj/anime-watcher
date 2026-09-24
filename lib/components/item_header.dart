import 'package:flutter/material.dart';

import '../models/episode.dart';
import '../models/item.dart';
import 'cover_image.dart';

enum ItemAction { rescan, remove }

/// Cover, title, metadata and actions for the selected library item.
class ItemHeader extends StatelessWidget {
  final LibraryEntry entry;
  final Episode? nextUp;
  final VoidCallback? onPlay;
  final ValueChanged<ItemAction> onAction;

  const ItemHeader(
      {super.key, required this.entry, required this.nextUp, required this.onPlay, required this.onAction});

  @override
  Widget build(BuildContext context) {
    final item = entry.item;
    final theme = Theme.of(context);
    final facts = [
      item.type.label,
      if (item.airing) 'Currently airing',
      if (item.totalEpisodes != null) '${item.totalEpisodes} episodes',
      if (item.score != null) '★ ${item.score!.toStringAsFixed(2)}',
    ];
    final started = nextUp?.progress?.started ?? false;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        CoverImage(path: item.coverPath, url: item.imageLarge ?? item.imageMedium, width: 150, height: 212),
        const SizedBox(width: 20),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(item.title,
                    style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
              ),
              PopupMenuButton<ItemAction>(
                tooltip: 'More',
                onSelected: onAction,
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: ItemAction.rescan,
                    child: ListTile(leading: Icon(Icons.refresh), title: Text('Rescan folder')),
                  ),
                  PopupMenuItem(
                    value: ItemAction.remove,
                    child: ListTile(leading: Icon(Icons.delete_outline), title: Text('Remove from library')),
                  ),
                ],
              ),
            ]),
            const SizedBox(height: 4),
            Text(facts.join('  ·  '), style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white70)),
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final g in item.genres)
                Chip(label: Text(g), visualDensity: VisualDensity.compact, padding: EdgeInsets.zero),
            ]),
            if (item.synopsis != null) ...[
              const SizedBox(height: 8),
              Text(item.synopsis!, maxLines: 3, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
            ],
            const SizedBox(height: 12),
            Row(children: [
              FilledButton.icon(
                onPressed: onPlay,
                icon: const Icon(Icons.play_arrow),
                label: Text(nextUp == null
                    ? (entry.episodeCount == 0 ? 'No episodes' : 'All watched')
                    : '${started ? 'Continue' : 'Play'} ${nextUp!.code}'),
              ),
              const SizedBox(width: 16),
              SizedBox(
                width: 200,
                child: LinearProgressIndicator(value: entry.progress, minHeight: 6),
              ),
              const SizedBox(width: 8),
              Text('${entry.watchedCount} / ${entry.episodeCount} watched'),
            ]),
          ]),
        ),
      ]),
    );
  }
}
