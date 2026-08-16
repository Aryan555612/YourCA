import 'dart:math';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart' hide Transaction;
import 'package:http/http.dart' as http;

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart' show debugPrint;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../shared/models/models.dart';
import '../../shared/repositories/user_repository.dart';
import '../../shared/repositories/transaction_repository.dart';
import '../../core/services/database_helper.dart';
import '../../core/services/activity_logger.dart';
import '../../core/config/secrets.dart';
import '../sms/sms_listener_service.dart';
import 'package:sqflite/sqflite.dart' hide Transaction;
import 'package:supabase_flutter/supabase_flutter.dart' hide User;
import '../../core/services/supabase_sync_service.dart';


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

      // 1. Generate a 6-digit verification code
      final code = (100000 + Random().nextInt(900000)).toString();
      final expiresAt = DateTime.now().add(const Duration(minutes: 10));

      // 2. Save OTP locally to SharedPreferences for instant offline/online verification
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('pending_otp_code', code);
      await prefs.setString('pending_otp_email', cleanEmail);
      await prefs.setInt('pending_otp_expiry', expiresAt.millisecondsSinceEpoch);

      // 3. Save OTP to Cloud Firestore 'otps' collection as cloud backup
      try {
        await FirebaseFirestore.instance.collection('otps').doc('${cleanEmail}_$code').set({
          'email': cleanEmail,
          'code': code,
          'expires_at': expiresAt.toIso8601String(),
          'created_at': DateTime.now().toIso8601String(),
        });
      } catch (e) {
        debugPrint('⚠️ [FIRESTORE OTP WRITE WARNING]: $e');
      }

      // 4. Try Supabase Auth Email OTP if real Supabase URL is configured
      if (!AppSecrets.supabaseUrl.contains('your-project.supabase.co')) {
        try {
          await Supabase.instance.client.auth.signInWithOtp(email: cleanEmail);
          debugPrint('✅ [SUPABASE AUTH] Email OTP dispatched via Supabase to $cleanEmail');
        } catch (e) {
          debugPrint('⚠️ [SUPABASE AUTH OTP NOTICE]: $e');
        }
      }

      // 5. Direct high-speed REST Email Dispatch via Brevo API
      debugPrint('✉️ [BREVO OTP DISPATCH] Sending OTP $code to $cleanEmail...');
      final response = await http.post(
        Uri.parse('https://api.brevo.com/v3/smtp/email'),
        headers: {
          'api-key': AppSecrets.brevoApiKey,
          'content-type': 'application/json',
          'accept': 'application/json',
        },
        body: jsonEncode({
          'sender': {'name': 'YourCA Finance', 'email': AppSecrets.brevoSenderEmail},
          'to': [{'email': cleanEmail}],
          'subject': '$code is your YourCA verification code',
          'textContent': 'Your YourCA login verification code is: $code. This code is valid for 10 minutes. If you did not request this, please ignore.',
          'htmlContent': '''
<!DOCTYPE html>
<html>
<head><meta charset="utf-8"/></head>
<body style="font-family: Arial, sans-serif; background-color: #0d0e15; margin: 0; padding: 20px; color: #ffffff;">
  <div style="max-width: 480px; margin: 0 auto; background-color: #161824; border-radius: 16px; padding: 32px; border: 1px solid #2d2f45;">
    <h1 style="color: #6C5CE7; text-align: center; margin: 0 0 8px 0; font-size: 26px;">YourCA Finance</h1>
    <p style="color: #a0a0b0; text-align: center; margin: 0 0 24px 0; font-size: 14px;">Personal Finance Planner</p>
    <p style="color: #e0e0e0; font-size: 15px; text-align: center; margin-bottom: 20px;">Your 6-digit login verification code is:</p>
    <div style="background: #0d0e15; border-radius: 12px; padding: 20px; text-align: center; border: 2px solid #6C5CE7; margin-bottom: 24px;">
      <span style="font-size: 40px; font-weight: bold; letter-spacing: 10px; color: #6C5CE7; font-family: monospace;">$code</span>
    </div>
    <p style="color: #707080; font-size: 13px; text-align: center; margin: 0;">
      This code is valid for <strong>10 minutes</strong>.<br/>
      If you did not request this code, please ignore this email.
    </p>
  </div>
</body>
</html>
''',
        }),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        debugPrint('✅ [BREVO REST API] OTP Email successfully sent to $cleanEmail (Status ${response.statusCode})');
      } else {
        debugPrint('⚠️ [BREVO REST API WARNING] Response status ${response.statusCode}: ${response.body}');
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

      bool isVerified = false;

      // 1. Try Supabase Auth verification
      try {
        final res = await Supabase.instance.client.auth.verifyOTP(
          type: OtpType.email,
          email: cleanEmail,
          token: cleanOtp,
        );
        if (res.user != null) {
          isVerified = true;
          debugPrint('✅ [SUPABASE AUTH] OTP verified for $cleanEmail (UID: ${res.user!.id})');
        }
      } catch (e) {
        debugPrint('⚠️ [SUPABASE VERIFY NOTICE]: $e');
      }

      // 2. Fallback check local SharedPreferences / Firestore OTP cache
      if (!isVerified) {
        final localCode = prefs.getString('pending_otp_code');
        final localEmail = prefs.getString('pending_otp_email');
        final localExpiry = prefs.getInt('pending_otp_expiry') ?? 0;

        if (localEmail == cleanEmail && localCode == cleanOtp) {
          if (DateTime.now().millisecondsSinceEpoch <= localExpiry) {
            isVerified = true;
          } else {
            throw Exception('Verification code has expired. Please request a new code.');
          }
        }
      }

      if (!isVerified) {
        final docId = '${cleanEmail}_$cleanOtp';
        try {
          final doc = await FirebaseFirestore.instance
              .collection('otps')
              .doc(docId)
              .get();

          if (doc.exists && doc.data() != null) {
            final expiresAt = doc.data()?['expires_at'] as String? ?? '';
            if (expiresAt.isNotEmpty && DateTime.now().isBefore(DateTime.parse(expiresAt))) {
              isVerified = true;
            } else {
              throw Exception('Verification code has expired. Please request a new code.');
            }
          }
        } catch (e) {
          if (e.toString().contains('expired')) rethrow;
        }
      }

      if (!isVerified) {
        throw Exception('Invalid verification code. Please check the code and try again.');
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

      // 7.7. Restore full backup from Supabase PostgreSQL tables
      try {
        await SupabaseSyncService.instance.restoreFromCloud(stableUid);
      } catch (e) {
        debugPrint('Error restoring from Supabase: $e');
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

      // Restore Savings Plans from Cloud Firestore
      try {
        final savingsSnap = await FirebaseFirestore.instance
            .collection('users')
            .doc(stableUid)
            .collection('savingsPlans')
            .get();
        if (savingsSnap.docs.isNotEmpty) {
          final db = await DatabaseHelper.instance.database;
          for (final doc in savingsSnap.docs) {
            final data = doc.data();
            await db.insert(
              'savings_plans',
              {
                'id': doc.id,
                'user_id': stableUid,
                'title': data['title'] ?? '',
                'description': data['description'] ?? '',
                'target_amount': (data['target_amount'] ?? 0.0).toDouble(),
                'saved_amount': (data['saved_amount'] ?? 0.0).toDouble(),
                'target_date': data['target_date'] ?? DateTime.now().toIso8601String(),
                'is_custom': (data['is_custom'] == true) ? 1 : 0,
                'created_at': data['created_at'] ?? DateTime.now().toIso8601String(),
              },
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
          DatabaseHelper.instance.notifyChange('savings_plans');
        }
      } catch (e) {
        debugPrint('Error restoring savings plans: $e');
      }

      // Restore Custom Categories from Cloud Firestore
      try {
        final catSnap = await FirebaseFirestore.instance
            .collection('users')
            .doc(stableUid)
            .collection('customCategories')
            .get();
        if (catSnap.docs.isNotEmpty) {
          final db = await DatabaseHelper.instance.database;
          for (final doc in catSnap.docs) {
            final data = doc.data();
            await db.insert(
              'custom_categories',
              {
                'id': doc.id,
                'user_id': stableUid,
                'name': data['name'] ?? '',
                'emoji': data['emoji'] ?? '🏷️',
                'created_at': data['created_at'] ?? DateTime.now().toIso8601String(),
              },
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
          DatabaseHelper.instance.notifyChange('custom_categories');
        }
      } catch (e) {
        debugPrint('Error restoring custom categories: $e');
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

    // Purge local SQLite database to prevent any data leak between accounts
    try {
      await DatabaseHelper.instance.clearAllData();
    } catch (e) {
      debugPrint('Error clearing local SQLite data on sign-out: $e');
    }

    ref.read(stableUserIdProvider.notifier).state = null;
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (_) {}
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


