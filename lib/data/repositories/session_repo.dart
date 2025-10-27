import 'dart:async';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import '../models/session.dart';

class SessionRepo {
  static final SessionRepo _i = SessionRepo._internal();
  factory SessionRepo() => _i;
  SessionRepo._internal();

  Database? _db;

  Future<Database> _open() async {
    if (_db != null) return _db!;
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'track_child_dev.db');
    _db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE sessions(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            created_at TEXT NOT NULL,
            template_key TEXT NOT NULL,
            h REAL NOT NULL,
            dstar REAL NOT NULL,
            cotl REAL NOT NULL,
            blank REAL NOT NULL
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_sessions_template ON sessions(template_key)',
        );
        await db.execute(
          'CREATE INDEX idx_sessions_created ON sessions(created_at)',
        );
      },
    );
    return _db!;
  }

  Future<int> insert(Session s) async {
    final db = await _open();
    return db.insert(
      'sessions',
      s.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Session>> listAll({String? templateKey, int? limit}) async {
    final db = await _open();
    final where = <String>[];
    final args = <Object?>[];
    if (templateKey != null) {
      where.add('template_key = ?');
      args.add(templateKey);
    }
    final rows = await db.query(
      'sessions',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'datetime(created_at) ASC',
      limit: limit,
    );
    return rows.map(Session.fromMap).toList();
  }

  Future<void> clearAll() async {
    final db = await _open();
    await db.delete('sessions');
  }
}
