import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    // Default app already exists (common during web hot restarts) - ignore
  }

  // Set to true to test locally using Firebase Emulators (no real SMS sent).
  // Set to false to connect to your real Firebase project and send real SMS texts.
  const bool useFirebaseEmulators = false;

  if (useFirebaseEmulators && kDebugMode) {
    try {
      final host = kIsWeb ? 'localhost' : '10.0.2.2';
      FirebaseFirestore.instance.useFirestoreEmulator(host, 8080);
      await FirebaseAuth.instance.useAuthEmulator(host, 9099);
      debugPrint('Connected to Firebase Emulators on $host');
    } catch (e) {
      debugPrint('Firebase Emulator connection error: $e');
    }
  }

  runApp(const ProviderScope(child: YourCAApp()));
}
