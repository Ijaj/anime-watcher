import 'dart:io';

import 'package:anime_watcher/models/item.dart';
import 'package:anime_watcher/services/library_scanner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;

  setUp(() async => tmp = await Directory.systemTemp.createTemp('scanner_test'));
  tearDown(() async => tmp.delete(recursive: true));

  Future<void> touch(String relative) async {
    final f = File(p.join(tmp.path, relative));
    await f.create(recursive: true);
  }

  List<String> codes(List<dynamic> eps) => [
    for (final e in eps) 'S${e.season}E${e.number} ${p.relative(e.path, from: tmp.path)}',
  ];

  test('season folders and SxxEyy files', () async {
    await touch('Season 1/Show S01E01.mkv');
    await touch('Season 1/Show S01E02.mkv');
    await touch('Season 2/[Grp] Show - 01.mkv');
    await touch('Season 2/[Grp] Show - 02.mkv');
    await touch('Specials/Show OVA 1.mkv');
    await touch('Season 1/Show S01E01.srt');
    await touch('Season 1/Sample/sample.mkv');

    final eps = await LibraryScanner.scan(tmp.path);
    expect(codes(eps), [
      'S0E1 ${p.join('Specials', 'Show OVA 1.mkv')}',
      'S1E1 ${p.join('Season 1', 'Show S01E01.mkv')}',
      'S1E2 ${p.join('Season 1', 'Show S01E02.mkv')}',
      'S2E1 ${p.join('Season 2', '[Grp] Show - 01.mkv')}',
      'S2E2 ${p.join('Season 2', '[Grp] Show - 02.mkv')}',
    ]);
  });

  test('root folder name supplies the season', () async {
    final root = Directory(p.join(tmp.path, 'Show.S03.1080p'));
    await File(p.join(root.path, 'Show - 01.mkv')).create(recursive: true);
    final eps = await LibraryScanner.scan(root.path);
    expect(eps.single.season, 3);
    expect(eps.single.number, 1);
  });

  test('unnumbered files are ordered naturally after numbered ones', () {
    final eps = LibraryScanner.assign('/r', ['/r/b.mkv', '/r/Show - 02.mkv', '/r/a.mkv', '/r/Show - 01.mkv']);
    expect(
      [for (final e in eps) '${e.number} ${p.basename(e.path)}'],
      ['1 Show - 01.mkv', '2 Show - 02.mkv', '3 a.mkv', '4 b.mkv'],
    );
  });

  test('duplicate numbers do not collide', () {
    final eps = LibraryScanner.assign('/r', ['/r/Show - 01.mkv', '/r/Show - 01v2.mkv']);
    expect(eps.map((e) => e.number).toSet().length, 2);
  });

  test('missing folder throws', () {
    expect(LibraryScanner.scan(p.join(tmp.path, 'nope')), throwsA(isA<FileSystemException>()));
  });

  group('rescan', () {
    LibraryEntry entry(String root, int episodeCount) => LibraryEntry(
      item: LibraryItem(type: MediaType.anime, title: 'Show', rootPath: root),
      episodeCount: episodeCount,
      watchedCount: 0,
    );

    test('missing folder is skipped', () async {
      expect(await LibraryScanner.rescan(entry(p.join(tmp.path, 'unplugged'), 3)), isNull);
    });
    test('a folder that lost every file is skipped', () async {
      expect(await LibraryScanner.rescan(entry(tmp.path, 3)), isNull);
    });
    test('an empty folder that never had episodes is scanned', () async {
      expect(await LibraryScanner.rescan(entry(tmp.path, 0)), isEmpty);
    });
    test('an available folder is scanned', () async {
      await touch('Show - 01.mkv');
      expect(await LibraryScanner.rescan(entry(tmp.path, 3)), hasLength(1));
    });
  });
}
