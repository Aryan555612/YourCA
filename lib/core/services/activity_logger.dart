import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Centralized activity logger that records user actions to Firestore.
///
/// Usage:
///   ActivityLogger.instance.log(
///     event: 'transaction_added',
///     screen: 'add_transaction',
///     details: {'amount': 250.0, 'merchant': 'Swiggy'},
///   );
///
/// All writes are fire-and-forget so they never block the UI.
/// Failures are silently swallowed — never crash the app for analytics.
class ActivityLogger {
  ActivityLogger._();
  static final ActivityLogger instance = ActivityLogger._();

  static const _stableUidPrefKey = 'stable_user_id';

  String get _platform {
    try {
      if (Platform.isAndroid) return 'android';
      if (Platform.isIOS) return 'ios';
    } catch (_) {}
    return 'web';
  }

  /// Logs a user activity event to Firestore.
  ///
  /// [event]   - Event name e.g. 'transaction_added', 'screen_view'
  /// [screen]  - Screen where the event occurred e.g. 'dashboard'
  /// [details] - Optional map with event-specific data
  void log({
    required String event,
    String? screen,
    Map<String, dynamic>? details,
  }) {
    // Fire-and-forget: intentionally not awaited
    _writeToFirestore(event: event, screen: screen, details: details);
  }

  Future<void> _writeToFirestore({
    required String event,
    String? screen,
    Map<String, dynamic>? details,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString(_stableUidPrefKey);
      if (userId == null) return; // Not logged in — skip

      final docId = const Uuid().v4();
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('activityLog')
          .doc(docId)
          .set({
        'event': event,
        if (screen != null) 'screen': screen,
        if (details != null) 'details': details,
        'timestamp': DateTime.now().toIso8601String(),
        'platform': _platform,
      });
    } catch (_) {
      // Silently fail — never block the user for analytics issues
    }
  }
}
