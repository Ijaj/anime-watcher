import 'package:flutter/material.dart';

import '../data/library_repository.dart';
import '../models/item.dart';
import 'cover_image.dart';

/// Scrollable list of library entries with cover, title and progress, plus a
/// title filter and sort menu.
class LibrarySidebar extends StatefulWidget {
  final List<LibraryEntry> entries;
  final int? selectedId;
  final ValueChanged<LibraryEntry> onSelected;
  final LibrarySort sort;
  final ValueChanged<LibrarySort> onSortChanged;

  const LibrarySidebar({
    super.key,
    required this.entries,
    required this.selectedId,
    required this.onSelected,
    required this.sort,
    required this.onSortChanged,
  });

  @override
  State<LibrarySidebar> createState() => _LibrarySidebarState();
}

class _LibrarySidebarState extends State<LibrarySidebar> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.entries.isEmpty) {
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
    final visible = LibraryRepository.filterAndSort(widget.entries, query: _searchController.text, sort: widget.sort);
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 4, 4),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Search library',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        icon: const Icon(Icons.clear),
                        onPressed: () => setState(_searchController.clear),
                      ),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          PopupMenuButton<LibrarySort>(
            tooltip: 'Sort: ${widget.sort.label}',
            icon: const Icon(Icons.sort),
            initialValue: widget.sort,
            onSelected: widget.onSortChanged,
            itemBuilder: (_) => [
              for (final s in LibrarySort.values)
                CheckedPopupMenuItem(value: s, checked: s == widget.sort, child: Text(s.label)),
            ],
          ),
        ]),
      ),
      Expanded(
        child: visible.isEmpty
            ? const Center(child: Text('No shows match your search.'))
            : ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: visible.length,
                itemBuilder: (context, i) => _SidebarTile(
                  entry: visible[i],
                  selected: visible[i].item.id == widget.selectedId,
                  onTap: () => widget.onSelected(visible[i]),
                ),
              ),
      ),
    ]);
  }
}

class _SidebarTile extends StatelessWidget {
  final LibraryEntry entry;
  final bool selected;
  final VoidCallback onTap;

  const _SidebarTile({required this.entry, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final fg = selected ? Colors.black : Colors.white;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Material(
        color: selected ? Colors.deepPurpleAccent : Colors.white12,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 84,
            child: Row(children: [
              CoverImage(
                  path: entry.item.coverPath, url: entry.item.imageMedium, width: 56, height: 84, borderRadius: 0),
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
  }
}
