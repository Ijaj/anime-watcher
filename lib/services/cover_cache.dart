import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../data/library_repository.dart';
import '../models/item.dart';

/// Keeps a copy of every item's cover image in the app-support directory so
/// covers show offline. [CoverImage] falls back to the network URL when the
/// file is missing.
class CoverCache {
  static const _extensions = {'.jpg', '.jpeg', '.png', '.webp', '.gif'};

  final Directory dir;
  final Future<List<int>> Function(String url) _fetch;

  /// Downloads run one pass at a time so an item is never fetched twice.
  Future<void> _queue = Future.value();

  CoverCache(this.dir, {Future<List<int>> Function(String url)? fetch}) : _fetch = fetch ?? _download;

  static Future<CoverCache> open() async =>
      CoverCache(Directory(p.join((await getApplicationSupportDirectory()).path, 'covers')));

  static Future<List<int>> _download(String url) async {
    final response = await Dio(
      BaseOptions(connectTimeout: const Duration(seconds: 10), receiveTimeout: const Duration(seconds: 30)),
    ).get<List<int>>(url, options: Options(responseType: ResponseType.bytes));
    return response.data ?? const [];
  }

  /// Downloads covers for every item that has an image URL but no cached
  /// file (never downloaded, or the file was deleted). Returns how many were
  /// downloaded. Failures are skipped and retried on the next call.
  Future<int> cacheMissing(LibraryRepository repository) {
    final run = _queue.then((_) => _cacheMissing(repository));
    _queue = run.then((_) {}, onError: (_) {});
    return run;
  }

  Future<int> _cacheMissing(LibraryRepository repository) async {
    var downloaded = 0;
    for (final entry in await repository.entries()) {
      final item = entry.item;
      if (item.coverPath != null && await File(item.coverPath!).exists()) continue;
      if (await cache(repository, item) != null) downloaded++;
    }
    return downloaded;
  }

  /// Downloads [item]'s cover and records its path. Returns the path, or
  /// null if the item has no image or the download failed.
  Future<String?> cache(LibraryRepository repository, LibraryItem item) async {
    final url = item.imageLarge ?? item.imageMedium;
    if (url == null || item.id == null) return null;
    try {
      final bytes = await _fetch(url);
      if (bytes.isEmpty) return null;
      await dir.create(recursive: true);
      final ext = p.extension(Uri.parse(url).path).toLowerCase();
      final file = File(p.join(dir.path, '${item.id}${_extensions.contains(ext) ? ext : '.jpg'}'));
      // Write then rename, so a failed write never leaves a truncated image.
      final partial = File('${file.path}.part');
      await partial.writeAsBytes(bytes, flush: true);
      await partial.rename(file.path);
      await repository.setCoverPath(item.id!, file.path);
      return file.path;
    } catch (_) {
      return null;
    }
  }

  /// Deletes the cached cover of item [itemId], e.g. when it is removed
  /// from the library. Looks for the file by name, so it also works when the
  /// caller's copy of the item predates the download.
  Future<void> evict(int itemId) async {
    for (final ext in _extensions) {
      final file = File(p.join(dir.path, '$itemId$ext'));
      if (await file.exists()) await file.delete();
    }
  }
}
