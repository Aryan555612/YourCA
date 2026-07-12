import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import '../../core/services/database_helper.dart';
import '../models/models.dart';

final userRepositoryProvider = Provider<UserRepository>((ref) {
  return UserRepository();
});

class UserRepository {
  UserRepository();

  Future<Database> get _db => DatabaseHelper.instance.database;

  UserProfile _fromRow(Map<String, dynamic> row) {
    return UserProfile(
      id: row['id'] as String,
      name: row['name'] as String? ?? '',
      phoneNumber: row['phone_number'] as String? ?? '',
      createdAt: DateTime.parse(row['created_at'] as String),
      monthlyIncomeSeed: (row['monthly_income_seed'] as num?)?.toDouble() ?? 0.0,
      savingsTargetRate: (row['savings_target_rate'] as num?)?.toDouble() ?? 0.30,
    );
  }

  Map<String, dynamic> _toRow(UserProfile profile) {
    return {
      'id': profile.id,
      'name': profile.name,
      'phone_number': profile.phoneNumber,
      'created_at': profile.createdAt.toIso8601String(),
      'monthly_income_seed': profile.monthlyIncomeSeed,
      'savings_target_rate': profile.savingsTargetRate,
    };
  }

  Future<UserProfile?> fetchProfile(String userId) async {
    final db = await _db;
    final maps = await db.query(
      'user_profiles',
      where: 'id = ?',
      whereArgs: [userId],
    );
    if (maps.isEmpty) return null;
    return _fromRow(maps.first);
  }

  Stream<UserProfile?> watchProfile(String userId) {
    final controller = StreamController<UserProfile?>();

    Future<void> _fetch() async {
      try {
        final profile = await fetchProfile(userId);
        if (!controller.isClosed) controller.add(profile);
      } catch (e) {
        if (!controller.isClosed) controller.addError(e);
      }
    }

    _fetch();

    final sub = DatabaseHelper.instance.changeStream.listen((table) {
      if (table == 'user_profiles') {
        _fetch();
      }
    });

    controller.onCancel = () {
      sub.cancel();
      controller.close();
    };

    return controller.stream;
  }

  Future<void> createProfile(UserProfile profile, {bool syncToCloud = true}) async {
    final db = await _db;
    await db.insert(
      'user_profiles',
      _toRow(profile),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    DatabaseHelper.instance.notifyChange('user_profiles');

    if (syncToCloud) {
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(profile.id)
            .set(profile.toFirestore(), SetOptions(merge: true));
      } catch (_) {}
    }
  }

  Future<void> updateProfile(UserProfile profile, {bool syncToCloud = true}) async {
    final db = await _db;
    await db.update(
      'user_profiles',
      _toRow(profile),
      where: 'id = ?',
      whereArgs: [profile.id],
    );
    DatabaseHelper.instance.notifyChange('user_profiles');

    if (syncToCloud) {
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(profile.id)
            .set(profile.toFirestore(), SetOptions(merge: true));
      } catch (_) {}
    }
  }

  // ── Merchant correction lookup ─────────────────────────────────────────
  Future<String?> fetchMerchantCorrection(String userId, String merchant) async {
    final db = await _db;
    final maps = await db.query(
      'merchant_corrections',
      where: 'user_id = ? AND merchant = ?',
      whereArgs: [userId, merchant.toLowerCase().trim()],
    );
    if (maps.isEmpty) return null;
    return maps.first['category'] as String?;
  }

  Future<void> saveMerchantCorrection(
      String userId, String merchant, String category) async {
    final db = await _db;
    final id = '${userId}_${merchant.toLowerCase().replaceAll(RegExp(r'\s+'), '_')}';
    await db.insert(
      'merchant_corrections',
      {
        'id': id,
        'user_id': userId,
        'merchant': merchant.toLowerCase().trim(),
        'category': category,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    DatabaseHelper.instance.notifyChange('merchant_corrections');
  }

  Future<Map<String, String>> fetchAllCorrections(String userId) async {
    final db = await _db;
    final maps = await db.query(
      'merchant_corrections',
      where: 'user_id = ?',
      whereArgs: [userId],
    );
    final result = <String, String>{};
    for (final row in maps) {
      final merchant = row['merchant'] as String;
      final category = row['category'] as String;
      result[merchant.toLowerCase().trim()] = category;
    }
    return result;
  }
}
