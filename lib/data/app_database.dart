import 'dart:async';
import 'dart:io' show Platform;

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;

import '../models/link_item.dart';

class AppDatabase {
  static final AppDatabase _instance = AppDatabase._internal();
  factory AppDatabase() => _instance;
  AppDatabase._internal();

  static const _dbName = 'library_links.db';
  static const _dbVersion = 1;
  static const tableLinks = 'links';

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _openDatabase();
    return _db!;
  }

  Future<Database> _openDatabase() async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      ffi.sqfliteFfiInit();
      databaseFactory = ffi.databaseFactoryFfi;
    }
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, _dbName);
    return openDatabase(
      path,
      version: _dbVersion,
      onCreate: (db, version) async {
        await db.execute('''
        CREATE TABLE $tableLinks (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          title TEXT NOT NULL,
          url TEXT NOT NULL,
          cover_path TEXT,
          category TEXT NOT NULL,
          created_at INTEGER NOT NULL,
          last_scroll_position REAL NOT NULL DEFAULT 0
        );
        ''');
        await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_links_category ON $tableLinks(category)');
        await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_links_title ON $tableLinks(title)');
      },
    );
  }

  Future<int> insertLink(LinkItem item) async {
    final db = await database;
    return db.insert(tableLinks, item.toMap());
  }

  Future<int> updateLink(LinkItem item) async {
    final db = await database;
    return db.update(
      tableLinks,
      item.toMap(),
      where: 'id = ?',
      whereArgs: [item.id],
    );
  }

  Future<int> deleteLink(int id) async {
    final db = await database;
    return db.delete(tableLinks, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteLinks(List<int> ids) async {
    if (ids.isEmpty) return 0;
    final db = await database;
    final placeholders = List.filled(ids.length, '?').join(',');
    return await db.rawDelete('DELETE FROM $tableLinks WHERE id IN ($placeholders)', ids);
  }

  Future<List<LinkItem>> getAllLinks({String? query, String? category}) async {
    final db = await database;
    final where = <String>[];
    final args = <Object?>[];
    if (query != null && query.trim().isNotEmpty) {
      where.add('(title LIKE ? OR url LIKE ?)');
      final like = '%${query.trim()}%';
      args.addAll([like, like]);
    }
    if (category != null && category.isNotEmpty && category != 'Tümü') {
      where.add('category = ?');
      args.add(category);
    }
    final whereClause = where.isEmpty ? null : where.join(' AND ');
    final rows = await db.query(
      tableLinks,
      where: whereClause,
      whereArgs: args,
      orderBy: 'created_at DESC',
    );
    return rows.map((e) => LinkItem.fromMap(e)).toList();
  }

  Future<void> updateScrollPosition({required int id, required double y}) async {
    final db = await database;
    await db.update(
      tableLinks,
      {'last_scroll_position': y},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> updateCategoryMany({required List<int> ids, required String category}) async {
    if (ids.isEmpty) return 0;
    final db = await database;
    final placeholders = List.filled(ids.length, '?').join(',');
    return await db.rawUpdate('UPDATE $tableLinks SET category = ? WHERE id IN ($placeholders)', [category, ...ids]);
  }
}


