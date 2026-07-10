import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:another_telephony/telephony.dart';
import 'package:uuid/uuid.dart';
import '../../shared/models/models.dart';
import '../../shared/repositories/transaction_repository.dart';
import '../../features/auth/auth_provider.dart';
import '../../features/categories/categorization_service.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:sqflite/sqflite.dart' hide Transaction;
import '../../core/services/database_helper.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../core/services/notification_service.dart';
import 'bank_sms_parser.dart';

/// Provider that starts the background SMS listener on Android.
/// No-op on iOS and Web.
final smsListenerProvider = Provider<SmsListenerService>((ref) {
  return SmsListenerService(ref);
});

class SmsListenerService {
  final Ref _ref;
  final Telephony _telephony = Telephony.instance;
  bool _isListening = false;

  SmsListenerService(this._ref);

  /// Start listening for incoming SMS on Android.
  void start() {
    if (!Platform.isAndroid) return;
    if (_isListening) return;
    _isListening = true;

    _telephony.listenIncomingSms(
      onNewMessage: (SmsMessage message) {
        _handleSms(
          body: message.body ?? '',
          sender: message.address ?? '',
          timestamp: message.date != null
              ? DateTime.fromMillisecondsSinceEpoch(message.date!)
              : DateTime.now(),
        );
      },
      onBackgroundMessage: backgroundSmsHandler,
      listenInBackground: true,
    );
  }

  void stop() {
    _isListening = false;
    // Telephony does not expose a stop method; setting flag prevents re-processing
  }

  Future<void> _handleSms({
    required String body,
    required String sender,
    required DateTime timestamp,
  }) async {
    final result =
        BankSmsParser.instance.parse(body: body, sender: sender);
    if (result == null) return;

    final userId = _ref.read(currentUserIdProvider);
    if (userId == null) return;

    final category = CategorizationService.instance.categorizeWithType(
      result.merchant,
      isCredit: !result.isDebit,
    );

    final tx = Transaction(
      id: const Uuid().v4(),
      userId: userId,
      amount: result.amount,
      type: result.isDebit ? TransactionType.debit : TransactionType.credit,
      category: category,
      merchant: result.merchant,
      date: result.date ?? timestamp,
      source: TransactionSource.sms,
      rawText: body,
      createdAt: DateTime.now(),
      bankReference: result.reference,
    );

    await _ref.read(transactionRepositoryProvider).add(tx);

    // Trigger local notification with quick category choice buttons
    if (category == 'Other' && tx.type == TransactionType.debit) {
      await NotificationService.instance.showCategorizationNotification(
        txId: tx.id,
        amount: tx.amount,
        merchant: tx.merchant,
      );
    }
  }
}

// ── Background handler (top-level, required by telephony package) ─────────────
@pragma('vm:entry-point')
Future<void> backgroundSmsHandler(SmsMessage message) async {
  try {
    WidgetsFlutterBinding.ensureInitialized();
    await Firebase.initializeApp();

    final body = message.body ?? '';
    final sender = message.address ?? '';

    final result = BankSmsParser.instance.parse(body: body, sender: sender);
    if (result == null) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final userId = user.uid;

    final category = CategorizationService.instance.categorizeWithType(
      result.merchant,
      isCredit: !result.isDebit,
    );

    final tx = Transaction(
      id: const Uuid().v4(),
      userId: userId,
      amount: result.amount,
      type: result.isDebit ? TransactionType.debit : TransactionType.credit,
      category: category,
      merchant: result.merchant,
      date: result.date ??
          (message.date != null
              ? DateTime.fromMillisecondsSinceEpoch(message.date!)
              : DateTime.now()),
      source: TransactionSource.sms,
      rawText: body,
      createdAt: DateTime.now(),
      bankReference: result.reference,
    );

    // Save directly to SQLite inside the background isolate
    final db = await DatabaseHelper.instance.database;
    await db.insert(
      'transactions',
      {
        'id': tx.id,
        'user_id': userId,
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
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    DatabaseHelper.instance.notifyChange('transactions');

    // Trigger local notification with quick category choice buttons
    if (category == 'Other' && tx.type == TransactionType.debit) {
      await NotificationService.instance.initialize();
      await NotificationService.instance.showCategorizationNotification(
        txId: tx.id,
        amount: tx.amount,
        merchant: tx.merchant,
      );
    }
  } catch (e) {
    debugPrint('YourCA Background SMS Parse Error: $e');
  }
}
