import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/app_categories.dart';
import '../../core/theme/app_colors.dart';
import '../../core/services/database_helper.dart';
import '../auth/auth_provider.dart';

final customCategoriesProvider = StreamProvider<List<CategoryInfo>>((ref) {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return Stream.value([]);

  final controller = StreamController<List<CategoryInfo>>();

  Future<void> _fetch() async {
    try {
      final db = await DatabaseHelper.instance.database;
      final maps = await db.query(
        'custom_categories',
        where: 'user_id = ?',
        whereArgs: [userId],
        orderBy: 'created_at DESC',
      );
      final list = maps.map((row) {
        final name = row['name'] as String;
        final emoji = row['emoji'] as String;
        return CategoryInfo(
          name: name,
          emoji: emoji,
          color: AppColors.catOther,
          keywords: [],
        );
      }).toList();

      if (!controller.isClosed) controller.add(list);
    } catch (e) {
      if (!controller.isClosed) controller.addError(e);
    }
  }

  _fetch();

  final sub = DatabaseHelper.instance.changeStream.listen((table) {
    if (table == 'custom_categories') {
      _fetch();
    }
  });

  controller.onCancel = () {
    sub.cancel();
    controller.close();
  };

  return controller.stream;
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
