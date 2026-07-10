import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../shared/models/models.dart';
import '../auth/auth_provider.dart';

final savingsPlansStreamProvider = StreamProvider<List<SavingsPlan>>((ref) {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return Stream.value([]);

  return FirebaseFirestore.instance
      .collection('users')
      .doc(userId)
      .collection('savings_plans')
      .orderBy('created_at', descending: true)
      .snapshots()
      .map((snapshot) {
    return snapshot.docs.map((doc) {
      return SavingsPlan.fromFirestore(doc.data(), doc.id);
    }).toList();
  });
});

final savingsPlanRepositoryProvider = Provider<SavingsPlanRepository>((ref) {
  return SavingsPlanRepository();
});

class SavingsPlanRepository {
  Future<void> addPlan(String userId, SavingsPlan plan) async {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('savings_plans')
        .doc(plan.id)
        .set(plan.toFirestore());
  }

  Future<void> updateSavedAmount(String userId, String planId, double savedAmount) async {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('savings_plans')
        .doc(planId)
        .update({'saved_amount': savedAmount});
  }

  Future<void> deletePlan(String userId, String planId) async {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('savings_plans')
        .doc(planId)
        .delete();
  }
}
