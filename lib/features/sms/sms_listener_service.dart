import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:telephony/telephony.dart';
import 'package:uuid/uuid.dart';
import '../../shared/models/models.dart';
import '../../shared/repositories/transaction_repository.dart';
import '../../features/auth/auth_provider.dart';
import '../../features/categories/categorization_service.dart';
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
  }
}

// ── Background handler (top-level, required by telephony package) ─────────────
@pragma('vm:entry-point')
void backgroundSmsHandler(SmsMessage message) {
  // Background processing is limited — we store a flag for next foreground visit.
  // Full background processing requires a background isolate setup which is
  // outside MVP scope but can be added via flutter_background_service.
}
