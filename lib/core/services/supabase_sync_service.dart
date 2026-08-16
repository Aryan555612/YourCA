import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sqflite/sqflite.dart';
import 'database_helper.dart';

class SupabaseSyncService {
  static final SupabaseSyncService instance = SupabaseSyncService._();
  SupabaseSyncService._();

  SupabaseClient? get _client {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  /// Restore cloud backup from Supabase PostgreSQL tables into local SQLite
  Future<void> restoreFromCloud(String userId) async {
    final client = _client;
    if (client == null || userId.isEmpty) return;

    try {
      final db = await DatabaseHelper.instance.database;

      // 1. Restore Profile
      final profileResponse = await client
          .from('user_profiles')
          .select()
          .eq('user_id', userId)
          .maybeSingle();

      if (profileResponse != null) {
        await db.insert(
          'user_profiles',
          {
            'id': profileResponse['id'] ?? userId,
            'name': profileResponse['name'] ?? '',
            'email': profileResponse['email'] ?? '',
            'monthly_income': profileResponse['monthly_income'] ?? 0.0,
            'updated_at': profileResponse['updated_at'] ?? DateTime.now().toIso8601String(),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      // 2. Restore Transactions
      final txs = await client.from('transactions').select().eq('user_id', userId);
      for (final tx in txs) {
        await db.insert(
          'transactions',
          {
            'id': tx['id'],
            'amount': (tx['amount'] as num).toDouble(),
            'type': tx['type'],
            'category': tx['category'],
            'merchant': tx['merchant'] ?? '',
            'note': tx['note'] ?? '',
            'bank_reference': tx['bank_reference'],
            'date': tx['date'],
            'is_excluded': (tx['is_excluded'] == true || tx['is_excluded'] == 1) ? 1 : 0,
            'is_user_edited': (tx['is_user_edited'] == true || tx['is_user_edited'] == 1) ? 1 : 0,
            'original_sms_body': tx['original_sms_body'],
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      // 3. Restore Savings Plans
      final plans = await client.from('savings_plans').select().eq('user_id', userId);
      for (final plan in plans) {
        await db.insert(
          'savings_plans',
          {
            'id': plan['id'],
            'title': plan['title'],
            'target_amount': (plan['target_amount'] as num).toDouble(),
            'current_amount': (plan['current_amount'] as num).toDouble(),
            'monthly_contribution': (plan['monthly_contribution'] as num).toDouble(),
            'target_date': plan['target_date'],
            'category': plan['category'],
            'notes': plan['notes'],
            'is_completed': (plan['is_completed'] == true || plan['is_completed'] == 1) ? 1 : 0,
            'created_at': plan['created_at'],
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      // 4. Restore Custom Categories
      final cats = await client.from('custom_categories').select().eq('user_id', userId);
      for (final cat in cats) {
        await db.insert(
          'custom_categories',
          {
            'id': cat['id'],
            'name': cat['name'],
            'icon_name': cat['icon_name'],
            'color_value': cat['color_value'],
            'type': cat['type'],
            'budget_limit': cat['budget_limit'] != null ? (cat['budget_limit'] as num).toDouble() : null,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      DatabaseHelper.instance.notifyChange('transactions');
      DatabaseHelper.instance.notifyChange('savings_plans');
      DatabaseHelper.instance.notifyChange('custom_categories');
      DatabaseHelper.instance.notifyChange('user_profiles');
    } catch (e) {
      debugPrint('Supabase restoreFromCloud warning: $e');
    }
  }

  /// Sync local SQLite data to Supabase
  Future<void> syncToCloud(String userId) async {
    final client = _client;
    if (client == null || userId.isEmpty) return;

    try {
      final db = await DatabaseHelper.instance.database;

      // Sync Transactions
      final txs = await db.query('transactions');
      if (txs.isNotEmpty) {
        final payload = txs.map((tx) => {...tx, 'user_id': userId}).toList();
        await client.from('transactions').upsert(payload);
      }

      // Sync Savings Plans
      final plans = await db.query('savings_plans');
      if (plans.isNotEmpty) {
        final payload = plans.map((plan) => {...plan, 'user_id': userId}).toList();
        await client.from('savings_plans').upsert(payload);
      }

      // Sync Custom Categories
      final cats = await db.query('custom_categories');
      if (cats.isNotEmpty) {
        final payload = cats.map((cat) => {...cat, 'user_id': userId}).toList();
        await client.from('custom_categories').upsert(payload);
      }
    } catch (e) {
      debugPrint('Supabase syncToCloud warning: $e');
    }
  }
}
