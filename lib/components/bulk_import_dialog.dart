import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../data/library_repository.dart';
import '../services/bulk_importer.dart';
import '../services/mal_client.dart';

/// Pick a parent folder, treat every sub-folder as a show, review the
/// automatic MAL matches, then add them all. Pops with the
/// [BulkImportResult], or null if cancelled before adding.
class BulkImportDialog extends StatefulWidget {
  final LibraryRepository repository;
  final MalClient malClient;

  const BulkImportDialog({super.key, required this.repository, required this.malClient});

  static Future<BulkImportResult?> show(BuildContext context, LibraryRepository repository, MalClient malClient) =>
      showDialog<BulkImportResult>(
        context: context,
        barrierDismissible: false,
        builder: (_) => BulkImportDialog(repository: repository, malClient: malClient),
      );

  @override
  State<BulkImportDialog> createState() => _BulkImportDialogState();
}

class _BulkImportDialogState extends State<BulkImportDialog> {
  static const _lastDirKey = 'last_bulk_import_dir';

  late final _importer = BulkImporter(widget.repository, widget.malClient);
  final _pathController = TextEditingController();

  List<ImportCandidate>? _candidates;
  int _skippedExisting = 0;

  /// Non-null while scanning or adding: (done, total, label).
  (int, int, String)? _progress;
  String? _error;

  @override
  void dispose() {
    _pathController.dispose();
    super.dispose();
  }

  bool get _busy => _progress != null;

  Future<void> _browse() async {
    final dir = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select the folder that contains your show folders',
      lockParentWindow: true,
      initialDirectory: await widget.repository.setting(_lastDirKey),
    );
    if (dir == null) return;
    _pathController.text = dir;
    await _scan();
  }

  Future<void> _scan() async {
    final parent = _pathController.text.trim();
    if (parent.isEmpty) return;
    setState(() {
      _error = null;
      _candidates = null;
      _progress = (0, 0, 'Listing folders…');
    });
    try {
      final (folders, existing) = await _importer.showFolders(parent);
      await widget.repository.setSetting(_lastDirKey, parent);
      final candidates = <ImportCandidate>[];
      for (final folder in folders) {
        if (!mounted) return;
        setState(() => _progress = (candidates.length, folders.length, 'Scanning and matching…'));
        candidates.add(await _importer.prepare(folder));
      }
      if (!mounted) return;
      setState(() {
        _candidates = candidates;
        _skippedExisting = existing;
        if (folders.isEmpty) {
          _error = existing > 0 ? 'Every sub-folder is already in your library.' : 'No sub-folders found.';
        }
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _progress = null);
    }
  }

  Future<void> _addAll() async {
    final chosen = _candidates!.where((c) => c.include).length;
    setState(() => _progress = (0, chosen, 'Adding…'));
    final result = await _importer.addAll(_candidates!, onProgress: (done) {
      if (mounted) setState(() => _progress = (done, chosen, 'Adding…'));
    });
    if (mounted) Navigator.of(context).pop(result);
  }

  Future<void> _research(ImportCandidate c) async {
    final picked = await showDialog<MalSearchResult>(
      context: context,
      builder: (_) => _MatchSearchDialog(malClient: widget.malClient, initialQuery: c.folderTitle),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (!c.matches.any((m) => m.id == picked.id)) c.matches = [picked, ...c.matches];
      c.match = c.matches.firstWhere((m) => m.id == picked.id);
      c.error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final candidates = _candidates;
    final chosen = candidates?.where((c) => c.include).length ?? 0;
    final progress = _progress;

    return Dialog(
      backgroundColor: theme.colorScheme.surface.withAlpha(242),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1000, maxHeight: 680),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Import a Folder of Shows', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 4),
              const Text('Every sub-folder is treated as one show and matched on MyAnimeList. '
                  'Review the matches before adding.'),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _pathController,
                    enabled: !_busy,
                    onSubmitted: (_) => _scan(),
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Parent folder',
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
              ]),
              const SizedBox(height: 12),
              if (progress != null) ...[
                Text(progress.$2 == 0 ? progress.$3 : '${progress.$3} ${progress.$1} / ${progress.$2}'),
                const SizedBox(height: 6),
                LinearProgressIndicator(value: progress.$2 == 0 ? null : progress.$1 / progress.$2),
              ] else if (_error != null)
                Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
              if (candidates != null && candidates.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('${candidates.length} new folders'
                    '${_skippedExisting > 0 ? ' · $_skippedExisting already in library (skipped)' : ''}'),
                const SizedBox(height: 8),
                Flexible(
                  child: Material(
                    type: MaterialType.transparency,
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: candidates.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) => _CandidateRow(
                        candidate: candidates[i],
                        enabled: !_busy,
                        onChanged: () => setState(() {}),
                        onSearch: () => _research(candidates[i]),
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                TextButton(
                  onPressed: _busy && candidates != null ? null : () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _busy || chosen == 0 ? null : _addAll,
                  icon: const Icon(Icons.library_add),
                  label: Text('Add $chosen ${chosen == 1 ? 'Show' : 'Shows'}'),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

class _CandidateRow extends StatelessWidget {
  final ImportCandidate candidate;
  final bool enabled;
  final VoidCallback onChanged;
  final VoidCallback onSearch;

  const _CandidateRow(
      {required this.candidate, required this.enabled, required this.onChanged, required this.onSearch});

  @override
  Widget build(BuildContext context) {
    final c = candidate;
    final hasVideos = c.episodes.isNotEmpty;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Checkbox(
          value: c.include,
          onChanged: enabled && hasVideos
              ? (v) {
                  c.include = v ?? false;
                  onChanged();
                }
              : null,
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 280,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(c.folderName, maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(
              [if (hasVideos) '${c.episodes.length} video files', if (c.error != null) c.error!].join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(color: c.error != null ? theme.colorScheme.error : null),
            ),
          ]),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: DropdownButton<int>(
            isExpanded: true,
            value: c.match?.id ?? -1,
            onChanged: enabled && hasVideos
                ? (id) {
                    c.match = id == -1 ? null : c.matches.firstWhere((m) => m.id == id);
                    onChanged();
                  }
                : null,
            items: [
              for (final m in c.matches)
                DropdownMenuItem(value: m.id, child: Text(m.label, maxLines: 1, overflow: TextOverflow.ellipsis)),
              DropdownMenuItem(
                value: -1,
                child: Text('No metadata — add as "${c.folderTitle}"', maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Search MyAnimeList',
          onPressed: enabled && hasVideos ? onSearch : null,
          icon: const Icon(Icons.search),
        ),
      ]),
    );
  }
}

/// Free-text MAL search that pops with the picked result.
class _MatchSearchDialog extends StatefulWidget {
  final MalClient malClient;
  final String initialQuery;

  const _MatchSearchDialog({required this.malClient, required this.initialQuery});

  @override
  State<_MatchSearchDialog> createState() => _MatchSearchDialogState();
}

class _MatchSearchDialogState extends State<_MatchSearchDialog> {
  late final _controller = TextEditingController(text: widget.initialQuery);
  List<MalSearchResult> _results = [];
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final results = await widget.malClient.search(_controller.text);
      if (mounted) setState(() => _results = results);
      if (results.isEmpty) throw const MalException('No results.');
    } on MalException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Search MyAnimeList'),
      content: SizedBox(
        width: 500,
        height: 400,
        child: Column(children: [
          TextField(
            controller: _controller,
            autofocus: true,
            onSubmitted: (_) => _search(),
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              isDense: true,
              suffixIcon: IconButton(onPressed: _busy ? null : _search, icon: const Icon(Icons.search)),
            ),
          ),
          const SizedBox(height: 8),
          if (_busy) const LinearProgressIndicator(),
          if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          Expanded(
            child: ListView(children: [
              for (final r in _results) ListTile(title: Text(r.label), onTap: () => Navigator.of(context).pop(r)),
            ]),
          ),
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel'))],
    );
  }
}
