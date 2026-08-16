import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'database_helper.dart';

@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse notificationResponse) async {
  try {
    WidgetsFlutterBinding.ensureInitialized();
    await Firebase.initializeApp();

    final txId = notificationResponse.payload;
    final actionId = notificationResponse.actionId;
    if (txId == null) return;

    final user = FirebaseAuth.instance.currentUser;
    final db = await DatabaseHelper.instance.database;

    // Handle Note input from notification action
    if (actionId == 'action_add_note' || actionId == 'action_input_note') {
      final inputNote = notificationResponse.input?.trim();
      if (inputNote != null && inputNote.isNotEmpty) {
        await db.update(
          'transactions',
          {'note': inputNote},
          where: 'id = ?',
          whereArgs: [txId],
        );
        DatabaseHelper.instance.notifyChange('transactions');
        debugPrint('YourCA Notification Callback: updated tx $txId with note "$inputNote"');
        return;
      }
    }

    // Handle Category actions
    String? category;
    if (actionId == 'action_food') category = 'Food & Dining';
    if (actionId == 'action_shopping') category = 'Shopping';
    if (actionId == 'action_transport') category = 'Transport';
    if (actionId == 'action_income') category = 'Income';
    if (actionId == 'action_person') category = 'Person';

    if (category != null) {
      await db.update(
        'transactions',
        {'category': category},
        where: 'id = ?',
        whereArgs: [txId],
      );
      DatabaseHelper.instance.notifyChange('transactions');
      debugPrint('YourCA Notification Callback: updated tx $txId to category "$category"');
    }
  } catch (e) {
    debugPrint('YourCA Background Notification Action Error: $e');
  }
}

class NotificationService {
  static final NotificationService instance = NotificationService._();
  NotificationService._();

  final FlutterLocalNotificationsPlugin _localNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static const String channelId = 'yourca_transaction_channel_v4';
  static const String channelName = 'Transaction Alerts & Notes';

  Future<void> initialize({bool requestPermission = true}) async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initializationSettingsUnified = InitializationSettings(
      android: initializationSettingsAndroid,
    );

    await _localNotificationsPlugin.initialize(
      initializationSettingsUnified,
      onDidReceiveNotificationResponse: (details) {
        // Foreground tap
      },
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );

    try {
      final androidPlugin = _localNotificationsPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      if (androidPlugin != null) {
        // Create high importance Android notification channel
        const AndroidNotificationChannel channel = AndroidNotificationChannel(
          channelId,
          channelName,
          description: 'Notifications for incoming/outgoing payments with note & category options',
          importance: Importance.max,
          playSound: true,
          enableVibration: true,
          enableLights: true,
          showBadge: true,
        );
        await androidPlugin.createNotificationChannel(channel);

        if (requestPermission) {
          await androidPlugin.requestNotificationsPermission();
        }
      }
    } catch (e) {
      debugPrint('YourCA Notification Initialization Error: $e');
    }
  }

  Future<void> showTransactionNotification({
    required String txId,
    required double amount,
    required String merchant,
    required bool isDebit,
    String? currentCategory,
  }) async {
    final title = isDebit
        ? '🔴 Payment Sent: \u20B9${amount.toStringAsFixed(2)}'
        : '🟢 Payment Received: \u20B9${amount.toStringAsFixed(2)}';

    final body = isDebit
        ? 'Paid to "$merchant". Add a note or tap category below.'
        : 'Received from "$merchant". Add a note or tap category below.';

    final List<AndroidNotificationAction> actions = isDebit
        ? [
            const AndroidNotificationAction(
              'action_food',
              '\u{1F354} Food',
              showsUserInterface: false,
              cancelNotification: true,
            ),
            const AndroidNotificationAction(
              'action_shopping',
              '\u{1F6CD} Shopping',
              showsUserInterface: false,
              cancelNotification: true,
            ),
            const AndroidNotificationAction(
              'action_add_note',
              '\u{1F4DD} Add Note',
              inputs: [
                AndroidNotificationActionInput(
                  label: 'Type note for this payment...',
                )
              ],
              showsUserInterface: false,
              cancelNotification: true,
            ),
          ]
        : [
            const AndroidNotificationAction(
              'action_income',
              '\u{1F4B8} Income',
              showsUserInterface: false,
              cancelNotification: true,
            ),
            const AndroidNotificationAction(
              'action_person',
              '\u{1F464} Person',
              showsUserInterface: false,
              cancelNotification: true,
            ),
            const AndroidNotificationAction(
              'action_add_note',
              '\u{1F4DD} Add Note',
              inputs: [
                AndroidNotificationActionInput(
                  label: 'Type note for this payment...',
                )
              ],
              showsUserInterface: false,
              cancelNotification: true,
            ),
          ];

    final androidDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: 'Notifications for incoming/outgoing payments with note & category options',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      enableLights: true,
      actions: actions,
    );

    final notificationDetails = NotificationDetails(android: androidDetails);

    await _localNotificationsPlugin.show(
      txId.hashCode,
      title,
      body,
      notificationDetails,
      payload: txId,
    );
  }

  // Alias for backward compatibility
  Future<void> showCategorizationNotification({
    required String txId,
    required double amount,
    required String merchant,
  }) async {
    await showTransactionNotification(
      txId: txId,
      amount: amount,
      merchant: merchant,
      isDebit: true,
    );
  }
}

