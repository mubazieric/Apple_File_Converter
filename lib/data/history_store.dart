import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../domain/history/conversion_record.dart';

/// Persistence for the conversion history.
///
/// Behind an interface so the controller and UI are testable with [MemoryHistoryStore] and no
/// platform database.
abstract interface class HistoryStore {
  Future<void> init();

  /// Most recent first.
  Future<List<ConversionRecord>> load({int limit = 300});

  Future<void> add(ConversionRecord record);
  Future<void> remove(String id);
  Future<void> clear();
}

/// SQLite-backed history, stored in the app's support directory.
class SqliteHistoryStore implements HistoryStore {
  static const String _table = 'history';
  Database? _database;

  Future<Database> _open() async {
    final existing = _database;
    if (existing != null) {
      return existing;
    }
    final directory = await getApplicationSupportDirectory();
    final path = p.join(directory.path, 'conversion_history.db');
    final database = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE $_table (
            id TEXT PRIMARY KEY,
            display_name TEXT NOT NULL,
            kind TEXT NOT NULL,
            output_extension TEXT NOT NULL,
            finished_at INTEGER NOT NULL,
            source_path TEXT,
            output_path TEXT,
            source_bytes INTEGER,
            output_bytes INTEGER,
            was_remux INTEGER NOT NULL DEFAULT 0,
            success INTEGER NOT NULL DEFAULT 1,
            error_message TEXT,
            exported_to_gallery INTEGER NOT NULL DEFAULT 0
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_history_finished ON $_table(finished_at DESC)',
        );
      },
    );
    _database = database;
    return database;
  }

  @override
  Future<void> init() async {
    await _open();
  }

  @override
  Future<List<ConversionRecord>> load({int limit = 300}) async {
    final database = await _open();
    final rows = await database.query(
      _table,
      orderBy: 'finished_at DESC',
      limit: limit,
    );
    return rows.map(ConversionRecord.fromMap).toList(growable: false);
  }

  @override
  Future<void> add(ConversionRecord record) async {
    final database = await _open();
    await database.insert(
      _table,
      record.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> remove(String id) async {
    final database = await _open();
    await database.delete(_table, where: 'id = ?', whereArgs: <Object?>[id]);
  }

  @override
  Future<void> clear() async {
    final database = await _open();
    await database.delete(_table);
  }
}

/// Non-persistent history for tests and previews.
class MemoryHistoryStore implements HistoryStore {
  final List<ConversionRecord> _records = <ConversionRecord>[];

  @override
  Future<void> init() async {}

  @override
  Future<List<ConversionRecord>> load({int limit = 300}) async {
    final sorted = List<ConversionRecord>.of(_records)
      ..sort((a, b) => b.finishedAt.compareTo(a.finishedAt));
    return sorted.take(limit).toList(growable: false);
  }

  @override
  Future<void> add(ConversionRecord record) async {
    _records
      ..removeWhere((r) => r.id == record.id)
      ..add(record);
  }

  @override
  Future<void> remove(String id) async {
    _records.removeWhere((r) => r.id == id);
  }

  @override
  Future<void> clear() async => _records.clear();
}
