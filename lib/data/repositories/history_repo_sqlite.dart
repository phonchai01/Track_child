import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import '../models/history_record.dart';

class HistoryRepoSqlite {
  HistoryRepoSqlite._();
  static final HistoryRepoSqlite I = HistoryRepoSqlite._();

  Database? _db;

  Future<Database> _open() async {
    if (_db != null) return _db!;
    final dir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(dir.path, 'histories.db');
    _db = await openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, v) async {
        await db.execute('''
          CREATE TABLE history(
            id TEXT PRIMARY KEY,
            profileKey TEXT NOT NULL,
            createdAt INTEGER NOT NULL,
            templateKey TEXT NOT NULL,
            age INTEGER NOT NULL,
            h REAL NOT NULL,
            c REAL NOT NULL,
            blank REAL NOT NULL,
            cotl REAL NOT NULL,
            zH REAL NOT NULL,
            zC REAL NOT NULL,
            zBlank REAL NOT NULL,
            zCotl REAL NOT NULL,
            zSum REAL NOT NULL,
            level TEXT NOT NULL,
            imagePath TEXT
          );
        ''');
        await db.execute(
          'CREATE INDEX idx_history_profile ON history(profileKey, createdAt DESC);',
        );
      },
    );
    return _db!;
  }

  /// เก็บรูปเป็นไฟล์ (โฟลเดอร์แยกตามโปรไฟล์) แล้วคืน path
  Future<String> saveImageBytes(
    Uint8List bytes, {
    required String profileKey,
  }) async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, 'histories_img', profileKey));
    if (!await dir.exists()) await dir.create(recursive: true);
    final file = File(
      p.join(dir.path, 'preview_${DateTime.now().millisecondsSinceEpoch}.png'),
    );
    await file.writeAsBytes(bytes);
    return file.path;
  }

  /// Insert
  Future<void> add(String profileKey, HistoryRecord r) async {
    final db = await _open();
    final map = r.toMap();
    map['profileKey'] = profileKey;
    await db.insert(
      'history',
      map,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Select ทั้งหมดของโปรไฟล์ (ล่าสุดก่อน)
  Future<List<HistoryRecord>> listByProfile(String profileKey) async {
    final db = await _open();
    final rows = await db.query(
      'history',
      where: 'profileKey = ?',
      whereArgs: [profileKey],
      orderBy: 'createdAt DESC',
    );
    return rows.map((m) => HistoryRecord.fromMap(m)).toList();
  }

  /// ลบทั้งหมดของโปรไฟล์
  Future<void> clearByProfile(String profileKey) async {
    final db = await _open();
    await db.delete(
      'history',
      where: 'profileKey = ?',
      whereArgs: [profileKey],
    );
  }
}
