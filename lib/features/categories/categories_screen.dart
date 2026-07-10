import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/constants/app_categories.dart';

class CategoriesScreen extends ConsumerWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Categories')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Transaction Categories',
            style: AppTextStyles.headlineMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'Transactions are auto-categorized. You can fix categories on individual transactions and the correction will be remembered.',
            style: AppTextStyles.bodySmall
                .copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 20),
          ...AppCategories.all.map((cat) => Card(
                child: ListTile(
                  leading: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: (cat.color as Color).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Center(
                      child: Text(cat.emoji,
                          style: const TextStyle(fontSize: 20)),
                    ),
                  ),
                  title: Text(cat.name, style: AppTextStyles.titleMedium),
                  subtitle: cat.keywords.isEmpty
                      ? Text('Fallback category',
                          style: AppTextStyles.bodySmall)
                      : Text(
                          cat.keywords.take(4).join(', ') +
                              (cat.keywords.length > 4 ? '...' : ''),
                          style: AppTextStyles.bodySmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                ),
              )),
        ],
      ),
    );
  }
}
