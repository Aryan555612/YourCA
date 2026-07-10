import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/constants/app_categories.dart';
import '../auth/auth_provider.dart';
import 'categories_provider.dart';

class CategoriesScreen extends ConsumerWidget {
  const CategoriesScreen({super.key});

  void _showAddCategoryDialog(BuildContext context, WidgetRef ref) {
    final nameController = TextEditingController();
    final emojiController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Custom Category'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nameController,
                style: AppTextStyles.bodyMedium,
                decoration: const InputDecoration(
                  labelText: 'Category Name',
                  hintText: 'Enter name (e.g. Gym)',
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Enter a name';
                  if (v.trim().toLowerCase() == 'income' || v.trim().toLowerCase() == 'other') {
                    return 'Name reserved';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: emojiController,
                style: AppTextStyles.bodyMedium,
                decoration: const InputDecoration(
                  labelText: 'Emoji Symbol',
                  hintText: 'Enter single emoji (e.g. 🏋️)',
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Enter an emoji';
                  if (v.trim().runes.length != 1 && v.trim().length > 2) {
                    return 'Enter exactly one emoji';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              final name = nameController.text.trim();
              final emoji = emojiController.text.trim();
              final userId = ref.read(currentUserIdProvider);

              if (userId != null) {
                await FirebaseFirestore.instance
                    .collection('users')
                    .doc(userId)
                    .collection('custom_categories')
                    .doc(name)
                    .set({
                  'name': name,
                  'emoji': emoji,
                  'keywords': [name.toLowerCase()],
                });
              }

              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Custom category "$name" added successfully!'),
                    backgroundColor: AppColors.credit,
                  ),
                );
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref, String catName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Category'),
        content: Text('Are you sure you want to delete the custom category "$catName"? All transactions under it will fall back to "Other".'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final userId = ref.read(currentUserIdProvider);
              if (userId != null) {
                // Delete custom category document
                await FirebaseFirestore.instance
                    .collection('users')
                    .doc(userId)
                    .collection('custom_categories')
                    .doc(catName)
                    .delete();

                // Re-categorize transactions under this category to 'Other'
                final txQuery = await FirebaseFirestore.instance
                    .collection('users')
                    .doc(userId)
                    .collection('transactions')
                    .where('category', isEqualTo: catName)
                    .get();

                final batch = FirebaseFirestore.instance.batch();
                for (final doc in txQuery.docs) {
                  batch.update(doc.reference, {'category': 'Other'});
                }
                await batch.commit();
              }

              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Custom category deleted')),
                );
              }
            },
            child: const Text('Delete', style: TextStyle(color: AppColors.debit)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(allCategoriesProvider);
    final pinned = ref.watch(pinnedCategoriesProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Categories')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddCategoryDialog(context, ref),
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: const Text('Add Custom', style: TextStyle(color: Colors.white)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        children: [
          Text(
            'Transaction Categories',
            style: AppTextStyles.headlineMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'Transactions are auto-categorized. You can add custom categories, pin them to top, or reassign individual transactions.',
            style: AppTextStyles.bodySmall
                .copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 20),
          ...categories.map((cat) {
            final isPinned = pinned.contains(cat.name);
            final isBaseCategory = AppCategories.all.any((c) => c.name == cat.name);

            return Card(
              child: ListTile(
                leading: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: (cat.color is Color
                            ? cat.color as Color
                            : AppColors.catOther)
                        .withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: Text(cat.emoji,
                        style: const TextStyle(fontSize: 20)),
                  ),
                ),
                title: Row(
                  children: [
                    Text(cat.name, style: AppTextStyles.titleMedium),
                    if (!isBaseCategory) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Custom',
                          style: AppTextStyles.labelSmall.copyWith(
                            color: AppColors.primary,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                subtitle: isBaseCategory
                    ? (cat.keywords.isEmpty
                        ? Text('Fallback category', style: AppTextStyles.bodySmall)
                        : Text(
                            cat.keywords.take(4).join(', ') +
                                (cat.keywords.length > 4 ? '...' : ''),
                            style: AppTextStyles.bodySmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ))
                    : Text('Custom category', style: AppTextStyles.bodySmall),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(
                        isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                        color: isPinned ? AppColors.primary : AppColors.textTertiary,
                        size: 20,
                      ),
                      onPressed: () =>
                          ref.read(pinnedCategoriesProvider.notifier).togglePin(cat.name),
                      tooltip: isPinned ? 'Unpin from top' : 'Pin to top',
                    ),
                    if (!isBaseCategory)
                      IconButton(
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          color: AppColors.debit,
                          size: 20,
                        ),
                        onPressed: () => _confirmDelete(context, ref, cat.name),
                        tooltip: 'Delete custom category',
                      ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}
