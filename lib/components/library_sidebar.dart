import 'package:flutter/material.dart';

import '../models/item.dart';
import 'cover_image.dart';

/// Scrollable list of library entries with cover, title and progress.
class LibrarySidebar extends StatelessWidget {
  final List<LibraryEntry> entries;
  final int? selectedId;
  final ValueChanged<LibraryEntry> onSelected;

  const LibrarySidebar({super.key, required this.entries, required this.selectedId, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Your library is empty.\nClick + to add a show folder.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18),
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: entries.length,
      itemBuilder: (context, i) {
        final entry = entries[i];
        final selected = entry.item.id == selectedId;
        final fg = selected ? Colors.black : Colors.white;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Material(
            color: selected ? Colors.deepPurpleAccent : Colors.white12,
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => onSelected(entry),
              child: SizedBox(
                height: 84,
                child: Row(children: [
                  CoverImage(url: entry.item.imageMedium, width: 56, height: 84, borderRadius: 0),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.item.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: fg, fontSize: 17, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 6),
                        Row(children: [
                          Expanded(
                            child: LinearProgressIndicator(
                              value: entry.progress,
                              minHeight: 4,
                              color: selected ? Colors.black87 : Colors.deepPurpleAccent,
                              backgroundColor: fg.withAlpha(40),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text('${entry.watchedCount}/${entry.episodeCount}',
                              style: TextStyle(color: fg.withAlpha(200), fontSize: 13)),
                        ]),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                ]),
              ),
            ),
          ),
        );
      },
    );
  }
}
