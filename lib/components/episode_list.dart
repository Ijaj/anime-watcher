import 'package:flutter/material.dart';

import '../models/episode.dart';

/// Episodes grouped by season, with watched state and resume position.
class EpisodeList extends StatelessWidget {
  final List<Episode> episodes;
  final int? highlightId;
  final ValueChanged<Episode> onPlay;
  final void Function(Episode episode, bool watched) onSetWatched;

  const EpisodeList({
    super.key,
    required this.episodes,
    required this.onPlay,
    required this.onSetWatched,
    this.highlightId,
  });

  @override
  Widget build(BuildContext context) {
    if (episodes.isEmpty) {
      return const Center(child: Text('No video files found. Try “Rescan folder”.'));
    }

    final rows = <Widget>[];
    int? season;
    for (final e in episodes) {
      if (e.season != season) {
        season = e.season;
        rows.add(Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(season == 0 ? 'Specials' : 'Season $season',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        ));
      }
      rows.add(_EpisodeTile(
        episode: e,
        highlighted: e.id == highlightId,
        onTap: () => onPlay(e),
        onSetWatched: (w) => onSetWatched(e, w),
      ));
    }
    // ListTiles paint highlights on the nearest Material; without this the
    // panel's decorated background would hide them.
    return Material(
      type: MaterialType.transparency,
      child: ListView(padding: const EdgeInsets.only(bottom: 16), children: rows),
    );
  }
}

class _EpisodeTile extends StatelessWidget {
  final Episode episode;
  final bool highlighted;
  final VoidCallback onTap;
  final ValueChanged<bool> onSetWatched;

  const _EpisodeTile(
      {required this.episode, required this.highlighted, required this.onTap, required this.onSetWatched});

  @override
  Widget build(BuildContext context) {
    final progress = episode.progress;
    final Widget leading;
    if (episode.completed) {
      leading = const Icon(Icons.check_circle, color: Colors.greenAccent);
    } else if (progress != null && progress.started) {
      leading = SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(value: progress.fraction, strokeWidth: 3, backgroundColor: Colors.white24),
      );
    } else {
      leading = const Icon(Icons.play_circle_outline);
    }

    return ListTile(
      selected: highlighted,
      selectedTileColor: Colors.deepPurpleAccent.withAlpha(50),
      leading: leading,
      title: Text('Episode ${episode.number}'),
      subtitle: Text(episode.fileName, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (progress != null && !episode.completed && progress.duration > Duration.zero)
          Text('${formatDuration(progress.position)} / ${formatDuration(progress.duration)}'),
        PopupMenuButton<bool>(
          tooltip: 'Episode options',
          onSelected: onSetWatched,
          itemBuilder: (_) => [
            if (!episode.completed) const PopupMenuItem(value: true, child: Text('Mark as watched')),
            if (progress != null) const PopupMenuItem(value: false, child: Text('Mark as unwatched')),
          ],
        ),
      ]),
      onTap: onTap,
    );
  }
}

String formatDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}
