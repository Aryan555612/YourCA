import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/format_utils.dart';
import '../../core/constants/app_categories.dart';
import '../../shared/models/models.dart';
import '../../features/transactions/transaction_list_screen.dart';

class MerchantBreakdownScreen extends ConsumerWidget {
  final TransactionType type;

  const MerchantBreakdownScreen({super.key, required this.type});

  void _showMerchantTransactions(BuildContext context, String merchant, List<Transaction> txs) {
    final isDebit = type == TransactionType.debit;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.cardBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    merchant,
                    style: AppTextStyles.headlineSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            Text(
              '${txs.length} transaction${txs.length > 1 ? 's' : ''} this month',
              style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.separated(
                itemCount: txs.length,
                separatorBuilder: (_, __) => Divider(color: AppColors.divider, height: 1),
                itemBuilder: (context, i) {
                  final tx = txs[i];
                  final catInfo = AppCategories.getCategory(tx.category);
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: (catInfo.color as Color).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Center(child: Text(catInfo.emoji, style: const TextStyle(fontSize: 18))),
                    ),
                    title: Text(
                      '${catInfo.emoji} ${tx.category}',
                      style: AppTextStyles.titleMedium,
                    ),
                    subtitle: Text(
                      '${DateUtils2.toDayMonth(tx.date)} at ${DateUtils2.toTime(tx.date)}${tx.bankReference != null ? ' • Ref: ${tx.bankReference}' : ''}',
                      style: AppTextStyles.labelSmall,
                    ),
                    trailing: Text(
                      '${isDebit ? '-' : '+'}${CurrencyUtils.format(tx.amount)}',
                      style: AppTextStyles.titleMedium.copyWith(
                        color: isDebit ? AppColors.debit : AppColors.credit,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      context.pushNamed(
                        'transactionDetail',
                        pathParameters: {'txId': tx.id},
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final txAsync = ref.watch(transactionsStreamProvider);
    final selectedMonth = ref.watch(selectedMonthProvider);
    final isDebit = type == TransactionType.debit;
    final themeColor = isDebit ? AppColors.debit : AppColors.credit;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(isDebit ? 'Expenses Breakdown' : 'Income Breakdown'),
      ),
      body: Column(
        children: [
          // Header Summary Card
          Container(
            width: double.infinity,
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: themeColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: themeColor.withValues(alpha: 0.2)),
            ),
            child: Column(
              children: [
                Text(
                  isDebit ? 'Total Monthly Expenses' : 'Total Monthly Income',
                  style: AppTextStyles.labelLarge.copyWith(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 8),
                txAsync.when(
                  data: (txs) {
                    final filtered = txs.where((t) => t.type == type);
                    final sum = filtered.fold(0.0, (s, t) => s + t.amount);
                    return Text(
                      CurrencyUtils.format(sum),
                      style: AppTextStyles.moneyLarge.copyWith(color: themeColor),
                    );
                  },
                  loading: () => const SizedBox(
                    height: 30,
                    width: 30,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  error: (_, __) => const Text('₹0.00'),
                ),
                const SizedBox(height: 8),
                Text(
                  'Breakdown for ${DateUtils2.toMonthYear(selectedMonth)}',
                  style: AppTextStyles.bodySmall.copyWith(color: AppColors.textTertiary),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                isDebit ? 'Recipients List' : 'Senders List',
                style: AppTextStyles.headlineSmall,
              ),
            ),
          ),

          Expanded(
            child: txAsync.when(
              data: (txs) {
                final filtered = txs.where((t) => t.type == type).toList();
                if (filtered.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(isDebit ? '💸' : '💰', style: const TextStyle(fontSize: 48)),
                        const SizedBox(height: 12),
                        Text(
                          isDebit ? 'No expenses recorded yet.' : 'No income recorded yet.',
                          style: AppTextStyles.titleMedium.copyWith(color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  );
                }

                // Group by merchant
                final groups = <String, List<Transaction>>{};
                for (final tx in filtered) {
                  groups.putIfAbsent(tx.merchant, () => []).add(tx);
                }

                // Sort transactions within each merchant group by date descending (latest first)
                for (final list in groups.values) {
                  list.sort((a, b) => b.date.compareTo(a.date));
                }

                // Calculate sums and sort groups by the date of their most recent transaction (latest first)
                final merchantSums = groups.entries.map((entry) {
                  final sum = entry.value.fold(0.0, (s, t) => s + t.amount);
                  return MapEntry(entry.key, sum);
                }).toList()
                  ..sort((a, b) {
                    final latestA = groups[a.key]!.first.date;
                    final latestB = groups[b.key]!.first.date;
                    return latestB.compareTo(latestA);
                  });

                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  itemCount: merchantSums.length,
                  itemBuilder: (context, i) {
                    final item = merchantSums[i];
                    final merchantName = item.key;
                    final totalAmount = item.value;
                    final listTxs = groups[merchantName]!;

                    // Find most common category emoji for this merchant
                    final categoryCount = <String, int>{};
                    for (final tx in listTxs) {
                      categoryCount[tx.category] = (categoryCount[tx.category] ?? 0) + 1;
                    }
                    final commonCategory = (categoryCount.entries.toList()
                          ..sort((a, b) => b.value.compareTo(a.value)))
                        .first
                        .key;
                    final catInfo = AppCategories.getCategory(commonCategory);

                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: InkWell(
                        onTap: () => _showMerchantTransactions(context, merchantName, listTxs),
                        borderRadius: BorderRadius.circular(16),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          child: Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: themeColor.withValues(alpha: 0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: Text(catInfo.emoji, style: const TextStyle(fontSize: 20)),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      merchantName,
                                      style: AppTextStyles.titleMedium,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${listTxs.length} transaction${listTxs.length > 1 ? 's' : ''}',
                                      style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                CurrencyUtils.format(totalAmount),
                                style: AppTextStyles.titleMedium.copyWith(
                                  color: themeColor,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary, size: 18),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
            ),
          ),
        ],
      ),
    );
  }
}
