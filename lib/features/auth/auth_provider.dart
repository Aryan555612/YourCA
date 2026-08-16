import 'dart:math';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart' hide Transaction;
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart' show debugPrint;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../shared/models/models.dart';
import '../../shared/repositories/user_repository.dart';
import '../../shared/repositories/transaction_repository.dart';
import '../../core/services/activity_logger.dart';
import '../sms/sms_listener_service.dart';

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

final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('sharedPreferencesProvider must be overridden in ProviderScope');
});

final stableUserIdProvider = StateProvider<String?>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return prefs.getString(_stableUidPrefKey);
});

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
      final cleanEmail = email.toLowerCase().trim();

      // 1. Generate a random 6-digit verification code
      final code = (100000 + Random().nextInt(900000)).toString();

      // 2. Save OTP locally to SharedPreferences so verification NEVER fails even offline or if cloud rules block write
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('pending_otp_code', code);
      await prefs.setString('pending_otp_email', cleanEmail);
      await prefs.setInt('pending_otp_expiry', DateTime.now().add(const Duration(minutes: 10)).millisecondsSinceEpoch);

      // 3. Also attempt to save to Firestore under 'otps' collection (optional cloud backup)
      try {
        final docId = '${cleanEmail}_$code';
        await FirebaseFirestore.instance.collection('otps').doc(docId).set({
          'expires_at': DateTime.now().add(const Duration(minutes: 10)).toIso8601String(),
          'email': cleanEmail,
          'created_at': DateTime.now().toIso8601String(),
        });
      } catch (e) {
        debugPrint('Note: Could not save OTP to cloud Firestore (using local OTP verification): $e');
      }

      // 4. Print code to terminal debug logs so developer/tester can copy it immediately
      debugPrint('✉️ [EMAIL OTP] Verification code for $cleanEmail is: $code');

      // 5. Multi-channel Email Dispatch
      // Channel A: Firebase Auth Native Verification Email (dispatched directly from Google servers)
      try {
        try {
          await _auth.createUserWithEmailAndPassword(
            email: cleanEmail,
            password: 'YourCA_Pass_${cleanEmail.hashCode}',
          );
        } catch (_) {
          // Account already exists in Firebase Auth, proceed to send email
        }
        await _auth.sendPasswordResetEmail(email: cleanEmail);
        debugPrint('✉️ [FIREBASE EMAIL] Sent native authentication email to: $cleanEmail');
      } catch (e) {
        debugPrint('Note: Firebase Auth native email notice: $e');
      }

      // Channel B: Brevo / Webhook Transactional OTP Email API
      try {
        String brevoApiKey = '';
        try {
          final configDoc = await FirebaseFirestore.instance.collection('config').doc('brevo').get();
          if (configDoc.exists && configDoc.data() != null) {
            brevoApiKey = configDoc.data()?['apiKey'] as String? ?? '';
          }
        } catch (_) {}

        if (brevoApiKey.isNotEmpty) {
          final url = Uri.parse('https://api.brevo.com/v3/smtp/email');
          final response = await http.post(
            url,
            headers: {
              'api-key': brevoApiKey,
              'content-type': 'application/json',
            },
            body: jsonEncode({
              'sender': {'name': 'YourCA Verification', 'email': 'no-reply@yourca.com'},
              'to': [{'email': cleanEmail}],
              'subject': 'YourCA OTP Verification Code: $code',
              'htmlContent': '''
                <div style="font-family: Arial, sans-serif; padding: 24px; background-color: #0d0e15; color: #ffffff; border-radius: 16px; max-width: 480px; margin: auto;">
                  <h2 style="color: #6C5CE7; text-align: center; margin-top: 0;">YourCA Finance</h2>
                  <p style="color: #a0a0b0; font-size: 16px; text-align: center;">Use the following 6-digit code to complete your login:</p>
                  <div style="background-color: #161824; padding: 20px; border-radius: 12px; text-align: center; margin: 24px 0; border: 1px solid #2d2f45;">
                    <span style="font-size: 36px; font-weight: bold; letter-spacing: 8px; color: #6C5CE7;">$code</span>
                  </div>
                  <p style="color: #707080; font-size: 13px; text-align: center;">This code will expire in 10 minutes. If you did not request this code, please ignore this email.</p>
                </div>
              ''',
            }),
          );
          debugPrint('Brevo email dispatch HTTP status: ${response.statusCode}');
        }
      } catch (e) {
        debugPrint('Note: Transactional API dispatch notice: $e');
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
      final cleanEmail = email.toLowerCase().trim();
      final cleanOtp = otp.trim();
      final prefs = await SharedPreferences.getInstance();

      // 1. Check local SharedPreferences OTP cache first
      final localCode = prefs.getString('pending_otp_code');
      final localEmail = prefs.getString('pending_otp_email');
      final localExpiry = prefs.getInt('pending_otp_expiry') ?? 0;

      bool isVerifiedLocally = false;
      if (localEmail == cleanEmail && localCode == cleanOtp) {
        if (DateTime.now().millisecondsSinceEpoch <= localExpiry) {
          isVerifiedLocally = true;
        } else {
          throw Exception('Verification code has expired. Please request a new code.');
        }
      }

      // 2. If not verified locally, check Firestore 'otps' document
      if (!isVerifiedLocally) {
        final docId = '${cleanEmail}_$cleanOtp';
        try {
          final doc = await FirebaseFirestore.instance
              .collection('otps')
              .doc(docId)
              .get();

          if (!doc.exists || doc.data() == null) {
            throw Exception('Invalid verification code. Please try again.');
          }

          final data = doc.data()!;
          final expiresAtStr = data['expires_at'] as String? ?? '';
          if (expiresAtStr.isEmpty || DateTime.now().isAfter(DateTime.parse(expiresAtStr))) {
            throw Exception('Verification code has expired. Please try again.');
          }
        } catch (e) {
          if (e.toString().contains('expired') || e.toString().contains('Invalid')) {
            rethrow;
          }
          // Fallback if cloud read failed but code wasn't matched locally
          throw Exception('Invalid verification code. Please check the code and try again.');
        }
      }

      // 3. Clear local pending OTP
      await prefs.remove('pending_otp_code');
      await prefs.remove('pending_otp_email');
      await prefs.remove('pending_otp_expiry');

      // 4. Log in anonymously if not logged in
      UserCredential? credential;
      try {
        if (_auth.currentUser == null) {
          credential = await _auth.signInAnonymously();
        }
      } catch (e) {
        debugPrint('Note: Firebase Anonymous sign-in skipped or error: $e');
      }

      // 5. Get or create the STABLE user ID for this email
      final stableUid = await _getOrCreateStableUid(cleanEmail);

      // 6. Save stable UID to SharedPreferences for offline use
      await prefs.setString(_stableUidPrefKey, stableUid);
      await prefs.setString(_stableEmailPrefKey, cleanEmail);

      // 7. Update the in-memory state provider
      ref.read(stableUserIdProvider.notifier).state = stableUid;

      // 7.5. Re-claim all local SQLite transactions for this stable user ID
      try {
        await ref.read(transactionRepositoryProvider).migrateUserTransactions(stableUid);
      } catch (e) {
        debugPrint('Error migrating local transactions to stableUid: $e');
      }

      // 7.6. Trigger fresh SMS parse for historical SMS transactions
      try {
        await ref.read(smsListenerProvider).syncInboxSms();
      } catch (e) {
        debugPrint('Error syncing inbox SMS: $e');
      }

      // 8. Restore profile and transactions from Firestore if available
      UserProfile? cloudProfile;
      try {
        final profileDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(stableUid)
            .get();
        if (profileDoc.exists && profileDoc.data() != null) {
          cloudProfile = UserProfile.fromFirestore(profileDoc.data()!, stableUid);
        }
      } catch (e) {
        debugPrint('Error fetching user profile from Firestore: $e');
      }

      if (cloudProfile != null) {
        await _userRepo.createProfile(cloudProfile, syncToCloud: false);
      } else {
        final existingProfile = await _userRepo.fetchProfile(stableUid);
        if (existingProfile == null) {
          await _userRepo.createProfile(
            UserProfile(
              id: stableUid,
              name: cleanEmail.split('@').first,
              phoneNumber: cleanEmail,
              createdAt: DateTime.now(),
            ),
            syncToCloud: true,
          );
        }
      }

      // Restore ALL transactions from Firestore without any date filter
      try {
        final txsSnap = await FirebaseFirestore.instance
            .collection('users')
            .doc(stableUid)
            .collection('transactions')
            .get();
        if (txsSnap.docs.isNotEmpty) {
          final List<Transaction> transactions = [];
          for (final doc in txsSnap.docs) {
            final tx = Transaction.fromFirestore(doc.data(), doc.id);
            transactions.add(tx);
          }
          
          if (transactions.isNotEmpty) {
            await ref.read(transactionRepositoryProvider).addBatch(
                  transactions,
                  syncToCloud: false,
                );
          }
        }
      } catch (e) {
        debugPrint('Error restoring transactions from Firestore: $e');
      }

      // 9. Store mapping in Firestore linking Firebase UID → stable UID
      final fbUser = credential?.user ?? _auth.currentUser;
      if (fbUser != null) {
        try {
          await FirebaseFirestore.instance
              .collection('firebase_uid_map')
              .doc(fbUser.uid)
              .set({
            'stable_uid': stableUid,
            'email': cleanEmail,
            'updated_at': DateTime.now().toIso8601String(),
          });
        } catch (_) {}
      }

      // 10. Clean up cloud OTP doc if possible
      try {
        final docId = '${cleanEmail}_$cleanOtp';
        await FirebaseFirestore.instance.collection('otps').doc(docId).delete();
      } catch (_) {}

      // Log successful login
      ActivityLogger.instance.log(
        event: 'login_success',
        screen: 'auth',
        details: {'email': cleanEmail},
      );

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
    // Log logout before clearing state
    ActivityLogger.instance.log(event: 'logout', screen: 'profile');
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_stableUidPrefKey);
      await prefs.remove(_stableEmailPrefKey);
    } catch (_) {}
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


