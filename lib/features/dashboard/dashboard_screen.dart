import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/format_utils.dart';
import '../../core/constants/app_categories.dart';
import '../../shared/models/models.dart';
import '../../shared/repositories/transaction_repository.dart';
import '../../features/auth/auth_provider.dart';
import '../../features/transactions/transaction_list_screen.dart';
import '../../features/sms/sms_permission_screen.dart';
import 'package:go_router/go_router.dart';
import '../../features/sms/sms_listener_service.dart';
import '../../shared/widgets/summary_card.dart';

// â”€â”€ Monthly summary provider â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

final savingsTargetProvider = StateNotifierProvider<SavingsTargetNotifier, double>((ref) {
  return SavingsTargetNotifier();
});

class SavingsTargetNotifier extends StateNotifier<double> {
  static const _key = 'monthly_savings_target';

  SavingsTargetNotifier() : super(5000.0) {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = prefs.getDouble(_key) ?? 5000.0;
    } catch (_) {}
  }

  Future<void> setTarget(double value) async {
    state = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_key, value);
    } catch (_) {}
  }
}

final dismissedSmsTxIdsProvider = StateProvider<Set<String>>((ref) => {});

final monthlySummaryProvider =
    FutureProvider.autoDispose<MonthlySummary>((ref) async {
  final userId = ref.watch(currentUserIdProvider);
  final month = ref.watch(selectedMonthProvider);
  if (userId == null) return MonthlySummary.empty(month);

  final txs = await ref
      .watch(transactionRepositoryProvider)
      .fetchMonth(userId, month);

  double income = 0;
  double expense = 0;
  final catBreakdown = <String, double>{};

  for (final tx in txs) {
    if (tx.type == TransactionType.credit) {
      income += tx.amount;
    } else {
      expense += tx.amount;
      catBreakdown[tx.category] =
          (catBreakdown[tx.category] ?? 0) + tx.amount;
    }
  }

  return MonthlySummary(
    month: month,
    totalIncome: income,
    totalExpense: expense,
    categoryBreakdown: catBreakdown,
    transactionCount: txs.length,
  );
});

enum TrendRange {
  oneWeek,
  oneMonth,
  threeMonths,
  sixMonths,
  oneYear,
}

class TrendDataPoint {
  final String label;
  final double income;
  final double expense;

  const TrendDataPoint({
    required this.label,
    required this.income,
    required this.expense,
  });
}

final selectedTrendRangeProvider = StateProvider<TrendRange>((ref) => TrendRange.sixMonths);

final trendDataProvider = FutureProvider.autoDispose<List<TrendDataPoint>>((ref) async {
  final userId = ref.watch(currentUserIdProvider);
  final range = ref.watch(selectedTrendRangeProvider);
  if (userId == null) return [];

  final now = DateTime.now();
  final repo = ref.watch(transactionRepositoryProvider);

  switch (range) {
    case TrendRange.oneWeek:
      final start = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 6));
      final end = DateTime(now.year, now.month, now.day, 23, 59, 59);
      final txs = await repo.fetchDateRange(userId, start, end);

      final points = <TrendDataPoint>[];
      for (int i = 0; i < 7; i++) {
        final date = start.add(Duration(days: i));
        double income = 0;
        double expense = 0;
        for (final tx in txs) {
          final txDate = tx.date;
          if (txDate.year == date.year && txDate.month == date.month && txDate.day == date.day) {
            if (tx.type == TransactionType.credit) {
              income += tx.amount;
            } else {
              expense += tx.amount;
            }
          }
        }
        final weekdayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
        final label = weekdayLabels[date.weekday - 1];
        points.add(TrendDataPoint(label: label, income: income, expense: expense));
      }
      return points;

    case TrendRange.oneMonth:
      final start = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 27));
      final end = DateTime(now.year, now.month, now.day, 23, 59, 59);
      final txs = await repo.fetchDateRange(userId, start, end);

      final points = <TrendDataPoint>[];
      for (int w = 0; w < 4; w++) {
        final wStart = start.add(Duration(days: w * 7));
        final wEnd = wStart.add(const Duration(days: 6, hours: 23, minutes: 59, seconds: 59));
        double income = 0;
        double expense = 0;
        for (final tx in txs) {
          if (tx.date.isAfter(wStart.subtract(const Duration(seconds: 1))) && tx.date.isBefore(wEnd.add(const Duration(seconds: 1)))) {
            if (tx.type == TransactionType.credit) {
              income += tx.amount;
            } else {
              expense += tx.amount;
            }
          }
        }
        points.add(TrendDataPoint(label: 'W${w + 1}', income: income, expense: expense));
      }
      return points;

    case TrendRange.threeMonths:
    case TrendRange.sixMonths:
    case TrendRange.oneYear:
      final count = range == TrendRange.threeMonths ? 3 : (range == TrendRange.sixMonths ? 6 : 12);
      final points = <TrendDataPoint>[];
      
      for (int i = count - 1; i >= 0; i--) {
        final monthDate = DateTime(now.year, now.month - i, 1);
        final start = DateTime(monthDate.year, monthDate.month, 1);
        final end = DateTime(monthDate.year, monthDate.month + 1, 0, 23, 59, 59);
        final txs = await repo.fetchDateRange(userId, start, end);

        double income = 0;
        double expense = 0;
        for (final tx in txs) {
          if (tx.type == TransactionType.credit) {
            income += tx.amount;
          } else {
            expense += tx.amount;
          }
        }
        final monthNames = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
        final label = '${monthNames[start.month - 1]} ${start.year.toString().substring(2)}';
        points.add(TrendDataPoint(label: label, income: income, expense: expense));
      }
      return points;
  }
});

// â”€â”€ Screen â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  bool _showSmsPermission = false;
  static const _prefKey = 'sms_permission_asked';

  @override
  void initState() {
    super.initState();
    if (Platform.isAndroid) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _setupSms());
    }
  }

  Future<void> _setupSms() async {
    final prefs = await SharedPreferences.getInstance();
    final alreadyAsked = prefs.getBool(_prefKey) ?? false;
    final status = await Permission.sms.status;

    if (status.isGranted) {
      // Permission already granted — start listener right away
      _startSmsListener();
    } else if (!alreadyAsked) {
      // First launch — show the permission rationale screen
      if (mounted) setState(() => _showSmsPermission = true);
    }
    // Already denied before — don't ask again, user can grant via Settings
  }

  void _startSmsListener() {
    ref.read(smsListenerProvider).start();
  }

  Future<void> _onSmsGranted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, true);
    if (mounted) setState(() => _showSmsPermission = false);
    _startSmsListener();
  }

  Future<void> _onSmsDenied() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, true);
    if (mounted) setState(() => _showSmsPermission = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_showSmsPermission) {
      return SmsPermissionScreen(
        onGranted: _onSmsGranted,
        onDenied: _onSmsDenied,
      );
    }
    return const _DashboardContent();
  }
}

// ── Dashboard Content ─────────────────────────────────────────────────────────

class _DashboardContent extends ConsumerWidget {
  const _DashboardContent();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(monthlySummaryProvider);
    final trendDataAsync = ref.watch(trendDataProvider);
    final selectedMonth = ref.watch(selectedMonthProvider);
    final userAsync = ref.watch(userProfileProvider);
    final txsAsync = ref.watch(transactionsStreamProvider);
    final dismissedIds = ref.watch(dismissedSmsTxIdsProvider);

    // Find any pending SMS transaction with category 'Other' that hasn't been dismissed
    Transaction? pendingSmsTx;
    final txsList = txsAsync.value ?? [];
    for (final tx in txsList) {
      if (tx.category == 'Other' &&
          tx.source == TransactionSource.sms &&
          !dismissedIds.contains(tx.id)) {
        pendingSmsTx = tx;
        break;
      }
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          // ── App Bar ──────────────────────────────────────────
          SliverAppBar(
            expandedHeight: 120,
            backgroundColor: AppColors.background,
            floating: false,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              titlePadding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              title: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      gradient: AppColors.primaryGradient,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.android_rounded,
                        color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Text('YourCA', style: AppTextStyles.headlineMedium),
                  const Spacer(),
                  userAsync.when(
                    data: (user) => IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      icon: CircleAvatar(
                        radius: 16,
                        backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                        child: Text(
                          user != null && user.name.isNotEmpty
                              ? user.name[0].toUpperCase()
                              : 'U',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                      onPressed: () => context.pushNamed('profile'),
                    ),
                    loading: () => const SizedBox.shrink(),
                    error: (_, __) => const SizedBox.shrink(),
                  ),
                ],
              ),
              background: Container(
                decoration: BoxDecoration(
                    gradient: AppColors.backgroundGradient),
              ),
            ),
          ),

          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // Month selector
                _MonthRow(selectedMonth: selectedMonth, ref: ref),
                const SizedBox(height: 16),

                // Quick Categorization Card (if any pending SMS transaction needs category selection)
                if (pendingSmsTx != null) ...[
                  _QuickCategorizationCard(tx: pendingSmsTx),
                  const SizedBox(height: 16),
                ],

                // Summary cards / Smart Savings Hub
                summaryAsync.when(
                  data: (s) => _SummarySection(summary: s),
                  loading: () => const Center(
                      child: CircularProgressIndicator()),
                  error: (e, _) => Text('Error: $e'),
                ),
                const SizedBox(height: 24),

                // Category pie chart
                summaryAsync.when(
                  data: (s) => s.categoryBreakdown.isEmpty
                      ? const SizedBox.shrink()
                      : _CategoryChart(summary: s),
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                ),
                const SizedBox(height: 24),

                // Dynamic Trend Chart
                trendDataAsync.when(
                  data: (points) =>
                      points.isEmpty ? const SizedBox.shrink() : _BarChart(points: points),
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                ),
                const SizedBox(height: 100),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Month row ─────────────────────────────────────────────────────────────

class _MonthRow extends StatelessWidget {
  final DateTime selectedMonth;
  final WidgetRef ref;

  const _MonthRow({required this.selectedMonth, required this.ref});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final isCurrentMonth =
        selectedMonth.year == now.year && selectedMonth.month == now.month;

    return Row(
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
        Text(DateUtils2.toMonthYear(selectedMonth),
            style: AppTextStyles.headlineMedium),
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
    );
  }
}

// ── Smart Savings Hub & Summary Section ───────────────────────────────────

class _SummarySection extends ConsumerWidget {
  final MonthlySummary summary;

  const _SummarySection({required this.summary});

  static const List<String> _savingTips = [
    'Save ₹150 daily on coffee or dining out to hit your goal 4 days earlier.',
    'Review your Category chart: Shopping is high! Try cutting it by 10% next week.',
    'Put 20% of your income into savings automatically on payday to stay on track.',
    'Unsubscribe from streaming services you haven\'t used in the last 30 days.',
    'Set a shopping list before going to the supermarket to prevent impulse buying.',
    'Save money automatically by tracking your recurring subscription payments.'
  ];

  void _showEditTargetDialog(BuildContext context, WidgetRef ref, double currentTarget) {
    final controller = TextEditingController(text: currentTarget.toStringAsFixed(0));
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Set Monthly Savings Target'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Target Amount (₹)',
            hintText: 'Enter amount',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final newTarget = double.tryParse(controller.text);
              if (newTarget != null && newTarget > 0) {
                ref.read(savingsTargetProvider.notifier).setTarget(newTarget);
              }
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final target = ref.watch(savingsTargetProvider);
    final savedAmount = summary.totalIncome - summary.totalExpense;

    final progressPercent = target > 0 ? (savedAmount / target).clamp(0.0, 1.0) : 0.0;
    final isGoalAchieved = savedAmount >= target;

    final tipIndex = DateTime.now().day % _savingTips.length;
    final dailyTip = _savingTips[tipIndex];

    String statusText = '';
    if (savedAmount <= 0) {
      statusText = '⚠️ Spent more than earned. Try tracking discretionary expenses.';
    } else if (isGoalAchieved) {
      statusText = '🎉 Congratulations! You have achieved your savings target!';
    } else {
      statusText = '🎯 Keep going! You are ${(progressPercent * 100).toStringAsFixed(0)}% towards your target.';
    }

    return Column(
      children: [
        // ── Smart Savings Hub Card ──────────────────────────
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            gradient: isGoalAchieved
                ? AppColors.incomeGradient
                : AppColors.primaryGradient,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: (isGoalAchieved ? AppColors.credit : AppColors.primary)
                    .withValues(alpha: 0.25),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.track_changes_rounded, color: Colors.white, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Smart Savings Hub',
                        style: AppTextStyles.titleMedium.copyWith(
                          color: Colors.white.withValues(alpha: 0.9),
                        ),
                      ),
                    ],
                  ),
                  GestureDetector(
                    onTap: () => _showEditTargetDialog(context, ref, target),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.edit_rounded, color: Colors.white, size: 12),
                          const SizedBox(width: 4),
                          Text(
                            'Edit Target',
                            style: AppTextStyles.labelSmall.copyWith(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Current Savings',
                        style: AppTextStyles.labelSmall.copyWith(
                          color: Colors.white.withValues(alpha: 0.7),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        CurrencyUtils.format(savedAmount.clamp(0, double.infinity)),
                        style: AppTextStyles.moneyLarge.copyWith(color: Colors.white),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'Target',
                        style: AppTextStyles.labelSmall.copyWith(
                          color: Colors.white.withValues(alpha: 0.7),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        CurrencyUtils.format(target),
                        style: AppTextStyles.titleLarge.copyWith(color: Colors.white),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Progress Bar
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progressPercent,
                  backgroundColor: Colors.white.withValues(alpha: 0.2),
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                  minHeight: 6,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                statusText,
                style: AppTextStyles.bodySmall.copyWith(
                  color: Colors.white.withValues(alpha: 0.9),
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Divider(color: Colors.white24, height: 1),
              ),
              // Savings Tip section
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.lightbulb_rounded, color: Colors.amberAccent, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      dailyTip,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: SummaryCard(
                label: 'Income',
                amount: summary.totalIncome,
                icon: Icons.arrow_downward_rounded,
                color: AppColors.credit,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SummaryCard(
                label: 'Expenses',
                amount: summary.totalExpense,
                icon: Icons.arrow_upward_rounded,
                color: AppColors.debit,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// â”€â”€ Category Donut Chart â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _CategoryChart extends StatefulWidget {
  final MonthlySummary summary;

  const _CategoryChart({required this.summary});

  @override
  State<_CategoryChart> createState() => _CategoryChartState();
}

class _CategoryChartState extends State<_CategoryChart> {
  int _touchedIndex = -1;

  @override
  Widget build(BuildContext context) {
    final breakdown = widget.summary.categoryBreakdown;
    final sorted = breakdown.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final sections = sorted.asMap().entries.map((entry) {
      final i = entry.key;
      final cat = entry.value;
      final info = AppCategories.getCategory(cat.key);
      final isTouched = _touchedIndex == i;

      return PieChartSectionData(
        color: (info.color as Color).withValues(alpha: isTouched ? 1.0 : 0.8),
        value: cat.value,
        title: isTouched ? CurrencyUtils.formatCompact(cat.value) : '',
        radius: isTouched ? 80 : 64,
        titleStyle: AppTextStyles.labelSmall
            .copyWith(color: Colors.white, fontWeight: FontWeight.w700),
      );
    }).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Expense Breakdown', style: AppTextStyles.headlineSmall),
            const SizedBox(height: 20),
            SizedBox(
              height: 200,
              child: PieChart(
                PieChartData(
                  sections: sections,
                  centerSpaceRadius: 50,
                  sectionsSpace: 2,
                  pieTouchData: PieTouchData(
                    touchCallback: (event, response) {
                      setState(() {
                        _touchedIndex =
                            response?.touchedSection?.touchedSectionIndex ??
                                -1;
                      });
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Legend
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: sorted.take(6).map((cat) {
                final info = AppCategories.getCategory(cat.key);
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: info.color as Color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${info.emoji} ${cat.key}',
                      style: AppTextStyles.labelSmall,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      CurrencyUtils.formatCompact(cat.value),
                      style: AppTextStyles.labelSmall
                          .copyWith(color: AppColors.textPrimary),
                    ),
                  ],
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

// â”€â”€ 6-Month Bar Chart â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _BarChart extends ConsumerWidget {
  final List<TrendDataPoint> points;

  const _BarChart({required this.points});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedRange = ref.watch(selectedTrendRangeProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Financial Trend', style: AppTextStyles.headlineSmall),
                Row(
                  children: [
                    _LegendDot(color: AppColors.credit, label: 'In'),
                    const SizedBox(width: 8),
                    _LegendDot(color: AppColors.debit, label: 'Out'),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            
            // ── Segmented Range Selector ──────────────────────
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: TrendRange.values.map((range) {
                  final isSelected = range == selectedRange;
                  String label = '';
                  switch (range) {
                    case TrendRange.oneWeek: label = '1W'; break;
                    case TrendRange.oneMonth: label = '1M'; break;
                    case TrendRange.threeMonths: label = '3M'; break;
                    case TrendRange.sixMonths: label = '6M'; break;
                    case TrendRange.oneYear: label = '1Y'; break;
                  }

                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(label),
                      selected: isSelected,
                      onSelected: (val) {
                        if (val) {
                          ref.read(selectedTrendRangeProvider.notifier).state = range;
                        }
                      },
                      labelStyle: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isSelected
                            ? Colors.white
                            : (isDark ? Colors.white70 : Colors.black87),
                      ),
                      selectedColor: AppColors.primary,
                      backgroundColor: isDark ? AppColors.surfaceVariant : const Color(0xFFF2F2F7),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 20),

            // ── Bar Chart ─────────────────────────────────────
            SizedBox(
              height: 180,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: points.fold<double>(
                          0,
                          (max, p) => p.income > max
                              ? p.income
                              : (p.expense > max ? p.expense : max)) *
                      1.3,
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipColor: (_) => isDark ? AppColors.surface : Colors.white,
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        final point = points[group.x];
                        return BarTooltipItem(
                          '${point.label}\n',
                          AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondary),
                          children: [
                            TextSpan(
                              text: rodIndex == 0
                                  ? CurrencyUtils.formatCompact(point.income)
                                  : CurrencyUtils.formatCompact(point.expense),
                              style: AppTextStyles.labelMedium.copyWith(
                                color: rodIndex == 0 ? AppColors.credit : AppColors.debit,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  titlesData: FlTitlesData(
                    leftTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (x, meta) {
                          if (x.toInt() >= points.length || x.toInt() < 0) {
                            return const SizedBox.shrink();
                          }
                          final point = points[x.toInt()];
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              point.label.split(' ').first,
                              style: AppTextStyles.labelSmall,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  gridData: FlGridData(
                    show: true,
                    getDrawingHorizontalLine: (_) => FlLine(
                      color: (isDark ? AppColors.border : const Color(0xFFE5E5EA)).withValues(alpha: 0.5),
                      strokeWidth: 0.5,
                    ),
                    drawVerticalLine: false,
                  ),
                  borderData: FlBorderData(show: false),
                  barGroups: points.asMap().entries.map((entry) {
                    final i = entry.key;
                    final p = entry.value;
                    return BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: p.income,
                          color: AppColors.credit,
                          width: points.length > 8 ? 6 : 10,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        BarChartRodData(
                          toY: p.expense,
                          color: AppColors.debit,
                          width: points.length > 8 ? 6 : 10,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text(label, style: AppTextStyles.labelSmall),
      ],
    );
  }
}

// ── Quick Categorization Widget ──────────────────────────────────────────

class _QuickCategorizationCard extends ConsumerWidget {
  final Transaction tx;

  const _QuickCategorizationCard({required this.tx});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = AppCategories.all;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Card(
      color: AppColors.primary.withValues(alpha: 0.15),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.help_outline_rounded, color: AppColors.primary, size: 20),
                const SizedBox(width: 8),
                Text(
                  'What was this payment for?',
                  style: AppTextStyles.titleMedium.copyWith(color: AppColors.primary),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () {
                    ref.read(dismissedSmsTxIdsProvider.notifier).update((state) => {...state, tx.id});
                  },
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'A payment of ₹${tx.amount.toStringAsFixed(0)} was made to "${tx.merchant}". Select a category:',
              style: AppTextStyles.bodyMedium,
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 38,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: categories.map((cat) {
                  if (cat.name == 'Other' || cat.name == 'Income') return const SizedBox.shrink();

                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ActionChip(
                      avatar: Text(cat.emoji),
                      label: Text(cat.name),
                      onPressed: () async {
                        final updated = tx.copyWith(category: cat.name);
                        await ref.read(transactionRepositoryProvider).update(updated);
                        
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Transaction categorized as ${cat.name}'),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      },
                      labelStyle: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                      backgroundColor: isDark ? AppColors.surfaceVariant : const Color(0xFFF2F2F7),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
