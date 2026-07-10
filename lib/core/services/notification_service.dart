import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse notificationResponse) async {
  try {
    WidgetsFlutterBinding.ensureInitialized();
    await Firebase.initializeApp();

    final txId = notificationResponse.payload;
    final actionId = notificationResponse.actionId;
    if (txId == null || actionId == null) return;

    String? category;
    if (actionId == 'action_food') category = 'Food & Dining';
    if (actionId == 'action_shopping') category = 'Shopping';
    if (actionId == 'action_transport') category = 'Transport';
    if (category == null) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Update transaction category directly in Firestore
    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('transactions')
        .doc(txId)
        .update({'category': category});

    debugPrint('YourCA Notification Callback: updated tx $txId to $category');
  } catch (e) {
    debugPrint('YourCA Background Notification Action Error: $e');
  }
}

class NotificationService {
  static final NotificationService instance = NotificationService._();
  NotificationService._();

  final FlutterLocalNotificationsPlugin _localNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  Future<void> initialize() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    // Define dummy settings if platform specific isn't required on non-android
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

    // Request notifications permission on Android 13+
    final androidPlugin = _localNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      await androidPlugin.requestNotificationsPermission();
    }
  }

  Future<void> showCategorizationNotification({
    required String txId,
    required double amount,
    required String merchant,
  }) async {
    final androidDetails = AndroidNotificationDetails(
      'categorization_channel',
      'Transaction Categorization',
      channelDescription: 'Prompts to categorize transactions from SMS',
      importance: Importance.max,
      priority: Priority.high,
      actions: [
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
          'action_transport',
          '\u{1F697} Transport',
          showsUserInterface: false,
          cancelNotification: true,
        ),
      ],
    );

    final notificationDetails = NotificationDetails(android: androidDetails);

    await _localNotificationsPlugin.show(
      txId.hashCode,
      'Categorize Payment of \u20B9${amount.toStringAsFixed(0)}',
      'Sent to "$merchant". What was this for?',
      notificationDetails,
      payload: txId,
    );
  }
}

const AndroidInitializationSettings androidParagraphInitializationSettings =
    AndroidInitializationSettings('@mipmap/ic_launcher');
