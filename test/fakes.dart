import 'package:anime_watcher/services/mal_client.dart';

/// Offline [MalClient]: `search` returns [results] for any query whose
/// lowercase form contains the key; `details` builds a minimal response.
class FakeMalClient extends MalClient {
  final Map<String, List<MalSearchResult>> results;
  final bool failDetails;
  final List<String> queries = [];

  FakeMalClient(this.results, {this.failDetails = false});

  @override
  Future<List<MalSearchResult>> search(String query) async {
    queries.add(query);
    if (query.trim().length < 3) throw const MalException('Title must be at least 3 characters to search.');
    for (final e in results.entries) {
      if (query.toLowerCase().contains(e.key)) return e.value;
    }
    return const [];
  }

  @override
  Future<Map<String, dynamic>> details(int id) async {
    if (failDetails) throw const MalException('Could not reach MyAnimeList.');
    final match = results.values.expand((r) => r).firstWhere((r) => r.id == id);
    return {
      'id': id,
      'title': match.title,
      'genres': [
        {'id': 1, 'name': 'Action'},
      ],
      'num_episodes': 12,
      'status': 'finished_airing',
    };
  }
}
