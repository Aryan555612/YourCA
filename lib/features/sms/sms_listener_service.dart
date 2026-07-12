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
import 'package:shared_preferences/shared_preferences.dart';
import '../../firebase_options.dart';
import 'package:cloud_firestore/cloud_firestore.dart' hide Transaction;
import 'package:permission_handler/permission_handler.dart';
import '../../features/dashboard/dashboard_screen.dart';
import '../../features/transactions/transaction_list_screen.dart';

/// Provider that starts the background SMS listener on Android.
/// No-op on iOS and Web.
final pendingCategorizationProvider = StateProvider<Transaction?>((ref) => null);
final pendingConfirmTxIdsProvider = StateProvider<Set<String>>((ref) => {});

final smsListenerProvider = Provider<SmsListenerService>((ref) {
  return SmsListenerService(ref);
});

class SmsListenerService {
  final Ref _ref;
  final Telephony _telephony = Telephony.instance;
  bool _isListening = false;

  SmsListenerService(this._ref);

  static String autoSelectCategory(String merchant, TransactionType type) {
    final lower = merchant.toLowerCase().trim();
    final companyKeywords = [
      'flipkart', 'amazon', 'myntra', 'ajio', 'meesho', 'nykaa',
      'bigbasket', 'grofers', 'blinkit', 'instamart', 'zepto',
      'dmart', 'reliance', 'tata', 'jiomart', 'swiggy', 'zomato',
      'dominos', 'pizza', 'mcdonalds', 'kfc', 'starbucks', 'uber',
      'ola', 'rapido', 'redbus', 'irctc', 'netflix', 'spotify',
      'jio', 'airtel', 'bsnl', 'vi', 'vodafone', 'electricity',
      'paytm', 'phonepe', 'gpay', 'razorpay', 'billdesk', 'retail',
      'limited', 'ltd', 'private', 'pvt', 'corp', 'co', 'store',
      'supermarket', 'mart', 'hotel', 'restaurant', 'cafe', 'bazaar',
      'services', 'solutions', 'technologies', 'infotech', 'agency',
      'enterprise', 'enterprises', 'wholesale', 'distributor', 'distribution',
      'e-kart', 'ekart', 'pay', 'shop', 'online'
    ];
    for (final kw in companyKeywords) {
      if (lower.contains(kw)) {
        return 'Shopping';
      }
    }
    if (type == TransactionType.credit) {
      final words = merchant.trim().split(RegExp(r'\s+'));
      if (words.length >= 2) {
        return 'Person';
      }
      return 'Income';
    }
    return 'Person';
  }

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

    // Sync inbox SMS to catch up on any missing transactions
    syncInboxSms();
  }

  void stop() {
    _isListening = false;
    // Telephony does not expose a stop method; setting flag prevents re-processing
  }

  /// Queries the SMS inbox for the last 30 days, parses bank alerts,
  /// and imports missing transactions.
  Future<void> syncInboxSms() async {
    try {
      if (!Platform.isAndroid) return;
      final userId = _ref.read(currentUserIdProvider);
      if (userId == null) return;

      // Check permission first (don't request aggressively if denied)
      final status = await Permission.sms.status;
      if (!status.isGranted) return;

      final now = DateTime.now();
      final repo = _ref.read(transactionRepositoryProvider);

      // Determine dynamic start date: look up the last transaction date from SQLite database.
      // This handles offline gaps of any duration (even multiple months).
      DateTime startDate;
      final db = await DatabaseHelper.instance.database;
      final lastTxRow = await db.query(
        'transactions',
        where: 'user_id = ?',
        whereArgs: [userId],
        orderBy: 'date DESC',
        limit: 1,
      );

      final cutoffDate = DateTime(2026, 7, 12);
      if (lastTxRow.isNotEmpty) {
        final lastTxDateStr = lastTxRow.first['date'] as String;
        final lastTxDate = DateTime.parse(lastTxDateStr);
        // Overlap by 2 days to account for potential timestamp mismatches/delays
        startDate = lastTxDate.subtract(const Duration(days: 2));
      } else {
        // Fresh install/login: only scan from 00:00:00 of the current date (today) onwards
        startDate = DateTime(now.year, now.month, now.day);
      }
      if (startDate.isBefore(cutoffDate)) {
        startDate = cutoffDate;
      }

      final existingTxs = await repo.fetchDateRange(userId, startDate, now);

      final existingRefs = existingTxs
          .map((tx) => tx.bankReference)
          .where((ref) => ref != null)
          .cast<String>()
          .toSet();

      final existingRawTexts = existingTxs
          .map((tx) => tx.rawText)
          .where((text) => text != null)
          .cast<String>()
          .toSet();

      final existingKeys = existingTxs.map((tx) {
        final localDate = tx.date.toLocal();
        final dateKey = "${localDate.year}-${localDate.month}-${localDate.day}";
        return "${tx.amount}_${dateKey}_${tx.merchant.toLowerCase().trim()}";
      }).toSet();

      // Fetch SMS messages from the dynamic start date
      final messages = await _telephony.getInboxSms(
        columns: [SmsColumn.ADDRESS, SmsColumn.BODY, SmsColumn.DATE],
        filter: SmsFilter.where(SmsColumn.DATE)
            .greaterThan(startDate.millisecondsSinceEpoch.toString()),
        sortOrder: [OrderBy(SmsColumn.DATE, sort: Sort.ASC)], // Oldest first
      );

      bool newTransactionsFound = false;

      for (final message in messages) {
        final body = message.body ?? '';
        final sender = message.address ?? '';
        final timestamp = message.date != null
            ? DateTime.fromMillisecondsSinceEpoch(message.date!)
            : DateTime.now();

        final result = BankSmsParser.instance.parse(body: body, sender: sender);
        if (result == null) continue;

        // 1. Check raw text duplicate (ultimate unique SMS fingerprint check)
        if (existingRawTexts.contains(body)) {
          continue;
        }

        // 2. Check reference duplicate
        if (result.reference != null && existingRefs.contains(result.reference)) {
          continue;
        }

        // 3. Check unique key duplicate using timezone-robust local date format
        final txDate = result.date != null
            ? DateTime(result.date!.year, result.date!.month, result.date!.day,
                timestamp.hour, timestamp.minute, timestamp.second)
            : timestamp;
        final localTxDate = txDate.toLocal();
        final dateKey = "${localTxDate.year}-${localTxDate.month}-${localTxDate.day}";
        final key = "${result.amount}_${dateKey}_${result.merchant.toLowerCase().trim()}";
        if (existingKeys.contains(key)) {
          continue;
        }

        // Create new transaction
        final category = SmsListenerService.autoSelectCategory(
          result.merchant,
          result.isDebit ? TransactionType.debit : TransactionType.credit,
        );

        final tx = Transaction(
          id: const Uuid().v4(),
          userId: userId,
          amount: result.amount,
          type: result.isDebit ? TransactionType.debit : TransactionType.credit,
          category: category,
          merchant: result.merchant,
          date: txDate,
          source: TransactionSource.sms,
          rawText: body,
          createdAt: DateTime.now(),
          bankReference: result.reference,
        );

        // Add locally and sync to Firestore
        await repo.add(tx);

        if (result.reference != null) {
          existingRefs.add(result.reference!);
        }
        existingRawTexts.add(body);
        existingKeys.add(key);
        newTransactionsFound = true;
      }

      if (newTransactionsFound) {
        _ref.invalidate(monthlySummaryProvider);
        _ref.invalidate(trendDataProvider);
        _ref.invalidate(transactionsStreamProvider);
      }
    } catch (e) {
      debugPrint('YourCA SMS Inbox Sync Error: $e');
    }
  }

  Future<void> _handleSms({
    required String body,
    required String sender,
    required DateTime timestamp,
  }) async {
    final result =
        BankSmsParser.instance.parse(body: body, sender: sender);
    if (result == null) return;

    // Prevent duplicate insertion
    final db = await DatabaseHelper.instance.database;
    final duplicates = await db.query(
      'transactions',
      where: 'raw_text = ?' + (result.reference != null ? ' OR bank_reference = ?' : ''),
      whereArgs: [body, if (result.reference != null) result.reference!],
    );
    if (duplicates.isNotEmpty) return;

    final userId = _ref.read(currentUserIdProvider);
    if (userId == null) return;

    final category = CategorizationService.instance.categorizeWithType(
      result.merchant,
      isCredit: !result.isDebit,
    );

    final txDate = result.date != null
        ? DateTime(result.date!.year, result.date!.month, result.date!.day,
            timestamp.hour, timestamp.minute, timestamp.second)
        : timestamp;

    final tx = Transaction(
      id: const Uuid().v4(),
      userId: userId,
      amount: result.amount,
      type: result.isDebit ? TransactionType.debit : TransactionType.credit,
      category: category,
      merchant: result.merchant,
      date: txDate,
      source: TransactionSource.sms,
      rawText: body,
      createdAt: DateTime.now(),
      bankReference: result.reference,
    );

    final autoCat = SmsListenerService.autoSelectCategory(tx.merchant, tx.type);
    final txWithAuto = tx.copyWith(category: autoCat);

    await _ref.read(transactionRepositoryProvider).add(txWithAuto);
    _ref.read(pendingConfirmTxIdsProvider.notifier).update((state) => {...state, tx.id});

    _ref.read(pendingCategorizationProvider.notifier).state = txWithAuto;

    if (tx.type == TransactionType.debit) {
      await NotificationService.instance.showCategorizationNotification(
        txId: tx.id,
        amount: tx.amount,
        merchant: tx.merchant,
      );
    } else {
      await NotificationService.instance.showTransactionNotification(
        amount: tx.amount,
        merchant: tx.merchant,
        isDebit: false,
      );
    }
  }
}

// ── Background handler (top-level, required by telephony package) ─────────────
@pragma('vm:entry-point')
Future<void> backgroundSmsHandler(SmsMessage message) async {
  try {
    WidgetsFlutterBinding.ensureInitialized();
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    } catch (_) {
      // Duplicate app or options missing
    }

    final body = message.body ?? '';
    final sender = message.address ?? '';

    final result = BankSmsParser.instance.parse(body: body, sender: sender);
    if (result == null) return;

    // Prevent duplicate insertion in background isolate
    final db = await DatabaseHelper.instance.database;
    final duplicates = await db.query(
      'transactions',
      where: 'raw_text = ?' + (result.reference != null ? ' OR bank_reference = ?' : ''),
      whereArgs: [body, if (result.reference != null) result.reference!],
    );
    if (duplicates.isNotEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('stable_user_id') ?? FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;

    final category = SmsListenerService.autoSelectCategory(
      result.merchant,
      result.isDebit ? TransactionType.debit : TransactionType.credit,
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

    // Also sync to cloud Firestore if possible
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('transactions')
          .doc(tx.id)
          .set(tx.toFirestore());
    } catch (_) {}

    // Trigger local notification
    await NotificationService.instance.initialize(requestPermission: false);
    if (tx.type == TransactionType.debit) {
      await NotificationService.instance.showCategorizationNotification(
        txId: tx.id,
        amount: tx.amount,
        merchant: tx.merchant,
      );
    } else {
      await NotificationService.instance.showTransactionNotification(
        amount: tx.amount,
        merchant: tx.merchant,
        isDebit: false,
      );
    }
  } catch (e) {
    debugPrint('YourCA Background SMS Parse Error: $e');
  }
}
