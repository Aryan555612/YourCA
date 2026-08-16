import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart' hide Transaction;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart' hide Transaction;
import '../../core/services/database_helper.dart';
import '../models/models.dart';

final transactionRepositoryProvider = Provider<TransactionRepository>((ref) {
  return TransactionRepository();
});

class TransactionRepository {
  TransactionRepository();

  Future<Database> get _db => DatabaseHelper.instance.database;

  // Helper map from SQLite to Model
  Transaction _fromRow(Map<String, dynamic> row) {
    return Transaction(
      id: row['id'] as String,
      userId: row['user_id'] as String,
      amount: row['amount'] as double,
      type: row['type'] == 'debit' ? TransactionType.debit : TransactionType.credit,
      category: row['category'] as String,
      merchant: row['merchant'] as String,
      date: DateTime.parse(row['date'] as String),
      source: TransactionSource.values.firstWhere(
        (e) => e.name == (row['source'] as String? ?? 'manual'),
        orElse: () => TransactionSource.manual,
      ),
      rawText: row['raw_text'] as String?,
      createdAt: DateTime.parse(row['created_at'] as String),
      note: row['note'] as String?,
      bankReference: row['bank_reference'] as String?,
    );
  }

  Map<String, dynamic> _toRow(Transaction tx) {
    return {
      'id': tx.id,
      'user_id': tx.userId,
      'amount': tx.amount,
      'type': tx.type.name,
      'category': tx.category,
      'merchant': tx.merchant,
      'date': tx.date.toIso8601String(),
      'source': tx.source.name,
      'raw_text': tx.rawText,
      'created_at': tx.createdAt.toIso8601String(),
      'note': tx.note,
      'bank_reference': tx.bankReference,
    };
  }

  // ── Migrate unassigned/anonymous transactions in SQLite to the current userId ──
  Future<void> migrateUserTransactions(String newUserId) async {
    try {
      final db = await _db;
      await db.rawUpdate(
        "UPDATE transactions SET user_id = ? WHERE user_id IS NULL OR user_id = '' OR user_id LIKE 'anon_%'",
        [newUserId],
      );
      DatabaseHelper.instance.notifyChange('transactions');
    } catch (_) {}
  }

  // ── Stream all transactions for the current month ──────────────────────
  Stream<List<Transaction>> watchMonthTransactions(String userId, DateTime month) {
    final controller = StreamController<List<Transaction>>();

    Future<void> _fetch() async {
      try {
        final list = await fetchMonth(userId, month);
        if (!controller.isClosed) controller.add(list);
      } catch (e) {
        if (!controller.isClosed) controller.addError(e);
      }
    }

    _fetch();

    final sub = DatabaseHelper.instance.changeStream.listen((table) {
      if (table == 'transactions') {
        _fetch();
      }
    });

    controller.onCancel = () {
      sub.cancel();
      controller.close();
    };

    return controller.stream;
  }

  // ── Deduplicate list in memory ───────────────────────────────────────────
  List<Transaction> _deduplicateList(List<Transaction> list) {
    final Set<String> seenKeys = {};
    final List<Transaction> result = [];
    for (final tx in list) {
      String key;
      if (tx.bankReference != null && tx.bankReference!.trim().isNotEmpty) {
        key = 'ref_${tx.bankReference!.trim()}';
      } else {
        final dateStr = tx.date.toIso8601String();
        final dateMinute = dateStr.length >= 16 ? dateStr.substring(0, 16) : dateStr;
        key = 'tx_${tx.userId}_${tx.amount}_${tx.type.name}_${tx.merchant.toLowerCase().trim()}_$dateMinute';
      }
      if (!seenKeys.contains(key)) {
        seenKeys.add(key);
        result.add(tx);
      }
    }
    return result;
  }

  // ── Stream recent transactions (paginated) ─────────────────────────────
  Stream<List<Transaction>> watchRecent(String userId, {int limit = 50}) {
    final controller = StreamController<List<Transaction>>();

    Future<void> _fetch() async {
      try {
        final db = await _db;
        await DatabaseHelper.instance.cleanDuplicates(db);
        var maps = await db.query(
          'transactions',
          where: 'user_id = ?',
          whereArgs: [userId],
          orderBy: 'date DESC',
          limit: limit * 2,
        );
        final rawList = maps.map((row) => _fromRow(row)).toList();
        final list = _deduplicateList(rawList).take(limit).toList();
        if (!controller.isClosed) controller.add(list);
      } catch (e) {
        if (!controller.isClosed) controller.addError(e);
      }
    }

    _fetch();

    final sub = DatabaseHelper.instance.changeStream.listen((table) {
      if (table == 'transactions') {
        _fetch();
      }
    });

    controller.onCancel = () {
      sub.cancel();
      controller.close();
    };

    return controller.stream;
  }

  // ── Add single transaction ─────────────────────────────────────────────
  Future<String> add(Transaction tx, {bool syncToCloud = true}) async {
    final db = await _db;
    await db.insert(
      'transactions',
      _toRow(tx),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await DatabaseHelper.instance.cleanDuplicates(db);
    DatabaseHelper.instance.notifyChange('transactions');

    if (syncToCloud) {
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(tx.userId)
            .collection('transactions')
            .doc(tx.id)
            .set(tx.toFirestore());
      } catch (_) {}
    }
    return tx.id;
  }

  // ── Bulk add (CSV import / Cloud sync) ─────────────────────────────────
  Future<void> addBatch(List<Transaction> transactions, {bool syncToCloud = true}) async {
    if (transactions.isEmpty) return;
    final db = await _db;
    final batch = db.batch();
    for (final tx in transactions) {
      batch.insert(
        'transactions',
        _toRow(tx),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
    await DatabaseHelper.instance.cleanDuplicates(db);
    DatabaseHelper.instance.notifyChange('transactions');

    if (syncToCloud) {
      try {
        final firestoreBatch = FirebaseFirestore.instance.batch();
        for (final tx in transactions) {
          final docRef = FirebaseFirestore.instance
              .collection('users')
              .doc(tx.userId)
              .collection('transactions')
              .doc(tx.id);
          firestoreBatch.set(docRef, tx.toFirestore());
        }
        await firestoreBatch.commit();
      } catch (_) {}
    }
  }

  // ── Update transaction ─────────────────────────────────────────────────
  Future<void> update(Transaction tx, {bool syncToCloud = true}) async {
    final db = await _db;
    await db.update(
      'transactions',
      _toRow(tx),
      where: 'id = ?',
      whereArgs: [tx.id],
    );
    DatabaseHelper.instance.notifyChange('transactions');

    if (syncToCloud) {
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(tx.userId)
            .collection('transactions')
            .doc(tx.id)
            .set(tx.toFirestore(), SetOptions(merge: true));
      } catch (_) {}
    }
  }

  // ── Delete transaction ─────────────────────────────────────────────────
  Future<void> delete(String userId, String txId, {bool syncToCloud = true}) async {
    final db = await _db;
    await db.delete(
      'transactions',
      where: 'id = ? AND user_id = ?',
      whereArgs: [txId, userId],
    );
    DatabaseHelper.instance.notifyChange('transactions');

    if (syncToCloud) {
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .collection('transactions')
            .doc(txId)
            .delete();
      } catch (_) {}
    }
  }

  // ── Fetch single transaction ───────────────────────────────────────────
  Future<Transaction?> fetchById(String userId, String txId) async {
    final db = await _db;
    final maps = await db.query(
      'transactions',
      where: 'id = ? AND user_id = ?',
      whereArgs: [txId, userId],
    );
    if (maps.isEmpty) return null;
    return _fromRow(maps.first);
  }

  // ── Fetch all transactions (for summary computation) ───────────────────
  Future<List<Transaction>> fetchMonth(String userId, DateTime month) async {
    final start = DateTime(month.year, month.month, 1);
    final end = DateTime(month.year, month.month + 1, 0, 23, 59, 59);
    return fetchDateRange(userId, start, end);
  }

  // ── Fetch transactions between two specific dates ──────────────────────
  Future<List<Transaction>> fetchDateRange(
      String userId, DateTime start, DateTime end) async {
    final db = await _db;
    await DatabaseHelper.instance.cleanDuplicates(db);
    var maps = await db.query(
      'transactions',
      where: 'user_id = ? AND date >= ? AND date <= ?',
      whereArgs: [userId, start.toIso8601String(), end.toIso8601String()],
      orderBy: 'date DESC',
    );
    final rawList = maps.map((row) => _fromRow(row)).toList();
    return _deduplicateList(rawList);
  }
}
