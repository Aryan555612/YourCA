import 'dart:async';
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

    // Hard cutoff: delete all transactions before July 12, 2026
    await _database!.delete(
      'transactions',
      where: "date < ?",
      whereArgs: [DateTime(2026, 7, 12).toIso8601String()],
    );

    // SQLite Cleanup: Delete duplicate rows in transactions table
    // 1. Deduplicate by bank_reference (if not null)
    await _database!.rawDelete('''
      DELETE FROM transactions 
      WHERE bank_reference IS NOT NULL 
        AND id NOT IN (
          SELECT MIN(id) 
          FROM transactions 
          GROUP BY bank_reference
        )
    ''');

    // 2. Deduplicate by raw_text (if not null)
    await _database!.rawDelete('''
      DELETE FROM transactions 
      WHERE raw_text IS NOT NULL 
        AND id NOT IN (
          SELECT MIN(id) 
          FROM transactions 
          GROUP BY raw_text
        )
    ''');

    // 3. Deduplicate by unique key: user_id, amount, date, merchant
    await _database!.rawDelete('''
      DELETE FROM transactions 
      WHERE id NOT IN (
        SELECT MIN(id) 
        FROM transactions 
        GROUP BY user_id, amount, date, merchant
      )
    ''');

    return _database!;
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
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final path = join(documentsDirectory.path, 'yourca_local.db');

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
