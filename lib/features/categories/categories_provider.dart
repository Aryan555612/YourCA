import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/app_categories.dart';
import '../../core/theme/app_colors.dart';
import '../auth/auth_provider.dart';

final customCategoriesProvider = StreamProvider<List<CategoryInfo>>((ref) {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return Stream.value([]);

  return FirebaseFirestore.instance
      .collection('users')
      .doc(userId)
      .collection('custom_categories')
      .snapshots()
      .map((snapshot) {
    return snapshot.docs.map((doc) {
      final data = doc.data();
      return CategoryInfo(
        name: data['name'] ?? doc.id,
        emoji: data['emoji'] ?? '📦',
        color: AppColors.catOther,
        keywords: List<String>.from(data['keywords'] ?? []),
      );
    }).toList();
  });
});

final pinnedCategoriesProvider =
    StateNotifierProvider<PinnedCategoriesNotifier, List<String>>((ref) {
  return PinnedCategoriesNotifier();
});

class PinnedCategoriesNotifier extends StateNotifier<List<String>> {
  PinnedCategoriesNotifier() : super([]) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getStringList('pinned_categories') ?? [];
  }

  Future<void> togglePin(String categoryName) async {
    final prefs = await SharedPreferences.getInstance();
    final current = [...state];
    if (current.contains(categoryName)) {
      current.remove(categoryName);
    } else {
      current.add(categoryName);
    }
    await prefs.setStringList('pinned_categories', current);
    state = current;
  }
}

final allCategoriesProvider = Provider<List<CategoryInfo>>((ref) {
  final custom = ref.watch(customCategoriesProvider).value ?? [];
  final pinned = ref.watch(pinnedCategoriesProvider);

  final map = <String, CategoryInfo>{};
  // Base categories
  for (final cat in AppCategories.all) {
    map[cat.name] = cat;
  }
  // Custom categories override
  for (final cat in custom) {
    map[cat.name] = cat;
  }

  final list = map.values.toList();

  list.sort((a, b) {
    final aPinned = pinned.contains(a.name);
    final bPinned = pinned.contains(b.name);
    if (aPinned && !bPinned) return -1;
    if (!aPinned && bPinned) return 1;
    return 0;
  });

  return list;
});
