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
  FirebaseAuth? _authInstance;
  UserRepository? _userRepoInstance;

  FirebaseAuth get _auth {
    if (_authInstance != null) return _authInstance!;
    try {
      return ref.read(firebaseAuthProvider);
    } catch (_) {
      return FirebaseAuth.instance;
    }
  }

  UserRepository get _userRepo {
    if (_userRepoInstance != null) return _userRepoInstance!;
    return ref.read(userRepositoryProvider);
  }

  @override
  Future<void> build() async {
    try {
      _authInstance = ref.watch(firebaseAuthProvider);
    } catch (_) {}
    try {
      _userRepoInstance = ref.watch(userRepositoryProvider);
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
    final cleanEmail = email.toLowerCase().trim();
    final stableUid = _generateStableId(cleanEmail);

    try {
      final docRef = FirebaseFirestore.instance
          .collection('user_stable_ids')
          .doc(cleanEmail);

      final doc = await docRef.get();
      if (doc.exists && doc.data()?['stable_uid'] != null) {
        return doc.data()!['stable_uid'] as String;
      }

      await docRef.set({
        'stable_uid': stableUid,
        'email': cleanEmail,
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (_) {
      // Firestore uninitialized or offline — fall back to locally generated stable ID
    }
    return stableUid;
  }

  // ── Custom Email OTP Authentication flow ──────────────────────────────────
  Future<void> sendEmailOtp({
    required String email,
    http.Client? httpClient,
  }) async {
    state = const AsyncLoading();
    try {
      final cleanEmail = email.toLowerCase().trim();

      if (cleanEmail.isEmpty || !cleanEmail.contains('@')) {
        throw Exception('Please enter a valid email address.');
      }

      // Pre-authenticate anonymously if needed for Firebase services
      try {
        if (_auth.currentUser == null) {
          await _auth.signInAnonymously();
        }
      } catch (e) {
        debugPrint('Note: Pre-auth anonymous sign-in skipped: $e');
      }

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
      final client = httpClient ?? http.Client();
      final response = await client.post(
        Uri.parse('https://api.brevo.com/v3/smtp/email'),
        headers: {
          'api-key': AppSecrets.brevoApiKey,
          'content-type': 'application/json',
          'accept': 'application/json',
        },
        body: jsonEncode({
          'sender': {'name': 'YourCA', 'email': AppSecrets.brevoSenderEmail},
          'to': [{'email': cleanEmail}],
          'subject': 'YourCA OTP Verification Code',
          'textContent': 'Use the following verification code to sign in to your finance tracking account: $code. This code will expire in 10 minutes. If you did not request this code, you can safely ignore this email.',
          'htmlContent': '''
<!DOCTYPE html>
<html>
<head><meta charset="utf-8"/></head>
<body style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; background-color: #0d0e15; margin: 0; padding: 32px 16px; color: #ffffff;">
  <div style="max-width: 460px; margin: 0 auto; background-color: #161824; border-radius: 20px; padding: 36px 32px; border: 1px solid #2d2f45; box-shadow: 0 10px 25px rgba(0,0,0,0.5);">
    <h2 style="color: #6C5CE7; text-align: left; margin: 0 0 16px 0; font-size: 24px; font-weight: 800; letter-spacing: -0.5px;">YourCA</h2>
    <p style="color: #a0a0b0; font-size: 15px; text-align: left; margin: 0 0 28px 0; line-height: 1.5;">Use the following verification code to sign in to your finance tracking account:</p>
    <div style="background-color: #0d0e15; border-radius: 14px; padding: 24px 16px; text-align: center; border: 1px solid #2d2f45; margin-bottom: 28px;">
      <span style="font-size: 42px; font-weight: 900; letter-spacing: 12px; color: #ffffff; font-family: monospace;">$code</span>
    </div>
    <p style="color: #707080; font-size: 13px; text-align: left; margin: 0; line-height: 1.5;">
      This code will expire in 10 minutes. If you did not request this code, you can safely ignore this email.
    </p>
  </div>
</body>
</html>
''',
        }),
      ).timeout(const Duration(seconds: 12));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        debugPrint('✅ [BREVO REST API] OTP Email successfully sent to $cleanEmail (Status ${response.statusCode})');
      } else {
        debugPrint('❌ [BREVO REST API ERROR] Status ${response.statusCode}: ${response.body}');
        throw Exception('Failed to send verification email (Status ${response.statusCode}). Please check your email address.');
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

      // 1. Try Supabase Auth verification if configured
      if (!isVerified && !AppSecrets.supabaseUrl.contains('your-project.supabase.co')) {
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
      }

      // 2. Check local SharedPreferences OTP cache
      if (!isVerified) {
        final localCode = prefs.getString('pending_otp_code');
        final localEmail = prefs.getString('pending_otp_email');
        final localExpiry = prefs.getInt('pending_otp_expiry') ?? 0;

        if (localEmail == cleanEmail && localCode == cleanOtp) {
          if (localExpiry == 0 || DateTime.now().millisecondsSinceEpoch <= localExpiry) {
            isVerified = true;
          } else {
            throw Exception('Verification code has expired. Please request a new code.');
          }
        }
      }

      // 3. Check Cloud Firestore 'otps' collection
      if (!isVerified) {
        final docId = '${cleanEmail}_$cleanOtp';
        try {
          final doc = await FirebaseFirestore.instance
              .collection('otps')
              .doc(docId)
              .get();

          if (doc.exists && doc.data() != null) {
            final expiresAt = doc.data()?['expires_at'] as String? ?? '';
            if (expiresAt.isEmpty || DateTime.now().isBefore(DateTime.parse(expiresAt))) {
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

      try {
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
      } catch (e) {
        debugPrint('Note: Profile local storage sync skipped: $e');
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
      User? fbUser = credential?.user;
      try {
        fbUser ??= _auth.currentUser;
      } catch (_) {}
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
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (_) {}
    try {
      await _auth.signOut();
    } catch (e) {
      debugPrint('Note: Firebase signOut skipped or error: $e');
    }
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


