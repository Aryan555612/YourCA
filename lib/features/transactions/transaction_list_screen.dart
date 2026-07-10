import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shimmer/shimmer.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/format_utils.dart';
import '../../core/constants/app_categories.dart';
import '../../shared/models/models.dart';
import '../../shared/repositories/transaction_repository.dart';
import '../../features/auth/auth_provider.dart';

// â”€â”€ Providers â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

final selectedMonthProvider = StateProvider<DateTime>((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, 1);
});

final transactionFilterProvider =
    StateProvider<String?>((ref) => null); // category filter

final transactionsStreamProvider =
    StreamProvider.autoDispose<List<Transaction>>((ref) {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return Stream.value([]);
  final month = ref.watch(selectedMonthProvider);
  return ref
      .watch(transactionRepositoryProvider)
      .watchMonthTransactions(userId, month);
});

// â”€â”€ Screen â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class TransactionListScreen extends ConsumerWidget {
  const TransactionListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final txAsync = ref.watch(transactionsStreamProvider);
    final selectedMonth = ref.watch(selectedMonthProvider);
    final categoryFilter = ref.watch(transactionFilterProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Transactions'),
        actions: [
          IconButton(
            onPressed: () => context.pushNamed('csvImport'),
            icon: const Icon(Icons.upload_file_rounded),
            tooltip: 'Import CSV',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.pushNamed('addTransaction'),
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: Text('Add', style: AppTextStyles.labelLarge.copyWith(color: Colors.white)),
      ),
      body: Column(
        children: [
          // Month picker
          _MonthSelector(selectedMonth: selectedMonth, ref: ref),

          // Category filter chips
          txAsync.when(
            data: (txs) => _CategoryFilterRow(transactions: txs, ref: ref),
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),

          // Transaction list
          Expanded(
            child: txAsync.when(
              data: (txs) {
                final filtered = categoryFilter == null
                    ? txs
                    : txs
                        .where((t) => t.category == categoryFilter)
                        .toList();

                if (filtered.isEmpty) {
                  return _EmptyState(hasFilter: categoryFilter != null);
                }

                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                  itemCount: filtered.length,
                  itemBuilder: (context, i) {
                    final tx = filtered[i];
                    final showDateHeader = i == 0 ||
                        !DateUtils2.isSameMonth(
                            filtered[i - 1].date, tx.date) ||
                        filtered[i - 1].date.day != tx.date.day;

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (showDateHeader)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(4, 16, 0, 8),
                            child: Text(
                              DateUtils2.toDayMonth(tx.date),
                              style: AppTextStyles.labelSmall.copyWith(
                                  color: AppColors.textSecondary,
                                  letterSpacing: 1),
                            ),
                          ),
                        _TransactionCard(tx: tx),
                      ],
                    );
                  },
                );
              },
              loading: () => _ShimmerList(),
              error: (e, _) => Center(
                child: Text('Error: $e',
                    style: AppTextStyles.bodyMedium
                        .copyWith(color: AppColors.debit)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// â”€â”€ Month Selector â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _MonthSelector extends StatelessWidget {
  final DateTime selectedMonth;
  final WidgetRef ref;

  const _MonthSelector({required this.selectedMonth, required this.ref});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final isCurrentMonth =
        selectedMonth.year == now.year && selectedMonth.month == now.month;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: AppColors.background,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: Icon(Icons.chevron_left_rounded,
                color: AppColors.textSecondary),
            onPressed: () {
              ref.read(selectedMonthProvider.notifier).state = DateTime(
                selectedMonth.year,
                selectedMonth.month - 1,
              );
            },
          ),
          Text(
            DateUtils2.toMonthYear(selectedMonth),
            style: AppTextStyles.headlineSmall,
          ),
          IconButton(
            icon: Icon(Icons.chevron_right_rounded,
                color: isCurrentMonth
                    ? AppColors.textDisabled
                    : AppColors.textSecondary),
            onPressed: isCurrentMonth
                ? null
                : () {
                    ref.read(selectedMonthProvider.notifier).state = DateTime(
                      selectedMonth.year,
                      selectedMonth.month + 1,
                    );
                  },
          ),
        ],
      ),
    );
  }
}

// â”€â”€ Category filter row â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _CategoryFilterRow extends StatelessWidget {
  final List<Transaction> transactions;
  final WidgetRef ref;

  const _CategoryFilterRow({required this.transactions, required this.ref});

  @override
  Widget build(BuildContext context) {
    final categories = transactions.map((t) => t.category).toSet().toList();
    final current = ref.watch(transactionFilterProvider);
    if (categories.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: categories.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          if (i == 0) {
            return FilterChip(
              label: const Text('All'),
              selected: current == null,
              onSelected: (_) =>
                  ref.read(transactionFilterProvider.notifier).state = null,
            );
          }
          final cat = categories[i - 1];
          final info = AppCategories.getCategory(cat);
          return FilterChip(
            avatar: Text(info.emoji),
            label: Text(cat),
            selected: current == cat,
            onSelected: (_) => ref
                .read(transactionFilterProvider.notifier)
                .state = current == cat ? null : cat,
          );
        },
      ),
    );
  }
}

// â”€â”€ Transaction Card â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _TransactionCard extends ConsumerWidget {
  final Transaction tx;

  const _TransactionCard({required this.tx});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDebit = tx.type == TransactionType.debit;
    final catInfo = AppCategories.getCategory(tx.category);

    return Card(
      child: InkWell(
        onTap: () => context.pushNamed('transactionDetail',
            pathParameters: {'txId': tx.id}),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              // Category icon circle
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: (catInfo.color as Color).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(catInfo.emoji,
                      style: const TextStyle(fontSize: 22)),
                ),
              ),
              const SizedBox(width: 14),
              // Merchant + category
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tx.merchant, style: AppTextStyles.titleMedium,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(
                      '${catInfo.emoji} ${tx.category}  Â·  ${tx.source.name}',
                      style: AppTextStyles.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              // Amount
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${isDebit ? '-' : '+'}${CurrencyUtils.formatNoDecimal(tx.amount)}',
                    style: AppTextStyles.moneySmall.copyWith(
                      color: isDebit ? AppColors.debit : AppColors.credit,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    DateUtils2.toTime(tx.date),
                    style: AppTextStyles.labelSmall,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// â”€â”€ Empty State â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _EmptyState extends StatelessWidget {
  final bool hasFilter;

  const _EmptyState({required this.hasFilter});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('\u{1F4B8}', style: const TextStyle(fontSize: 56)),
          const SizedBox(height: 16),
          Text(
            hasFilter ? 'No transactions in this category' : 'No transactions yet',
            style: AppTextStyles.headlineSmall
                .copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 8),
          Text(
            hasFilter
                ? 'Try clearing the filter'
                : 'Tap + to add your first transaction',
            style: AppTextStyles.bodyMedium
                .copyWith(color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }
}

// â”€â”€ Shimmer loading â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _ShimmerList extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: AppColors.surfaceVariant,
      highlightColor: AppColors.cardBackground,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: 8,
        itemBuilder: (_, __) => Container(
          height: 74,
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }
}
