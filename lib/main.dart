import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app.dart';
import 'firebase_options.dart';
import 'core/services/notification_service.dart';
import 'features/auth/auth_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    // Default app already exists (common during web hot restarts) - ignore
  }

  // Initialize notifications
  await NotificationService.instance.initialize();

  // Initialize SharedPreferences
  final prefs = await SharedPreferences.getInstance();

  // To test with Firebase Emulators locally, uncomment and configure:
  // const host = '10.0.2.2'; // Android emulator → localhost
  // FirebaseFirestore.instance.useFirestoreEmulator(host, 8080);
  // await FirebaseAuth.instance.useAuthEmulator(host, 9099);

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: const YourCAApp(),
    ),
  );
}
