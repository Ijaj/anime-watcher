import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../data/library_repository.dart';
import '../models/episode.dart';
import '../models/item.dart';
import '../services/library_scanner.dart';
import '../services/mal_client.dart';
import '../services/title_parser.dart';

/// Pick a folder, match it on MyAnimeList, and add it to the library.
/// Pops with the saved [LibraryItem], or null if cancelled.
class AddItemDialog extends StatefulWidget {
  final LibraryRepository repository;
  final MalClient malClient;

  const AddItemDialog({super.key, required this.repository, required this.malClient});

  static Future<LibraryItem?> show(BuildContext context, LibraryRepository repository, MalClient malClient) =>
      showDialog<LibraryItem>(
        context: context,
        builder: (_) => AddItemDialog(repository: repository, malClient: malClient),
      );

  @override
  State<AddItemDialog> createState() => _AddItemDialogState();
}

class _AddItemDialogState extends State<AddItemDialog> {
  static const _lastDirKey = 'last_browse_dir';

  final _pathController = TextEditingController();
  final _titleController = TextEditingController();
  final _matchController = TextEditingController();

  MediaType _type = MediaType.anime;
  ParsedTitle? _parsed;
  List<ScannedEpisode>? _episodes;
  List<MalSearchResult> _matches = [];
  MalSearchResult? _selected;
  Map<String, dynamic>? _details;

  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _pathController.dispose();
    _titleController.dispose();
    _matchController.dispose();
    super.dispose();
  }

  Future<void> _browse() async {
    final lastDir = await widget.repository.setting(_lastDirKey);
    final dir = await FilePicker.getDirectoryPath(
      dialogTitle: 'Select the show folder',
      initialDirectory: lastDir,
      windowsOptions: const WindowsOptions(lockParentWindow: true),
      linuxOptions: const LinuxOptions(lockParentWindow: true),
    );
    if (dir == null) return;
    _pathController.text = dir;
    await widget.repository.setSetting(_lastDirKey, p.dirname(dir));
    await _loadFolder(dir);
  }

  /// Parses the folder name and scans it for episodes.
  Future<void> _loadFolder(String dir) async {
    dir = dir.trim();
    if (dir.isEmpty) return;
    final parsed = TitleExtractor.extract(p.basename(dir));
    setState(() {
      _parsed = parsed;
      _titleController.text = parsed.title;
      _episodes = null;
      _matches = [];
      _selected = null;
      _details = null;
      _matchController.clear();
    });
    await _run(() async {
      if (await widget.repository.containsPath(dir)) {
        throw DuplicateItemException(dir);
      }
      final episodes = await LibraryScanner.scan(dir);
      setState(() => _episodes = episodes);
      if (_type == MediaType.anime && parsed.title.length >= 3) await _search();
    });
  }

  Future<void> _search() => _run(() async {
    final results = await widget.malClient.search(_titleController.text);
    setState(() {
      _matches = results;
      _selected = null;
      _details = null;
      _matchController.clear();
    });
    if (results.isEmpty) {
      throw MalException('No MyAnimeList results for "${_titleController.text}".');
    }
    await _select(results.first);
  });

  Future<void> _select(MalSearchResult match) async {
    setState(() {
      _selected = match;
      _matchController.text = match.label;
    });
    await _run(() async {
      final details = await widget.malClient.details(match.id);
      if (_selected?.id == match.id) setState(() => _details = details);
    });
  }

  Future<void> _add() => _run(() async {
    final root = _pathController.text.trim();
    final item = _type == MediaType.anime && _details != null
        ? LibraryItem.fromMal(_details!, rootPath: root, type: _type)
        : LibraryItem(type: _type, title: _titleController.text.trim(), rootPath: root);
    final saved = await widget.repository.addItem(item, _episodes ?? const []);
    if (mounted) Navigator.of(context).pop(saved);
  });

  /// Runs [action] with the busy spinner, turning exceptions into an inline
  /// error message.
  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool get _canAdd {
    if (_busy || _episodes == null || _episodes!.isEmpty) return false;
    if (_type == MediaType.anime && _details != null) return true;
    // Without a MAL match (other types, lookup failed, or no results) the
    // item can still be added using the typed title.
    return _titleController.text.trim().isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final seasonsOnDisk = _episodes == null ? null : ({for (final e in _episodes!) e.season}.toList()..sort());
    final genres = (_details?['genres'] as List<dynamic>?)?.map((g) => g['name']).join(', ');
    final malEpisodes = _details?['num_episodes'];

    return Dialog(
      backgroundColor: theme.colorScheme.surface.withAlpha(242),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Add to Library', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _pathController,
                      onSubmitted: _loadFolder,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'Show folder',
                        hintText: 'Paste a path and press Enter, or Browse',
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: _busy ? null : _browse,
                    icon: const Icon(Icons.folder_open),
                    label: const Text('Browse…'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _titleController,
                      onSubmitted: (_) => _type == MediaType.anime ? _search() : setState(() {}),
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'Title',
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SegmentedButton<MediaType>(
                    segments: const [
                      ButtonSegment(value: MediaType.anime, label: Text('Anime'), icon: Icon(Icons.animation)),
                      ButtonSegment(value: MediaType.movie, label: Text('Movie'), icon: Icon(Icons.movie)),
                      ButtonSegment(value: MediaType.series, label: Text('TV Series'), icon: Icon(Icons.tv)),
                    ],
                    selected: {_type},
                    onSelectionChanged: (v) => setState(() => _type = v.first),
                  ),
                  const SizedBox(width: 12),
                  Tooltip(
                    message: _type == MediaType.anime ? '' : 'Metadata lookup for movies and TV series is coming soon',
                    child: FilledButton.tonalIcon(
                      onPressed: !_busy && _type == MediaType.anime && _titleController.text.trim().length >= 3
                          ? _search
                          : null,
                      icon: const Icon(Icons.search),
                      label: const Text('Search MAL'),
                    ),
                  ),
                ],
              ),
              if (_type == MediaType.anime) ...[
                const SizedBox(height: 16),
                LayoutBuilder(
                  builder: (context, constraints) => DropdownMenu<MalSearchResult>(
                    enabled: _matches.isNotEmpty && !_busy,
                    controller: _matchController,
                    width: constraints.maxWidth,
                    label: Text(_matches.length > 1 ? 'Match (${_matches.length} found)' : 'Match'),
                    onSelected: (v) {
                      if (v != null) _select(v);
                    },
                    dropdownMenuEntries: [for (final m in _matches) DropdownMenuEntry(value: m, label: m.label)],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Table(
                columnWidths: const {0: IntrinsicColumnWidth()},
                border: TableBorder.all(color: theme.dividerColor),
                children: [
                  _row('Name', _type == MediaType.anime ? (_details?['title']) : _titleController.text),
                  _row('Type', _type.label),
                  if (_type == MediaType.anime) ...[
                    _row('Genre', genres),
                    _row('Episodes (MAL)', malEpisodes == null || malEpisodes == 0 ? null : '$malEpisodes'),
                    _row('Status', (_details?['status'] as String?)?.replaceAll('_', ' ')),
                  ],
                  _row(
                    'Seasons on disk',
                    seasonsOnDisk?.map((s) => s == 0 ? 'Specials' : '$s').join(', ') ?? _parsed?.seasons.join(', '),
                  ),
                  _row('Video files found', _episodes?.length.toString()),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 24,
                child: _busy
                    ? const Align(alignment: Alignment.centerLeft, child: LinearProgressIndicator())
                    : _error != null
                    ? Text(_error!, style: TextStyle(color: theme.colorScheme.error), maxLines: 2)
                    : _episodes != null && _episodes!.isEmpty
                    ? Text('No video files found in this folder.', style: TextStyle(color: theme.colorScheme.error))
                    : null,
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _canAdd ? _add : null,
                    icon: const Icon(Icons.library_add),
                    label: Text(
                      _type == MediaType.anime && _details == null ? 'Add Without Metadata' : 'Add To Library',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  TableRow _row(String label, Object? value) => TableRow(
    children: [
      Padding(
        padding: const EdgeInsets.all(8),
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      ),
      Padding(padding: const EdgeInsets.all(8), child: Text(value?.toString() ?? '—')),
    ],
  );
}
