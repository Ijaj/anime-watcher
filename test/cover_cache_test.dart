import 'dart:io';

import 'package:anime_watcher/data/app_database.dart';
import 'package:anime_watcher/data/library_repository.dart';
import 'package:anime_watcher/models/item.dart';
import 'package:anime_watcher/services/cover_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory tmp;
  late LibraryRepository repo;
  late List<String> fetched;
  late CoverCache cache;

  setUpAll(sqfliteFfiInit);
  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('covers_test');
    repo = LibraryRepository(await AppDatabase.open(path: inMemoryDatabasePath));
    fetched = [];
    cache = CoverCache(Directory(p.join(tmp.path, 'covers')), fetch: (url) async {
      fetched.add(url);
      if (url.contains('broken')) throw const SocketException('offline');
      return [1, 2, 3];
    });
  });
  tearDown(() async {
    await repo.close();
    await tmp.delete(recursive: true);
  });

  Future<LibraryItem> add(String root, {String? large, String? medium}) => repo.addItem(
      LibraryItem(type: MediaType.anime, title: root, rootPath: root, imageLarge: large, imageMedium: medium),
      const []);

  Future<String?> storedPath(int id) async => (await repo.item(id))!.coverPath;

  test('cache downloads the large image and records its path', () async {
    final item = await add('/a', large: 'https://cdn.example/images/a.webp?s=1', medium: 'https://cdn.example/a_m.jpg');
    final path = await cache.cache(repo, item);
    expect(path, p.join(tmp.path, 'covers', '${item.id}.webp'));
    expect(await File(path!).readAsBytes(), [1, 2, 3]);
    expect(await storedPath(item.id!), path);
    expect(fetched, ['https://cdn.example/images/a.webp?s=1']);
  });

  test('failed or missing images are not recorded', () async {
    final broken = await add('/broken', medium: 'https://cdn.example/broken.jpg');
    final none = await add('/none');
    expect(await cache.cache(repo, broken), isNull);
    expect(await cache.cache(repo, none), isNull);
    expect(await storedPath(broken.id!), isNull);
    expect(fetched, ['https://cdn.example/broken.jpg']);
  });

  test('cacheMissing fills gaps and re-downloads deleted files', () async {
    final a = await add('/a', large: 'https://cdn.example/a');
    await add('/b', medium: 'https://cdn.example/b.png');
    await add('/none');

    expect(await cache.cacheMissing(repo), 2);
    expect(p.basename((await storedPath(a.id!))!), '${a.id}.jpg', reason: 'unknown extension defaults to .jpg');
    expect(await cache.cacheMissing(repo), 0, reason: 'already cached');

    await File((await storedPath(a.id!))!).delete();
    expect(await cache.cacheMissing(repo), 1);
    expect(fetched.where((u) => u == 'https://cdn.example/a'), hasLength(2));
  });

  test('concurrent cacheMissing calls do not download twice', () async {
    await add('/a', large: 'https://cdn.example/a.jpg');
    final counts = await Future.wait([cache.cacheMissing(repo), cache.cacheMissing(repo)]);
    expect(counts, [1, 0]);
    expect(fetched, hasLength(1));
  });

  test('evict deletes the cached file', () async {
    final a = await add('/a', large: 'https://cdn.example/a.png');
    final path = (await cache.cache(repo, a))!;
    await cache.evict(a.id!);
    expect(await File(path).exists(), isFalse);
    await cache.evict(a.id!); // nothing left to delete
  });
}
