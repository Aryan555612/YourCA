import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import '../../core/services/database_helper.dart';
import '../../core/services/activity_logger.dart';
import '../../shared/models/models.dart';
import '../auth/auth_provider.dart';

final savingsPlansStreamProvider = StreamProvider<List<SavingsPlan>>((ref) {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return Stream.value([]);

  final controller = StreamController<List<SavingsPlan>>();

  Future<void> _fetch() async {
    try {
      final db = await DatabaseHelper.instance.database;
      final maps = await db.query(
        'savings_plans',
        where: 'user_id = ?',
        whereArgs: [userId],
        orderBy: 'created_at DESC',
      );
      final list = maps.map((row) {
        return SavingsPlan(
          id: row['id'] as String,
          userId: row['user_id'] as String,
          title: row['title'] as String,
          description: row['description'] as String,
          targetAmount: row['target_amount'] as double,
          savedAmount: row['saved_amount'] as double,
          targetDate: DateTime.parse(row['target_date'] as String),
          isCustom: (row['is_custom'] as int) == 1,
          createdAt: DateTime.parse(row['created_at'] as String),
        );
      }).toList();

      if (!controller.isClosed) controller.add(list);
    } catch (e) {
      if (!controller.isClosed) controller.addError(e);
    }
  }

  _fetch();

  final sub = DatabaseHelper.instance.changeStream.listen((table) {
    if (table == 'savings_plans') {
      _fetch();
    }
  });

  controller.onCancel = () {
    sub.cancel();
    controller.close();
  };

  return controller.stream;
});

final savingsPlanRepositoryProvider = Provider<SavingsPlanRepository>((ref) {
  return SavingsPlanRepository();
});

class SavingsPlanRepository {
  Future<Database> get _db => DatabaseHelper.instance.database;

  Future<void> addPlan(String userId, SavingsPlan plan) async {
    final db = await _db;
    await db.insert(
      'savings_plans',
      {
        'id': plan.id,
        'user_id': userId,
        'title': plan.title,
        'description': plan.description,
        'target_amount': plan.targetAmount,
        'saved_amount': plan.savedAmount,
        'target_date': plan.targetDate.toIso8601String(),
        'is_custom': plan.isCustom ? 1 : 0,
        'created_at': plan.createdAt.toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    DatabaseHelper.instance.notifyChange('savings_plans');

    // Sync new savings plan to Firestore
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('savingsPlans')
          .doc(plan.id)
          .set(plan.toFirestore());
    } catch (_) {}

    ActivityLogger.instance.log(
      event: 'savings_plan_created',
      screen: 'savings',
      details: {
        'plan_id': plan.id,
        'title': plan.title,
        'target_amount': plan.targetAmount,
      },
    );
  }

  Future<void> updateSavedAmount(String userId, String planId, double savedAmount) async {
    final db = await _db;
    await db.update(
      'savings_plans',
      {'saved_amount': savedAmount},
      where: 'id = ? AND user_id = ?',
      whereArgs: [planId, userId],
    );
    DatabaseHelper.instance.notifyChange('savings_plans');

    // Sync updated saved amount to Firestore
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('savingsPlans')
          .doc(planId)
          .update({'saved_amount': savedAmount});
    } catch (_) {}

    ActivityLogger.instance.log(
      event: 'savings_amount_updated',
      screen: 'savings',
      details: {
        'plan_id': planId,
        'new_saved_amount': savedAmount,
      },
    );
  }

  Future<void> deletePlan(String userId, String planId) async {
    final db = await _db;
    await db.delete(
      'savings_plans',
      where: 'id = ? AND user_id = ?',
      whereArgs: [planId, userId],
    );
    DatabaseHelper.instance.notifyChange('savings_plans');

    // Delete savings plan from Firestore too
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('savingsPlans')
          .doc(planId)
          .delete();
    } catch (_) {}

    ActivityLogger.instance.log(
      event: 'savings_plan_deleted',
      screen: 'savings',
      details: {'plan_id': planId},
    );
  }
}
