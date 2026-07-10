import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/models.dart';

final userRepositoryProvider = Provider<UserRepository>((ref) {
  return UserRepository(FirebaseFirestore.instance);
});

class UserRepository {
  final FirebaseFirestore _firestore;

  UserRepository(this._firestore);

  DocumentReference<Map<String, dynamic>> _userDoc(String userId) =>
      _firestore.collection('users').doc(userId);

  Future<UserProfile?> fetchProfile(String userId) async {
    final doc = await _userDoc(userId).get();
    if (!doc.exists) return null;
    return UserProfile.fromFirestore(doc.data()!, doc.id);
  }

  Stream<UserProfile?> watchProfile(String userId) {
    return _userDoc(userId).snapshots().map((doc) {
      if (!doc.exists) return null;
      return UserProfile.fromFirestore(doc.data()!, doc.id);
    });
  }

  Future<void> createProfile(UserProfile profile) async {
    await _userDoc(profile.id).set(profile.toFirestore());
  }

  Future<void> updateProfile(UserProfile profile) async {
    await _userDoc(profile.id).update(profile.toFirestore());
  }

  // ── Merchant correction lookup ─────────────────────────────────────────
  CollectionReference<Map<String, dynamic>> _correctionsCol(String userId) =>
      _userDoc(userId).collection('merchantCorrections');

  Future<String?> fetchMerchantCorrection(
      String userId, String merchant) async {
    final key = merchant.toLowerCase().replaceAll(RegExp(r'\s+'), '_');
    final doc = await _correctionsCol(userId).doc(key).get();
    if (!doc.exists) return null;
    return doc.data()?['category'] as String?;
  }

  Future<void> saveMerchantCorrection(
      String userId, String merchant, String category) async {
    final key = merchant.toLowerCase().replaceAll(RegExp(r'\s+'), '_');
    await _correctionsCol(userId).doc(key).set({
      'merchant': merchant,
      'category': category,
      'updated_at': DateTime.now().toIso8601String(),
    });
  }

  Future<Map<String, String>> fetchAllCorrections(String userId) async {
    final snap = await _correctionsCol(userId).get();
    final result = <String, String>{};
    for (final doc in snap.docs) {
      final merchant = doc.data()['merchant'] as String? ?? doc.id;
      final category = doc.data()['category'] as String? ?? 'Other';
      result[merchant.toLowerCase()] = category;
    }
    return result;
  }
}
