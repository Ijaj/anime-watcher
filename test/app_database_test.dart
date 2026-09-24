import 'dart:io';

import 'package:anime_watcher/data/app_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('upgrading a v1 database adds cover_path and keeps items', () async {
    final tmp = await Directory.systemTemp.createTemp('db_test');
    addTearDown(() => tmp.delete(recursive: true));
    final path = p.join(tmp.path, 'v1.db');

    // The v1 items table, as shipped.
    final v1 = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) => db.execute('''
            CREATE TABLE items (
              id INTEGER PRIMARY KEY AUTOINCREMENT, mal_id INTEGER, type TEXT NOT NULL, title TEXT NOT NULL,
              root_path TEXT NOT NULL UNIQUE, genres TEXT NOT NULL DEFAULT '[]', synopsis TEXT, image_medium TEXT,
              image_large TEXT, airing INTEGER NOT NULL DEFAULT 0, total_episodes INTEGER, score REAL,
              added_at INTEGER NOT NULL
            )'''),
      ),
    );
    await v1.insert('items', {'type': 'anime', 'title': 'Old', 'root_path': '/old', 'added_at': 0});
    await v1.close();

    final db = await AppDatabase.open(path: path);
    addTearDown(db.close);
    expect(await db.getVersion(), AppDatabase.version);
    final rows = await db.query('items');
    expect(rows.single['title'], 'Old');
    expect(rows.single.containsKey('cover_path'), isTrue);
  });

  test('a fresh database has the latest schema', () async {
    final db = await AppDatabase.open(path: inMemoryDatabasePath);
    addTearDown(db.close);
    final columns = await db.rawQuery('PRAGMA table_info(items)');
    expect(columns.map((c) => c['name']), contains('cover_path'));
  });
}
