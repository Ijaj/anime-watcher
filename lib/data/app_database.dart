import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Opens the app's single SQLite database and runs schema migrations.
class AppDatabase {
  static const int version = 1;
  static const String fileName = 'anime_watcher.db';

  /// Opens the database. Pass [path] (e.g. [inMemoryDatabasePath]) and
  /// [factory] to override the defaults in tests.
  static Future<Database> open({String? path, DatabaseFactory? factory}) async {
    factory ??= databaseFactoryFfi;
    path ??= p.join((await getApplicationSupportDirectory()).path, fileName);
    return factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: version,
        singleInstance: path != inMemoryDatabasePath,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, _) => _migrate(db, 0, version),
        onUpgrade: _migrate,
      ),
    );
  }

  static Future<void> _migrate(Database db, int from, int to) async {
    final batch = db.batch();
    if (from < 1) {
      batch.execute('''
        CREATE TABLE items (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          mal_id INTEGER,
          type TEXT NOT NULL,
          title TEXT NOT NULL,
          root_path TEXT NOT NULL UNIQUE,
          genres TEXT NOT NULL DEFAULT '[]',
          synopsis TEXT,
          image_medium TEXT,
          image_large TEXT,
          airing INTEGER NOT NULL DEFAULT 0,
          total_episodes INTEGER,
          score REAL,
          added_at INTEGER NOT NULL
        )''');
      batch.execute('''
        CREATE TABLE episodes (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          item_id INTEGER NOT NULL REFERENCES items(id) ON DELETE CASCADE,
          season INTEGER NOT NULL,
          number INTEGER NOT NULL,
          path TEXT NOT NULL UNIQUE
        )''');
      batch.execute('CREATE INDEX idx_episodes_item ON episodes(item_id, season, number)');
      batch.execute('''
        CREATE TABLE watch_progress (
          episode_id INTEGER PRIMARY KEY REFERENCES episodes(id) ON DELETE CASCADE,
          position_ms INTEGER NOT NULL DEFAULT 0,
          duration_ms INTEGER NOT NULL DEFAULT 0,
          completed INTEGER NOT NULL DEFAULT 0,
          updated_at INTEGER NOT NULL
        )''');
      batch.execute('''
        CREATE TABLE settings (
          key TEXT PRIMARY KEY,
          value TEXT
        )''');
    }
    await batch.commit(noResult: true);
  }
}
