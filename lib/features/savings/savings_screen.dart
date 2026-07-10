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
import 'savings_plans_provider.dart';
import 'package:uuid/uuid.dart';

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

    // ── Compute category spend by month ────────────────────
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

    // ── 1. Spike detection (> 20% above 2-month average) ────
    for (final cat in thisSpend.keys) {
      if (cat == 'Income' || cat == 'Other') continue;
      final thisAmt = thisSpend[cat] ?? 0;
      final avgPrev =
          ((lastSpend[cat] ?? 0) + (twoAgoSpend[cat] ?? 0)) / 2;

      if (avgPrev > 100 && thisAmt > avgPrev * 1.2) {
        final increase = ((thisAmt - avgPrev) / avgPrev * 100).round();
        suggestions.add(SavingsSuggestion(
          type: SuggestionType.spike,
          title: '\u{1F4C8} $cat spending spiked',
          description:
              'You\'ve spent ${CurrencyUtils.formatNoDecimal(thisAmt)} on $cat this month \u2014 $increase% higher than your usual ${CurrencyUtils.formatNoDecimal(avgPrev)}.',
          category: cat,
          amount: thisAmt - avgPrev,
          emoji: '\u{1F4C8}',
        ));
      }
    }

    // ── 2. Savings gap suggestion ──────────────────────────────────
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
            title: '\u{1F3AF} Close your savings gap',
            description:
                'You need to save ${CurrencyUtils.formatNoDecimal(gapAmount)} more to hit your ${(targetSavingsRate * 100).round()}% goal. Cutting ${topCat.key} spending by ${CurrencyUtils.formatNoDecimal(gapAmount)} would do it.',
            category: topCat.key,
            amount: gapAmount,
            emoji: '\u{1F3AF}',
          ));
        }
      }
    }

    // ── 3. Month projection ────────────────────────────────────────
    final daysElapsed = currentMonth.day;
    final daysInMonth =
        DateTime(currentMonth.year, currentMonth.month + 1, 0).day;
    if (daysElapsed > 5 && thisIncome > 0) {
      final projectedExpense =
          (thisExpense / daysElapsed) * daysInMonth;
      final projectedSavings = thisIncome - projectedExpense;
      suggestions.add(SavingsSuggestion(
        type: SuggestionType.projection,
        title: '\u{1F4CA} Month projection',
        description:
            'At your current pace, you\'ll save ${CurrencyUtils.formatNoDecimal(projectedSavings)} this month (${daysInMonth - daysElapsed} days left).',
        amount: projectedSavings,
        emoji: '\u{1F4CA}',
      ));
    }

    // ── 4. Recurring merchant detection ──────────────────────────
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
        title: '\u{1F50D} Recurring expenses spotted',
        description:
            'We noticed regular payments to $names. Check if all subscriptions are still used.',
        emoji: '\u{1F50D}',
      ));
    }

    return suggestions;
  }
}

// ── Savings Screen ──────────────────────────────────────────────────────────

class SavingsScreen extends ConsumerWidget {
  const SavingsScreen({super.key});

  void _showCreatePlanDialog(BuildContext context, WidgetRef ref, double income) {
    final titleController = TextEditingController();
    final targetController = TextEditingController();
    DateTime selectedDate = DateTime.now().add(const Duration(days: 90));
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('New Savings Goal Plan'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: titleController,
                  style: AppTextStyles.bodyMedium,
                  decoration: const InputDecoration(
                    labelText: 'Goal Title',
                    hintText: 'e.g., Trip to Ladakh, New Laptop',
                  ),
                  validator: (v) => v == null || v.trim().isEmpty ? 'Enter a title' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: targetController,
                  style: AppTextStyles.bodyMedium,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Target Amount (₹)',
                    hintText: 'e.g., 50000',
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Enter an amount';
                    if (double.tryParse(v) == null || double.parse(v) <= 0) {
                      return 'Enter a valid amount';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Target Date: ${selectedDate.day}/${selectedDate.month}/${selectedDate.year}',
                        style: AppTextStyles.bodyMedium,
                      ),
                    ),
                    TextButton(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: selectedDate,
                          firstDate: DateTime.now(),
                          lastDate: DateTime.now().add(const Duration(days: 3650)),
                        );
                        if (picked != null) {
                          setState(() => selectedDate = picked);
                        }
                      },
                      child: const Text('Change'),
                    ),
                  ],
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
                final userId = ref.read(currentUserIdProvider);
                if (userId == null) return;

                final plan = SavingsPlan(
                  id: const Uuid().v4(),
                  userId: userId,
                  title: titleController.text.trim(),
                  description: 'Custom Savings Goal',
                  targetAmount: double.parse(targetController.text),
                  savedAmount: 0.0,
                  targetDate: selectedDate,
                  isCustom: true,
                  createdAt: DateTime.now(),
                );

                await ref.read(savingsPlanRepositoryProvider).addPlan(userId, plan);

                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Savings goal "${plan.title}" created!'),
                      backgroundColor: AppColors.credit,
                    ),
                  );
                }
              },
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final suggestionsAsync = ref.watch(savingsSuggestionsProvider);
    final summaryAsync = ref.watch(monthlySummaryProvider);
    final plansAsync = ref.watch(savingsPlansStreamProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Savings Planner')),
      body: summaryAsync.when(
        data: (summary) {
          final savedAmount = summary.totalIncome - summary.totalExpense;
          final plans = plansAsync.value ?? [];

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // ── Savings rate card ──
              _SavingsRateCard(summary: summary),
              const SizedBox(height: 24),

              // ── 3-4 Savings Plan Templates Section ──
              Text('Savings Plans & Templates', style: AppTextStyles.headlineMedium),
              const SizedBox(height: 4),
              Text(
                'Activate budgeting frameworks or track custom goals',
                style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 16),

              // Horizontal scroll of Templates
              SizedBox(
                height: 180,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    _TemplatePlanCard(
                      title: '50-30-20 Rule Plan',
                      icon: Icons.pie_chart_rounded,
                      color: AppColors.primary,
                      description: 'Needs (50%), Wants (30%), Savings (20%).',
                      progressText: 'Savings Target: \u20B9${(summary.totalIncome * 0.2).toStringAsFixed(0)}',
                      details: 'Needs Limit: \u20B9${(summary.totalIncome * 0.5).toStringAsFixed(0)}\nWants Limit: \u20B9${(summary.totalIncome * 0.3).toStringAsFixed(0)}',
                    ),
                    const SizedBox(width: 12),
                    _TemplatePlanCard(
                      title: 'Emergency Fund Builder',
                      icon: Icons.shield_rounded,
                      color: AppColors.credit,
                      description: 'Save 3 months of essential income to protect you.',
                      progressText: 'Target Goal: \u20B9${(summary.totalIncome * 3).toStringAsFixed(0)}',
                      details: 'Saved Progress: \u20B9${savedAmount.clamp(0, double.infinity).toStringAsFixed(0)}',
                    ),
                    const SizedBox(width: 12),
                    _TemplatePlanCard(
                      title: 'Envelope Budget Plan',
                      icon: Icons.mail_outline_rounded,
                      color: AppColors.warning,
                      description: 'Put \u20B920,000 aside for specific short-term envelope goals.',
                      progressText: 'Envelope Target: \u20B920,000',
                      details: 'Saved Progress: \u20B9${savedAmount.clamp(0, 20000.0).toStringAsFixed(0)}',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // ── Custom Savings Plans List ──
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Custom Savings Goals', style: AppTextStyles.headlineMedium),
                  TextButton.icon(
                    onPressed: () => _showCreatePlanDialog(context, ref, summary.totalIncome),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Add Goal'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (plans.isEmpty)
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Center(
                    child: Text(
                      'No custom goals created yet. Tap "Add Goal" above to create one!',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
                    ),
                  ),
                )
              else
                ...plans.map((plan) => _CustomPlanCard(plan: plan, ref: ref)),

              const SizedBox(height: 24),

              // ── Suggestions ──
              Text('Smart Suggestions', style: AppTextStyles.headlineMedium),
              const SizedBox(height: 4),
              Text(
                'Personalized insights based on your spending patterns',
                style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 16),
              suggestionsAsync.when(
                data: (suggestions) => suggestions.isEmpty
                    ? _EmptySuggestions()
                    : Column(
                        children: suggestions
                            .map((s) => _SuggestionCard(suggestion: s))
                            .toList(),
                      ),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Text('Error: $e'),
              ),

              const SizedBox(height: 24),
              _V2Notice(),
              const SizedBox(height: 80),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }
}

// ── Savings Rate Card ──
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
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    isGood ? '\u2705 On track' : '\u26A0\uFE0F Below target',
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

// ── Stat Pill ──
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

// ── Suggestion Card ──
class _SuggestionCard extends StatelessWidget {
  final SavingsSuggestion suggestion;

  const _SuggestionCard({required this.suggestion});

  @override
  Widget build(BuildContext context) {
    final Color cardColor;
    switch (suggestion.type) {
      case SuggestionType.spike:
        cardColor = AppColors.debit.withValues(alpha: 0.08);
        break;
      case SuggestionType.gap:
        cardColor = AppColors.warning.withValues(alpha: 0.08);
        break;
      case SuggestionType.projection:
        cardColor = AppColors.primary.withValues(alpha: 0.08);
        break;
      case SuggestionType.recurring:
        cardColor = AppColors.credit.withValues(alpha: 0.08);
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

// ── Empty Suggestions Card ──
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
          const Text('\u{1F389}', style: TextStyle(fontSize: 40)),
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

// ── V2 Notice Card ──
class _V2Notice extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primaryGlow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
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
                  'India\'s RBI-approved AA framework will let YourCA pull real bank data server-side \u2014 no SMS needed. Works on Android, iOS, and Web identically.',
                  style: AppTextStyles.bodySmall
                      .copyWith(color: AppColors.primaryLight.withValues(alpha: 0.8)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Template Plan Card Widget ──
class _TemplatePlanCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final String description;
  final String progressText;
  final String details;

  const _TemplatePlanCard({
    required this.title,
    required this.icon,
    required this.color,
    required this.description,
    required this.progressText,
    required this.details,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 250,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: AppTextStyles.titleMedium.copyWith(fontWeight: FontWeight.bold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            description,
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const Spacer(),
          Text(
            progressText,
            style: AppTextStyles.labelSmall.copyWith(color: color, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            details,
            style: AppTextStyles.labelSmall.copyWith(fontSize: 10, color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }
}

// ── Custom Plan Card Widget ──
class _CustomPlanCard extends StatefulWidget {
  final SavingsPlan plan;
  final WidgetRef ref;

  const _CustomPlanCard({required this.plan, required this.ref});

  @override
  State<_CustomPlanCard> createState() => _CustomPlanCardState();
}

class _CustomPlanCardState extends State<_CustomPlanCard> {
  late double _localSaved;

  @override
  void initState() {
    super.initState();
    _localSaved = widget.plan.savedAmount;
  }

  @override
  void didUpdateWidget(covariant _CustomPlanCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.plan.savedAmount != widget.plan.savedAmount) {
      _localSaved = widget.plan.savedAmount;
    }
  }

  @override
  Widget build(BuildContext context) {
    final plan = widget.plan;
    final percent = plan.targetAmount > 0 ? (_localSaved / plan.targetAmount).clamp(0.0, 1.0) : 0.0;
    final remains = (plan.targetAmount - _localSaved).clamp(0.0, double.infinity);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.stars_rounded, color: AppColors.primary, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(plan.title, style: AppTextStyles.titleMedium),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, color: AppColors.debit, size: 20),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () {
                    widget.ref.read(savingsPlanRepositoryProvider).deletePlan(plan.userId, plan.id);
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Saved: \u20B9${_localSaved.toStringAsFixed(0)} of \u20B9${plan.targetAmount.toStringAsFixed(0)}',
                  style: AppTextStyles.bodyMedium,
                ),
                Text(
                  '${(percent * 100).toStringAsFixed(0)}%',
                  style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.bold, color: AppColors.primary),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: percent,
                backgroundColor: AppColors.surfaceVariant,
                color: AppColors.primary,
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 12),
            // Slider to adjust saved amount
            Row(
              children: [
                Text('Contribution:', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                Expanded(
                  child: Slider(
                    value: _localSaved,
                    min: 0.0,
                    max: plan.targetAmount,
                    divisions: 100,
                    onChanged: (val) {
                      setState(() => _localSaved = val);
                    },
                    onChangeEnd: (val) {
                      widget.ref.read(savingsPlanRepositoryProvider).updateSavedAmount(plan.userId, plan.id, val);
                    },
                  ),
                ),
              ],
            ),
            Text(
              remains <= 0 ? '\u{1F389} Target Achieved!' : '\u20B9${remains.toStringAsFixed(0)} remaining by ${plan.targetDate.day}/${plan.targetDate.month}/${plan.targetDate.year}',
              style: AppTextStyles.labelSmall.copyWith(
                color: remains <= 0 ? AppColors.credit : AppColors.textTertiary,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
