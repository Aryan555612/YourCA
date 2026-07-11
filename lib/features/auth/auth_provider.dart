import 'dart:math';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart' show debugPrint;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../shared/models/models.dart';
import '../../shared/repositories/user_repository.dart';

// ── Firebase Auth instance ─────────────────────────────────────────────────
final firebaseAuthProvider = Provider<FirebaseAuth>((ref) {
  return FirebaseAuth.instance;
});

// ── Auth state stream ──────────────────────────────────────────────────────
final authStateProvider = StreamProvider<User?>((ref) {
  return ref.watch(firebaseAuthProvider).authStateChanges();
});

// ── Stable User ID provider ────────────────────────────────────────────────
// This is the KEY fix: instead of using Firebase anonymous UID (which changes on
// each reinstall), we use a stable ID derived from the user's email and stored
// in Firestore. This guarantees the same email always maps to the same SQLite
// user_id, preserving all local data across reinstalls and re-logins.
const _stableUidPrefKey = 'stable_user_id';
const _stableEmailPrefKey = 'stable_user_email';

final stableUserIdProvider = StateProvider<String?>((ref) => null);

// ── Current UID shortcut ───────────────────────────────────────────────────
// Uses stableUserIdProvider first; falls back to Firebase UID only if stable
// ID hasn't been loaded yet (brief transition state).
final currentUserIdProvider = Provider<String?>((ref) {
  final stableId = ref.watch(stableUserIdProvider);
  if (stableId != null) return stableId;
  return ref.watch(authStateProvider).valueOrNull?.uid;
});

// ── Auth notifier ──────────────────────────────────────────────────────────
class AuthNotifier extends AsyncNotifier<void> {
  late FirebaseAuth _auth;
  late UserRepository _userRepo;

  @override
  Future<void> build() async {
    _auth = ref.watch(firebaseAuthProvider);
    _userRepo = ref.watch(userRepositoryProvider);
    // Restore stable ID from prefs on app start
    await _restoreStableId();
  }

  // ── Restore stable user ID from local prefs ────────────────────────────
  Future<void> _restoreStableId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedId = prefs.getString(_stableUidPrefKey);
      if (savedId != null) {
        ref.read(stableUserIdProvider.notifier).state = savedId;
      }
    } catch (_) {}
  }

  // ── Generate deterministic stable UID from email ───────────────────────
  // Uses SHA-256 of the email to create a consistent, collision-resistant ID
  // that is the same every time the user logs in with the same email.
  String _generateStableId(String email) {
    final bytes = utf8.encode(email.toLowerCase().trim());
    final digest = sha256.convert(bytes);
    // Take first 32 hex chars for a shorter but still unique ID
    return digest.toString().substring(0, 32);
  }

  // ── Get or create stable UID in Firestore ──────────────────────────────
  Future<String> _getOrCreateStableUid(String email) async {
    final docRef = FirebaseFirestore.instance
        .collection('user_stable_ids')
        .doc(email.toLowerCase().trim());

    try {
      final doc = await docRef.get();
      if (doc.exists && doc.data()?['stable_uid'] != null) {
        return doc.data()!['stable_uid'] as String;
      }
    } catch (_) {}

    // Not in Firestore yet — generate and store
    final stableUid = _generateStableId(email);
    try {
      await docRef.set({
        'stable_uid': stableUid,
        'email': email.toLowerCase().trim(),
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (_) {
      // Firestore write failed (offline?) — still use the generated ID locally
    }
    return stableUid;
  }

  // ── Custom Email OTP Authentication flow ──────────────────────────────────
  Future<void> sendEmailOtp({
    required String email,
  }) async {
    state = const AsyncLoading();
    try {
      // 1. Generate a random 6-digit verification code
      final code = (100000 + Random().nextInt(900000)).toString();

      // 2. Save it to Firestore under the 'otps' collection
      await FirebaseFirestore.instance.collection('otps').doc(email).set({
        'code': code,
        'expires_at': DateTime.now().add(const Duration(minutes: 10)).toIso8601String(),
      });

      // 3. Print code to terminal debug logs so the developer can copy it immediately
      debugPrint('✉️ [EMAIL OTP] Verification code for $email is: $code');

      // 4. Try to send it via real email using Brevo SMTP API (if configured in Firestore)
      final configDoc = await FirebaseFirestore.instance.collection('config').doc('brevo').get();
      final brevoApiKey = configDoc.exists ? (configDoc.data()?['apiKey'] as String? ?? '') : '';
      
      if (brevoApiKey.isNotEmpty) {
        final url = Uri.parse('https://api.brevo.com/v3/smtp/email');
        final response = await http.post(
          url,
          headers: {
            'api-key': brevoApiKey,
            'content-type': 'application/json',
          },
          body: jsonEncode({
            'sender': {'name': 'YourCA Verification', 'email': 'aryanpatel9051@gmail.com'},
            'to': [{'email': email}],
            'subject': 'YourCA OTP Verification Code',
            'htmlContent': '''
              <div style="font-family: sans-serif; padding: 24px; background-color: #000; color: #fff; border-radius: 16px; max-width: 480px;">
                <h2 style="color: #4D80FF; margin-bottom: 8px;">YourCA</h2>
                <p style="color: #8C8C8C; font-size: 16px;">Use the following verification code to sign in to your finance tracking account:</p>
                <div style="background-color: #1A1A1A; padding: 16px; border-radius: 12px; text-align: center; margin: 24px 0;">
                  <span style="font-size: 32px; font-weight: bold; letter-spacing: 6px; color: #fff;">$code</span>
                </div>
                <p style="color: #595959; font-size: 12px; margin-top: 24px;">This code will expire in 10 minutes. If you did not request this code, you can safely ignore this email.</p>
              </div>
            ''',
          }),
        );
        if (response.statusCode >= 400) {
          debugPrint('Brevo send error: ${response.body}');
        }
      }

      state = const AsyncData(null);
    } catch (e, st) {
      state = AsyncError(e, st);
      rethrow;
    }
  }

  Future<void> verifyEmailOtp({
    required String email,
    required String otp,
  }) async {
    state = const AsyncLoading();
    try {
      // 1. Attempt to write to the verification subcollection.
      // Firestore Security Rules will reject this write (permission-denied)
      // if the code is wrong OR if the OTP has expired.
      try {
        await FirebaseFirestore.instance
            .collection('otps')
            .doc(email)
            .collection('attempts')
            .doc('verify')
            .set({
          'enteredCode': otp,
          'timestamp': FieldValue.serverTimestamp(),
        });
      } catch (e) {
        // If write fails, the code is incorrect or has expired
        throw Exception('Invalid or expired verification code. Please try again.');
      }

      // If we reach here, the write succeeded, meaning the code was correct!
      // 2. Log in anonymously (works instantly on Spark plan with no card!)
      final credential = await _auth.signInAnonymously();

      // 3. Get or create the STABLE user ID for this email (KEY FIX)
      // This ensures the same email always maps to the same SQLite user_id,
      // even across reinstalls, re-logins, or different devices.
      final stableUid = await _getOrCreateStableUid(email);

      // 4. Save stable UID to SharedPreferences for offline use
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_stableUidPrefKey, stableUid);
      await prefs.setString(_stableEmailPrefKey, email.toLowerCase().trim());

      // 5. Update the in-memory state provider
      ref.read(stableUserIdProvider.notifier).state = stableUid;

      // 6. Ensure user profile in SQLite (using stable UID, NOT Firebase UID)
      final existingProfile = await _userRepo.fetchProfile(stableUid);
      if (existingProfile == null) {
        await _userRepo.createProfile(UserProfile(
          id: stableUid,
          name: email.split('@').first,
          phoneNumber: email,
          createdAt: DateTime.now(),
        ));
      }

      // 7. Also store a mapping in Firestore linking Firebase UID → stable UID
      // (useful for future cloud sync features)
      try {
        await FirebaseFirestore.instance
            .collection('firebase_uid_map')
            .doc(credential.user!.uid)
            .set({
          'stable_uid': stableUid,
          'email': email.toLowerCase().trim(),
          'updated_at': DateTime.now().toIso8601String(),
        });
      } catch (_) {}

      // 8. Clean up both the verification attempt and the parent OTP document
      try {
        await FirebaseFirestore.instance
            .collection('otps')
            .doc(email)
            .collection('attempts')
            .doc('verify')
            .delete();
        await FirebaseFirestore.instance.collection('otps').doc(email).delete();
      } catch (e) {
        // Safe to ignore cleanup failures
      }

      state = const AsyncData(null);
    } catch (e, st) {
      state = AsyncError(e, st);
      rethrow;
    }
  }

  // ── Ensure user profile exists in Firestore ────────────────────────────
  // ignore: unused_element
  Future<void> _ensureUserProfile() async {
    final user = _auth.currentUser;
    if (user == null) return;
    final stableUid = ref.read(stableUserIdProvider) ?? user.uid;
    final existing = await _userRepo.fetchProfile(stableUid);
    if (existing == null) {
      await _userRepo.createProfile(UserProfile(
        id: stableUid,
        name: user.displayName ?? '',
        phoneNumber: user.phoneNumber ?? '',
        createdAt: DateTime.now(),
      ));
    }
  }

  Future<void> updateUserName(String name) async {
    final stableUid = ref.read(stableUserIdProvider);
    final userId = stableUid ?? _auth.currentUser?.uid;
    if (userId == null) return;
    final profile = await _userRepo.fetchProfile(userId);
    if (profile == null) return;
    await _userRepo.updateProfile(profile.copyWith(name: name));
    await _auth.currentUser?.updateDisplayName(name);
  }

  Future<void> signOut() async {
    // Clear stable ID from memory (not from prefs — preserve for re-login)
    ref.read(stableUserIdProvider.notifier).state = null;
    await _auth.signOut();
  }
}

final authNotifierProvider =
    AsyncNotifierProvider<AuthNotifier, void>(() => AuthNotifier());

// ── User profile provider ──────────────────────────────────────────────────
final userProfileProvider = StreamProvider<UserProfile?>((ref) {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return Stream.value(null);
  return ref.watch(userRepositoryProvider).watchProfile(userId);
});


