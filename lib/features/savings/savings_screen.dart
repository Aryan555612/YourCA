import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/format_utils.dart';
import '../../shared/models/models.dart';
import '../../shared/repositories/transaction_repository.dart';
import '../../shared/repositories/user_repository.dart';
import '../../features/auth/auth_provider.dart';
import '../../features/dashboard/dashboard_screen.dart';
import '../../features/transactions/transaction_list_screen.dart';

// ── Savings suggestion engine ─────────────────────────────────────────────────

final savingsSuggestionsProvider =
    FutureProvider.autoDispose<List<SavingsSuggestion>>((ref) async {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return [];

  final now = DateTime.now();
  final thisMonth = DateTime(now.year, now.month, 1);
  final lastMonth = DateTime(now.year, now.month - 1, 1);
  final twoMonthsAgo = DateTime(now.year, now.month - 2, 1);

  final repo = ref.read(transactionRepositoryProvider);

  final [thisTxs, lastTxs, twoAgoTxs] = await Future.wait([
    repo.fetchMonth(userId, thisMonth),
    repo.fetchMonth(userId, lastMonth),
    repo.fetchMonth(userId, twoMonthsAgo),
  ]);

  final userRepo = ref.read(userRepositoryProvider);
  final profile = await userRepo.fetchProfile(userId);
  final targetRate = profile?.savingsTargetRate ?? 0.30;

  return _SuggestionEngine.generate(
    thisTxs: thisTxs,
    lastTxs: lastTxs,
    twoAgoTxs: twoAgoTxs,
    targetSavingsRate: targetRate,
    currentMonth: now,
  );
});

class _SuggestionEngine {
  static List<SavingsSuggestion> generate({
    required List<Transaction> thisTxs,
    required List<Transaction> lastTxs,
    required List<Transaction> twoAgoTxs,
    required double targetSavingsRate,
    required DateTime currentMonth,
  }) {
    final suggestions = <SavingsSuggestion>[];

    // ── Compute category spend by month ─────────────────────────────────
    Map<String, double> _catSpend(List<Transaction> txs) {
      final map = <String, double>{};
      for (final tx in txs) {
        if (tx.type == TransactionType.debit) {
          map[tx.category] = (map[tx.category] ?? 0) + tx.amount;
        }
      }
      return map;
    }

    final thisSpend = _catSpend(thisTxs);
    final lastSpend = _catSpend(lastTxs);
    final twoAgoSpend = _catSpend(twoAgoTxs);

    final thisIncome = thisTxs
        .where((t) => t.type == TransactionType.credit)
        .fold(0.0, (s, t) => s + t.amount);
    final thisExpense =
        thisSpend.values.fold(0.0, (s, v) => s + v);

    // ── 1. Spike detection (> 20% above 2-month average) ──────────────
    for (final cat in thisSpend.keys) {
      if (cat == 'Income' || cat == 'Other') continue;
      final thisAmt = thisSpend[cat] ?? 0;
      final avgPrev =
          ((lastSpend[cat] ?? 0) + (twoAgoSpend[cat] ?? 0)) / 2;

      if (avgPrev > 100 && thisAmt > avgPrev * 1.2) {
        final increase = ((thisAmt - avgPrev) / avgPrev * 100).round();
        suggestions.add(SavingsSuggestion(
          type: SuggestionType.spike,
          title: '📈 $cat spending spiked',
          description:
              'You\'ve spent ${CurrencyUtils.formatNoDecimal(thisAmt)} on $cat this month — $increase% higher than your usual ${CurrencyUtils.formatNoDecimal(avgPrev)}.',
          category: cat,
          amount: thisAmt - avgPrev,
          emoji: '📈',
        ));
      }
    }

    // ── 2. Savings gap suggestion ──────────────────────────────────────
    if (thisIncome > 0) {
      final actualRate = (thisIncome - thisExpense) / thisIncome;
      if (actualRate < targetSavingsRate) {
        // Find biggest non-essential expense category
        final nonEssential = Map.from(thisSpend)
          ..removeWhere((k, _) =>
              k == 'Housing' || k == 'Health' || k == 'Utilities' || k == 'Education');
        if (nonEssential.isNotEmpty) {
          final topCat = (nonEssential.entries.toList()
                ..sort((a, b) => b.value.compareTo(a.value)))
              .first;
          final gapAmount =
              (targetSavingsRate - actualRate) * thisIncome;
          suggestions.add(SavingsSuggestion(
            type: SuggestionType.gap,
            title: '🎯 Close your savings gap',
            description:
                'You need to save ${CurrencyUtils.formatNoDecimal(gapAmount)} more to hit your ${(targetSavingsRate * 100).round()}% goal. Cutting ${topCat.key} spending by ${CurrencyUtils.formatNoDecimal(gapAmount)} would do it.',
            category: topCat.key,
            amount: gapAmount,
            emoji: '🎯',
          ));
        }
      }
    }

    // ── 3. Month projection ────────────────────────────────────────────
    final daysElapsed = currentMonth.day;
    final daysInMonth =
        DateTime(currentMonth.year, currentMonth.month + 1, 0).day;
    if (daysElapsed > 5 && thisIncome > 0) {
      final projectedExpense =
          (thisExpense / daysElapsed) * daysInMonth;
      final projectedSavings = thisIncome - projectedExpense;
      suggestions.add(SavingsSuggestion(
        type: SuggestionType.projection,
        title: '📊 Month projection',
        description:
            'At your current pace, you\'ll save ${CurrencyUtils.formatNoDecimal(projectedSavings)} this month (${daysInMonth - daysElapsed} days left).',
        amount: projectedSavings,
        emoji: '📊',
      ));
    }

    // ── 4. Recurring merchant detection ───────────────────────────────
    final merchantFreq = <String, int>{};
    for (final tx in [...lastTxs, ...twoAgoTxs]) {
      merchantFreq[tx.merchant] = (merchantFreq[tx.merchant] ?? 0) + 1;
    }
    final recurring = merchantFreq.entries
        .where((e) => e.value >= 2)
        .take(3)
        .toList();
    if (recurring.isNotEmpty) {
      final names = recurring.map((e) => e.key).join(', ');
      suggestions.add(SavingsSuggestion(
        type: SuggestionType.recurring,
        title: '🔁 Recurring expenses spotted',
        description:
            'We noticed regular payments to $names. Check if all subscriptions are still used.',
        emoji: '🔁',
      ));
    }

    return suggestions;
  }
}

// ── Savings Screen ────────────────────────────────────────────────────────────

class SavingsScreen extends ConsumerWidget {
  const SavingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final suggestionsAsync = ref.watch(savingsSuggestionsProvider);
    final summaryAsync = ref.watch(monthlySummaryProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Savings Planner')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Savings rate gauge ───────────────────────────────
          summaryAsync.when(
            data: (s) => _SavingsRateCard(summary: s),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('$e'),
          ),
          const SizedBox(height: 24),

          Text('Smart Suggestions', style: AppTextStyles.headlineMedium),
          const SizedBox(height: 4),
          Text(
            'Personalized insights based on your spending patterns',
            style: AppTextStyles.bodySmall
                .copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),

          // ── Suggestions ──────────────────────────────────────
          suggestionsAsync.when(
            data: (suggestions) => suggestions.isEmpty
                ? _EmptySuggestions()
                : Column(
                    children: suggestions
                        .map((s) => _SuggestionCard(suggestion: s))
                        .toList(),
                  ),
            loading: () =>
                const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('Error: $e'),
          ),

          const SizedBox(height: 24),
          _V2Notice(),
          const SizedBox(height: 80),
        ],
      ),
    );
  }
}

class _SavingsRateCard extends StatelessWidget {
  final MonthlySummary summary;

  const _SavingsRateCard({required this.summary});

  @override
  Widget build(BuildContext context) {
    final rate = summary.savingsRate;
    final isGood = rate >= 0.3;
    final color = isGood ? AppColors.credit : AppColors.warning;
    final barWidth = (rate).clamp(0.0, 1.0);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Savings Rate', style: AppTextStyles.headlineSmall),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    isGood ? '✅ On track' : '⚠️ Below target',
                    style: AppTextStyles.labelMedium.copyWith(color: color),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${(rate * 100).toStringAsFixed(1)}%',
                  style: AppTextStyles.moneyMedium.copyWith(color: color),
                ),
                const SizedBox(width: 8),
                Text(' / 30% target',
                    style: AppTextStyles.bodySmall
                        .copyWith(color: AppColors.textSecondary)),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: barWidth,
                backgroundColor: AppColors.surfaceVariant,
                color: color,
                minHeight: 8,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _StatPill(
                    label: 'Income',
                    value: CurrencyUtils.formatCompact(summary.totalIncome),
                    color: AppColors.credit),
                _StatPill(
                    label: 'Expense',
                    value: CurrencyUtils.formatCompact(summary.totalExpense),
                    color: AppColors.debit),
                _StatPill(
                    label: 'Saved',
                    value: CurrencyUtils.formatCompact(
                        summary.netSavings.clamp(0, double.infinity)),
                    color: AppColors.primary),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatPill(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value,
            style: AppTextStyles.titleMedium.copyWith(color: color)),
        Text(label, style: AppTextStyles.labelSmall),
      ],
    );
  }
}

class _SuggestionCard extends StatelessWidget {
  final SavingsSuggestion suggestion;

  const _SuggestionCard({required this.suggestion});

  @override
  Widget build(BuildContext context) {
    final Color cardColor;
    switch (suggestion.type) {
      case SuggestionType.spike:
        cardColor = AppColors.debit.withOpacity(0.08);
        break;
      case SuggestionType.gap:
        cardColor = AppColors.warning.withOpacity(0.08);
        break;
      case SuggestionType.projection:
        cardColor = AppColors.primary.withOpacity(0.08);
        break;
      case SuggestionType.recurring:
        cardColor = AppColors.credit.withOpacity(0.08);
        break;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(suggestion.title, style: AppTextStyles.titleMedium),
          const SizedBox(height: 6),
          Text(
            suggestion.description,
            style: AppTextStyles.bodySmall
                .copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _EmptySuggestions extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          const Text('🎉', style: TextStyle(fontSize: 40)),
          const SizedBox(height: 12),
          Text(
            'Great job!',
            style: AppTextStyles.headlineSmall,
          ),
          const SizedBox(height: 6),
          Text(
            'No spending concerns this month. Keep it up!',
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMedium
                .copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _V2Notice extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primaryGlow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withOpacity(0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.rocket_launch_outlined,
              color: AppColors.primaryLight, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Coming in v2: Account Aggregator (AA)',
                    style: AppTextStyles.labelLarge
                        .copyWith(color: AppColors.primaryLight)),
                const SizedBox(height: 4),
                Text(
                  'India\'s RBI-approved AA framework will let YourCA pull real bank data server-side — no SMS needed. Works on Android, iOS, and Web identically.',
                  style: AppTextStyles.bodySmall
                      .copyWith(color: AppColors.primaryLight.withOpacity(0.8)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
