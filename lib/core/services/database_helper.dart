import 'dart:async';
import 'dart:io';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._();
  DatabaseHelper._();

  Database? _database;
  final _changeController = StreamController<String>.broadcast();

  Stream<String> get changeStream => _changeController.stream;

  void notifyChange(String table) {
    _changeController.add(table);
  }

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    await _runMigrations(_database!);
    await cleanDuplicates(_database!);
    return _database!;
  }

  /// Deduplicate transactions safely in SQLite
  Future<void> cleanDuplicates([Database? targetDb]) async {
    final db = targetDb ?? _database;
    if (db == null) return;
    try {
      // 1. Deduplicate by valid non-empty bank_reference
      await db.rawDelete('''
        DELETE FROM transactions 
        WHERE bank_reference IS NOT NULL 
          AND TRIM(bank_reference) != '' 
          AND id NOT IN (
            SELECT MIN(id) 
            FROM transactions 
            WHERE bank_reference IS NOT NULL AND TRIM(bank_reference) != ''
            GROUP BY bank_reference
          )
      ''');

      // 2. Deduplicate by valid non-empty raw_text
      await db.rawDelete('''
        DELETE FROM transactions 
        WHERE raw_text IS NOT NULL 
          AND TRIM(raw_text) != '' 
          AND id NOT IN (
            SELECT MIN(id) 
            FROM transactions 
            WHERE raw_text IS NOT NULL AND TRIM(raw_text) != ''
            GROUP BY raw_text
          )
      ''');

      // 3. Deduplicate by matching user_id, amount, type, merchant, and minute-level timestamp
      await db.rawDelete('''
        DELETE FROM transactions 
        WHERE id NOT IN (
          SELECT MIN(id) 
          FROM transactions 
          GROUP BY user_id, amount, type, merchant, substr(date, 1, 16)
        )
      ''');
    } catch (e) {
      // Ignore cleanup errors
    }
  }

  Future<void> _runMigrations(Database db) async {
    try {
      final rows = await db.query('transactions');
      for (final row in rows) {
        final id = row['id'] as String;
        final dateStr = row['date'] as String?;
        final createdAtStr = row['created_at'] as String?;
        if (dateStr == null || createdAtStr == null) continue;

        final date = DateTime.tryParse(dateStr);
        final createdAt = DateTime.tryParse(createdAtStr);

        if (date != null && createdAt != null) {
          if (date.hour == 0 && date.minute == 0 && date.second == 0) {
            final updatedDate = DateTime(
              date.year,
              date.month,
              date.day,
              createdAt.hour,
              createdAt.minute,
              createdAt.second,
            );
            await db.update(
              'transactions',
              {'date': updatedDate.toIso8601String()},
              where: 'id = ?',
              whereArgs: [id],
            );
          }
        }
      }
    } catch (_) {}
  }

  Future<Database> _initDatabase() async {
    final databasesPath = await getDatabasesPath();
    final path = join(databasesPath, 'yourca_local.db');

    // Safe migration from legacy app documents path to native databases path
    try {
      final documentsDirectory = await getApplicationDocumentsDirectory();
      final oldPath = join(documentsDirectory.path, 'yourca_local.db');
      final oldFile = File(oldPath);
      final newFile = File(path);
      if (await oldFile.exists() && !(await newFile.exists())) {
        await Directory(databasesPath).create(recursive: true);
        await oldFile.copy(path);
        await oldFile.delete();
      }
    } catch (_) {
      // Catch layout/plugin missing exceptions in background isolates
    }

    return await openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE transactions (
        id TEXT PRIMARY KEY,
        user_id TEXT,
        amount REAL,
        type TEXT,
        category TEXT,
        merchant TEXT,
        date TEXT,
        source TEXT,
        raw_text TEXT,
        created_at TEXT,
        note TEXT,
        bank_reference TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE custom_categories (
        name TEXT PRIMARY KEY,
        emoji TEXT,
        user_id TEXT,
        created_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE savings_plans (
        id TEXT PRIMARY KEY,
        user_id TEXT,
        title TEXT,
        description TEXT,
        target_amount REAL,
        saved_amount REAL,
        target_date TEXT,
        is_custom INTEGER,
        created_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE user_profiles (
        id TEXT PRIMARY KEY,
        name TEXT,
        phone_number TEXT,
        created_at TEXT,
        monthly_income_seed REAL,
        savings_target_rate REAL
      )
    ''');

    await db.execute('''
      CREATE TABLE merchant_corrections (
        id TEXT PRIMARY KEY,
        user_id TEXT,
        merchant TEXT,
        category TEXT
      )
    ''');
  }
}
