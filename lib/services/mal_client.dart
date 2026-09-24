import 'package:dio/dio.dart';

import '../config.dart';

class MalSearchResult {
  final int id;
  final String title;
  final String? mediaType;
  final int? year;
  final String? imageMedium;

  const MalSearchResult({required this.id, required this.title, this.mediaType, this.year, this.imageMedium});

  factory MalSearchResult.fromNode(Map<String, dynamic> node) => MalSearchResult(
        id: node['id'] as int,
        title: node['title'] as String,
        mediaType: node['media_type'] as String?,
        year: (node['start_season'] as Map<String, dynamic>?)?['year'] as int?,
        imageMedium: (node['main_picture'] as Map<String, dynamic>?)?['medium'] as String?,
      );

  /// e.g. "Frieren (TV, 2023)".
  String get label {
    final extra = [if (mediaType != null) mediaType!.toUpperCase(), if (year != null) '$year'];
    return extra.isEmpty ? title : '$title (${extra.join(', ')})';
  }
}

class MalException implements Exception {
  final String message;
  const MalException(this.message);

  @override
  String toString() => message;
}

/// Minimal MyAnimeList v2 API client.
class MalClient {
  static const detailFields = [
    'id',
    'title',
    'main_picture',
    'alternative_titles',
    'synopsis',
    'mean',
    'media_type',
    'status',
    'genres',
    'num_episodes',
    'start_season',
  ];

  final Dio _dio;

  MalClient({Dio? dio, String clientId = AppConfig.malClientId})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: AppConfig.malBaseUrl,
              headers: {'X-MAL-Client-ID': clientId},
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 15),
            ));

  String get clientId => _dio.options.headers['X-MAL-Client-ID'] as String;

  /// Switches the client ID used by later requests.
  set clientId(String id) => _dio.options.headers['X-MAL-Client-ID'] = id;

  Future<List<MalSearchResult>> search(String query) async {
    var q = query.trim();
    // MAL rejects queries shorter than 3 characters and longer than 64.
    if (q.length < 3) throw const MalException('Title must be at least 3 characters to search.');
    if (q.length > 64) q = q.substring(0, 64);
    final data = await _get('/anime', {
      'q': q,
      'limit': 10,
      'fields': 'media_type,start_season,main_picture',
    });
    return [
      for (final e in (data['data'] as List<dynamic>? ?? const []))
        MalSearchResult.fromNode(e['node'] as Map<String, dynamic>),
    ];
  }

  Future<Map<String, dynamic>> details(int id) => _get('/anime/$id', {'fields': detailFields.join(',')});

  Future<Map<String, dynamic>> _get(String path, Map<String, dynamic> query) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(path, queryParameters: query);
      return response.data ?? const {};
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 401 || status == 403) {
        throw const MalException('MyAnimeList rejected the client ID. Check it in Settings.');
      }
      if (status != null) throw MalException('MyAnimeList request failed (HTTP $status).');
      throw const MalException('Could not reach MyAnimeList. Check your internet connection.');
    }
  }
}
