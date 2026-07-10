import 'dart:math';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart' show debugPrint;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

// ── Current UID shortcut ───────────────────────────────────────────────────
final currentUserIdProvider = Provider<String?>((ref) {
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
      final doc = await FirebaseFirestore.instance.collection('otps').doc(email).get();
      if (!doc.exists) {
        throw Exception('No OTP request found for this email. Send a new one.');
      }

      final data = doc.data()!;
      final code = data['code'] as String?;
      final expiresAtStr = data['expires_at'] as String?;

      if (code == null || code != otp) {
        throw Exception('Invalid verification code. Please try again.');
      }

      if (expiresAtStr != null) {
        final expiresAt = DateTime.parse(expiresAtStr);
        if (DateTime.now().isAfter(expiresAt)) {
          throw Exception('Verification code has expired. Request a new one.');
        }
      }

      // Log in anonymously (works instantly on Spark plan with no card!)
      final credential = await _auth.signInAnonymously();

      // Ensure user profile in Firestore
      final existingProfile = await _userRepo.fetchProfile(credential.user!.uid);
      if (existingProfile == null) {
        await _userRepo.createProfile(UserProfile(
          id: credential.user!.uid,
          name: email.split('@').first,
          phoneNumber: email, // Store email inside phoneNumber
          createdAt: DateTime.now(),
        ));
      }

      // Clean up verification document
      await FirebaseFirestore.instance.collection('otps').doc(email).delete();

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
    final existing = await _userRepo.fetchProfile(user.uid);
    if (existing == null) {
      await _userRepo.createProfile(UserProfile(
        id: user.uid,
        name: user.displayName ?? '',
        phoneNumber: user.phoneNumber ?? '',
        createdAt: DateTime.now(),
      ));
    }
  }

  Future<void> updateUserName(String name) async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) return;
    final profile = await _userRepo.fetchProfile(userId);
    if (profile == null) return;
    await _userRepo.updateProfile(profile.copyWith(name: name));
    await _auth.currentUser?.updateDisplayName(name);
  }

  Future<void> signOut() async {
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
