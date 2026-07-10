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
    return _database!;
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
