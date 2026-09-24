import 'package:flutter/material.dart';

import '../config.dart';
import '../data/library_repository.dart';
import '../services/mal_client.dart';

class SettingsPage extends StatefulWidget {
  final LibraryRepository repository;
  final MalClient malClient;

  const SettingsPage({super.key, required this.repository, required this.malClient});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _clientIdController = TextEditingController();
  late double _threshold = widget.repository.watchedThreshold;

  /// The stored override, to tell whether the text field has unsaved edits.
  String? _savedClientId;

  LibraryRepository get _repo => widget.repository;

  @override
  void initState() {
    super.initState();
    _repo.malClientIdOverride().then((id) {
      if (!mounted) return;
      setState(() => _savedClientId = id);
      _clientIdController.text = id ?? '';
    });
  }

  @override
  void dispose() {
    _clientIdController.dispose();
    super.dispose();
  }

  Future<void> _saveClientId(String? id) async {
    await _repo.setMalClientId(id);
    final saved = await _repo.malClientIdOverride();
    widget.malClient.clientId = saved ?? AppConfig.malClientId;
    if (!mounted) return;
    setState(() => _savedClientId = saved);
    _clientIdController.text = saved ?? '';
    _toast(saved == null ? 'Using the built-in MyAnimeList client ID' : 'MyAnimeList client ID saved');
  }

  Future<void> _clearHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear watch history?'),
        content: const Text(
          'Every episode becomes unwatched and all resume positions are forgotten. '
          'Your library and files are not touched. This cannot be undone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Clear History')),
        ],
      ),
    );
    if (confirmed != true) return;
    await _repo.clearWatchHistory();
    _toast('Watch history cleared');
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..removeCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final edited = _clientIdController.text.trim() != (_savedClientId ?? '');
    Widget section(String title) => Padding(
      padding: const EdgeInsets.fromLTRB(0, 24, 0, 8),
      child: Text(title, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              section('MyAnimeList'),
              const Text(
                'Metadata lookups use a MyAnimeList API client ID. Leave this empty to use the built-in one, '
                'or create your own at myanimelist.net/apiconfig.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _clientIdController,
                onChanged: (_) => setState(() {}),
                onSubmitted: (v) => _saveClientId(v),
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  labelText: 'Client ID',
                  hintText: 'Built-in client ID',
                  helperText: _savedClientId == null ? 'Using the built-in client ID' : 'Using your client ID',
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _savedClientId == null ? null : () => _saveClientId(null),
                    child: const Text('Use Built-in'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: edited ? () => _saveClientId(_clientIdController.text) : null,
                    child: const Text('Save'),
                  ),
                ],
              ),
              section('Playback'),
              Text('Mark an episode as watched after ${(_threshold * 100).round()} % of it has played'),
              Slider(
                value: _threshold,
                min: LibraryRepository.minWatchedThreshold,
                max: 1,
                divisions: 10,
                label: '${(_threshold * 100).round()} %',
                onChanged: (v) => setState(() => _threshold = v),
                onChangeEnd: _repo.setWatchedThreshold,
              ),
              Text('Applies to episodes you watch from now on.', style: theme.textTheme.bodySmall),
              section('Watch history'),
              const Text('Forget which episodes you watched and where you stopped.'),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: theme.colorScheme.error),
                  onPressed: _clearHistory,
                  icon: const Icon(Icons.delete_sweep_outlined),
                  label: const Text('Clear Watch History'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
