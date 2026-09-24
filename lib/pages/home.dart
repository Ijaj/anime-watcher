import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart';

import '../components/add_item_dialog.dart';
import '../components/bulk_import_dialog.dart';
import '../components/continue_watching_shelf.dart';
import '../components/episode_list.dart';
import '../components/item_header.dart';
import '../components/library_sidebar.dart';
import '../data/library_repository.dart';
import '../models/continue_watching.dart';
import '../models/episode.dart';
import '../models/item.dart';
import '../services/library_scanner.dart';
import '../services/mal_client.dart';
import 'player_page.dart';
import 'settings_page.dart';

class HomePage extends StatefulWidget {
  final LibraryRepository repository;
  final MalClient malClient;

  /// Sync every show with its folder in the background after startup.
  final bool autoRescan;

  const HomePage({super.key, required this.repository, required this.malClient, this.autoRescan = true});

  @override
  State<HomePage> createState() => _HomePageState();
}

enum InterfaceBrightness {
  light,
  dark,
  auto,
}

class _HomePageState extends State<HomePage> {
  static const double titleHeight = 150;
  static const double headerHeight = 244;
  static const double padding = 8.0;
  static const double tileOpacity = 0.6;

  List<LibraryEntry> _entries = [];
  List<Episode> _episodes = [];
  List<ContinueWatching> _continue = [];
  int? _selectedId;
  bool _loaded = false;
  LibrarySort _sort = LibrarySort.title;

  static const _sortKey = 'library_sort';

  LibraryRepository get _repo => widget.repository;

  LibraryEntry? get _selected {
    for (final e in _entries) {
      if (e.item.id == _selectedId) return e;
    }
    return null;
  }

  BoxDecoration containerDecoration(BuildContext context) {
    return BoxDecoration(
      color: Theme.of(context).scaffoldBackgroundColor.withAlpha((255 * tileOpacity).round()),
      borderRadius: BorderRadius.circular(12.0),
    );
  }

  WindowEffect effect = Platform.isWindows ? WindowEffect.acrylic : WindowEffect.transparent;
  Color color = Platform.isWindows ? const Color(0x01000000) : Colors.transparent;
  InterfaceBrightness brightness = Platform.isMacOS ? InterfaceBrightness.auto : InterfaceBrightness.dark;

  void setWindowEffect(WindowEffect value) {
    Window.setEffect(
      effect: value,
      color: color,
      dark: brightness == InterfaceBrightness.dark,
    );
    if (Platform.isMacOS && brightness != InterfaceBrightness.auto) {
      Window.overrideMacOSBrightness(dark: brightness == InterfaceBrightness.dark);
    }
    setState(() => effect = value);
  }

  @override
  void initState() {
    super.initState();
    setWindowEffect(effect);
    _repo.addListener(_reload);
    _reload();
    _repo.setting(_sortKey).then((v) {
      if (mounted) setState(() => _sort = LibrarySort.fromName(v));
    });
    if (widget.autoRescan) _rescanAll();
  }

  /// Picks up new or deleted episode files, skipping unavailable folders.
  Future<void> _rescanAll() async {
    final summary = await _repo.syncAll(LibraryScanner.rescan);
    if (summary.changed) _toast(summary.describe());
  }

  @override
  void dispose() {
    _repo.removeListener(_reload);
    super.dispose();
  }

  /// Reloads the library and whatever the main panel shows: the selected
  /// show's episodes, or the continue-watching shelf when nothing is
  /// selected.
  Future<void> _reload() async {
    final entries = await _repo.entries();
    var selectedId = _selectedId;
    if (!entries.any((e) => e.item.id == selectedId)) selectedId = null;
    final episodes = selectedId == null ? <Episode>[] : await _repo.episodes(selectedId);
    final continueWatching = selectedId == null ? await _repo.continueWatching() : _continue;
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _selectedId = selectedId;
      _episodes = episodes;
      _continue = continueWatching;
      _loaded = true;
    });
  }

  Future<void> _select(int? itemId) async {
    setState(() => _selectedId = itemId);
    await _reload();
  }

  void _setSort(LibrarySort sort) {
    setState(() => _sort = sort);
    _repo.setSetting(_sortKey, sort.name);
  }

  Future<void> _addItem() async {
    final item = await AddItemDialog.show(context, _repo, widget.malClient);
    if (item == null || !mounted) return;
    setState(() => _selectedId = item.id);
    await _reload();
    _toast('Added ${item.title}');
  }

  Future<void> _bulkImport() async {
    final result = await BulkImportDialog.show(context, _repo, widget.malClient);
    if (result == null || !mounted) return;
    final failed = result.failures.isEmpty ? '' : '\nNot added:\n${result.failures.join('\n')}';
    _toast('Added ${result.added} ${result.added == 1 ? 'show' : 'shows'}$failed', error: result.failures.isNotEmpty);
  }

  Future<void> _openSettings() => Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => SettingsPage(repository: _repo, malClient: widget.malClient),
      ));

  Future<void> _play(Episode episode) async {
    final entry = _selected;
    if (entry != null) await _playFrom(entry.item, _episodes, episode);
  }

  Future<void> _playContinue(ContinueWatching c) async =>
      _playFrom(c.entry.item, await _repo.episodes(c.entry.item.id!), c.episode);

  Future<void> _playFrom(LibraryItem item, List<Episode> playlist, Episode episode) async {
    final index = playlist.indexWhere((e) => e.id == episode.id);
    if (index < 0) return;
    if (!await File(episode.path).exists()) {
      _toast('File not found: ${episode.path}\nTry “Rescan folder”.', error: true);
      return;
    }
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => PlayerPage(
        repository: _repo,
        item: item,
        playlist: playlist,
        startIndex: index,
      ),
    ));
    // Positions are saved without notifying, so refresh on return.
    await _reload();
  }

  Future<void> _onAction(ItemAction action) async {
    final item = _selected?.item;
    if (item == null) return;
    switch (action) {
      case ItemAction.rescan:
        try {
          final scanned = await LibraryScanner.scan(item.rootPath);
          final (added, removed) = await _repo.syncEpisodes(item.id!, scanned);
          _toast('Rescan complete: $added added, $removed removed');
        } on FileSystemException catch (e) {
          _toast('Could not scan ${item.rootPath}: ${e.message}', error: true);
        }
      case ItemAction.remove:
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('Remove ${item.title}?'),
            content: const Text('This removes it and its watch history from the library. '
                'Files on disk are not touched.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove')),
            ],
          ),
        );
        if (confirmed == true) await _repo.removeItem(item.id!);
    }
  }

  void _toast(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: error ? Theme.of(context).colorScheme.error : null,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final decoration = containerDecoration(context);
    final selected = _selected;
    final nextUp = LibraryRepository.nextUp(_episodes);

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton(
        hoverElevation: 6,
        tooltip: 'Add To Library',
        onPressed: _addItem,
        child: const Icon(Icons.add),
      ),
      body: Container(
        decoration: const BoxDecoration(
          color: Colors.black,
          backgroundBlendMode: BlendMode.clear,
        ),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 100.0, sigmaY: 100.0, tileMode: TileMode.mirror),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 400,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(padding, padding, padding, 0),
                      child: Container(
                        height: titleHeight,
                        width: double.infinity,
                        decoration: decoration,
                        child: Column(children: [
                          const Expanded(
                            child: Center(
                              child: FittedBox(
                                child:
                                    Text('ANIME WATCHER', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w700)),
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                              IconButton(
                                tooltip: 'Home',
                                isSelected: selected == null,
                                onPressed: () => _select(null),
                                icon: const Icon(Icons.home_outlined),
                                selectedIcon: const Icon(Icons.home),
                              ),
                              IconButton(
                                tooltip: 'Import a folder of shows',
                                onPressed: _bulkImport,
                                icon: const Icon(Icons.drive_folder_upload_outlined),
                              ),
                              IconButton(
                                tooltip: 'Settings',
                                onPressed: _openSettings,
                                icon: const Icon(Icons.settings_outlined),
                              ),
                            ]),
                          ),
                        ]),
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(padding),
                        child: Container(
                          decoration: decoration,
                          clipBehavior: Clip.antiAlias,
                          child: _loaded
                              ? LibrarySidebar(
                                  entries: _entries,
                                  selectedId: _selectedId,
                                  onSelected: (e) => _select(e.item.id),
                                  sort: _sort,
                                  onSortChanged: _setSort,
                                )
                              : const Center(child: CircularProgressIndicator()),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: selected == null
                    ? Padding(
                        padding: const EdgeInsets.fromLTRB(0, padding, padding, padding),
                        child: Container(
                          width: double.infinity,
                          decoration: decoration,
                          clipBehavior: Clip.antiAlias,
                          child: !_loaded
                              ? const SizedBox.shrink()
                              : _entries.isEmpty
                                  ? const Center(child: Text('Click + to add a show folder.'))
                                  : ContinueWatchingShelf(
                                      items: _continue,
                                      onPlay: _playContinue,
                                      onOpenShow: (c) => _select(c.entry.item.id),
                                    ),
                        ),
                      )
                    : Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(0, padding, padding, 0),
                            child: Container(
                              width: double.infinity,
                              height: headerHeight,
                              decoration: decoration,
                              child: ItemHeader(
                                entry: selected,
                                nextUp: nextUp,
                                onPlay: nextUp == null ? null : () => _play(nextUp),
                                onAction: _onAction,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(0, padding, padding, padding),
                              child: Container(
                                width: double.infinity,
                                decoration: decoration,
                                clipBehavior: Clip.antiAlias,
                                child: EpisodeList(
                                  episodes: _episodes,
                                  highlightId: nextUp?.id,
                                  onPlay: _play,
                                  onSetWatched: (e, watched) => _repo.setWatched(e.id!, watched),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
