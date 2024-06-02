import 'package:path/path.dart';
import 'package:anime_watcher/models/Item.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';


class ItemController{
  static Future<bool> create(Item item) async {
    final String rootDir = item.rootPath;
    String dbPath = join(rootDir, "AnimeWatcher", "anime_watcher.db");
    var db = await databaseFactoryFfi.openDatabase(dbPath);
    await db.execute(r"");
    return true;
  }
}