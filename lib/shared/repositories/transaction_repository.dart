import 'package:cloud_firestore/cloud_firestore.dart' hide Transaction;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/models.dart';
import '../../features/categories/categorization_service.dart';

final transactionRepositoryProvider = Provider<TransactionRepository>((ref) {
  return TransactionRepository(FirebaseFirestore.instance, ref);
});

class TransactionRepository {
  final FirebaseFirestore _firestore;
  final Ref _ref;

  TransactionRepository(this._firestore, this._ref);

  CollectionReference<Map<String, dynamic>> _txCol(String userId) =>
      _firestore.collection('users').doc(userId).collection('transactions');

  // ── Stream all transactions for the current month ──────────────────────
  Stream<List<Transaction>> watchMonthTransactions(
      String userId, DateTime month) {
    final start = DateTime(month.year, month.month, 1);
    final end = DateTime(month.year, month.month + 1, 0, 23, 59, 59);

    return _txCol(userId)
        .where('date', isGreaterThanOrEqualTo: start.toIso8601String())
        .where('date', isLessThanOrEqualTo: end.toIso8601String())
        .orderBy('date', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => Transaction.fromFirestore(d.data(), d.id))
            .toList());
  }

  // ── Stream recent transactions (paginated) ─────────────────────────────
  Stream<List<Transaction>> watchRecent(String userId, {int limit = 50}) {
    return _txCol(userId)
        .orderBy('date', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => Transaction.fromFirestore(d.data(), d.id))
            .toList());
  }

  // ── Add single transaction ─────────────────────────────────────────────
  Future<String> add(Transaction tx) async {
    final docRef = await _txCol(tx.userId).add(tx.toFirestore());
    return docRef.id;
  }

  // ── Bulk add (CSV import) ──────────────────────────────────────────────
  Future<void> addBatch(List<Transaction> transactions) async {
    if (transactions.isEmpty) return;
    final batch = _firestore.batch();
    for (final tx in transactions) {
      final docRef = _txCol(tx.userId).doc();
      batch.set(docRef, tx.toFirestore());
    }
    await batch.commit();
  }

  // ── Update transaction ─────────────────────────────────────────────────
  Future<void> update(Transaction tx) async {
    await _txCol(tx.userId).doc(tx.id).update(tx.toFirestore());
  }

  // ── Delete transaction ─────────────────────────────────────────────────
  Future<void> delete(String userId, String txId) async {
    await _txCol(userId).doc(txId).delete();
  }

  // ── Fetch single transaction ───────────────────────────────────────────
  Future<Transaction?> fetchById(String userId, String txId) async {
    final doc = await _txCol(userId).doc(txId).get();
    if (!doc.exists) return null;
    return Transaction.fromFirestore(doc.data()!, doc.id);
  }

  // ── Fetch all transactions (for summary computation) ───────────────────
  Future<List<Transaction>> fetchMonth(String userId, DateTime month) async {
    final start = DateTime(month.year, month.month, 1);
    final end = DateTime(month.year, month.month + 1, 0, 23, 59, 59);

    final snap = await _txCol(userId)
        .where('date', isGreaterThanOrEqualTo: start.toIso8601String())
        .where('date', isLessThanOrEqualTo: end.toIso8601String())
        .get();

    return snap.docs
        .map((d) => Transaction.fromFirestore(d.data(), d.id))
        .toList();
  }
}
