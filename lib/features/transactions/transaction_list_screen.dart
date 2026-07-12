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
import 'dart:io';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';

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
            onPressed: () => _showExportDialog(context, ref),
            icon: const Icon(Icons.download_rounded),
            tooltip: 'Export CSV',
          ),
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
                  return RefreshIndicator(
                    onRefresh: () async {
                      ref.invalidate(transactionsStreamProvider);
                    },
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        SizedBox(
                          height: MediaQuery.of(context).size.height * 0.6,
                          child: _EmptyState(hasFilter: categoryFilter != null),
                        ),
                      ],
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(transactionsStreamProvider);
                  },
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
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
                  ),
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

  String _getSourceLabel(TransactionSource source) {
    switch (source) {
      case TransactionSource.sms:
        return 'Auto';
      case TransactionSource.manual:
        return 'Manual';
      case TransactionSource.statementImport:
        return 'Statement';
      case TransactionSource.aa:
        return 'Bank';
    }
  }

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
                      '${catInfo.emoji} ${tx.category}  •  ${_getSourceLabel(tx.source)}',
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

void _showExportDialog(BuildContext context, WidgetRef ref) {
  showDialog(
    context: context,
    builder: (context) => const _ExportDialog(),
  );
}

class _ExportDialog extends ConsumerStatefulWidget {
  const _ExportDialog();

  @override
  ConsumerState<_ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends ConsumerState<_ExportDialog> {
  bool _isByMonth = true;
  late DateTime _selectedMonth;
  late DateTime _startDate;
  late DateTime _endDate;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedMonth = DateTime(now.year, now.month, 1);
    _startDate = DateTime(now.year, now.month, 1);
    _endDate = DateTime(now.year, now.month, now.day);
  }

  Future<void> _selectStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        _startDate = picked;
        if (_startDate.isAfter(_endDate)) {
          _endDate = _startDate;
        }
      });
    }
  }

  Future<void> _selectEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate,
      firstDate: _startDate,
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        _endDate = picked;
      });
    }
  }

  Future<void> _export() async {
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return;

    setState(() => _isLoading = true);

    try {
      DateTime start;
      DateTime end;

      if (_isByMonth) {
        start = DateTime(_selectedMonth.year, _selectedMonth.month, 1);
        end = DateTime(_selectedMonth.year, _selectedMonth.month + 1, 0, 23, 59, 59);
      } else {
        start = DateTime(_startDate.year, _startDate.month, _startDate.day);
        end = DateTime(_endDate.year, _endDate.month, _endDate.day, 23, 59, 59);
      }

      final repo = ref.read(transactionRepositoryProvider);
      final txs = await repo.fetchDateRange(userId, start, end);

      if (txs.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('No transactions found in the selected range.'),
              backgroundColor: AppColors.debit,
            ),
          );
        }
        setState(() => _isLoading = false);
        return;
      }

      // Generate Text Report
      final buffer = StringBuffer();
      buffer.writeln('==================================================');
      buffer.writeln('              YourCA TRANSACTION REPORT           ');
      buffer.writeln('==================================================');
      buffer.writeln('Date Range: ${DateFormat('dd-MMM-yyyy').format(start)} to ${DateFormat('dd-MMM-yyyy').format(end)}');
      buffer.writeln('Generated At: ${DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now())}');
      buffer.writeln('Total Transactions: ${txs.length}');
      buffer.writeln('--------------------------------------------------\n');

      int index = 1;
      for (final tx in txs) {
        final prefix = tx.type == TransactionType.credit ? '+' : '-';
        buffer.writeln('$index. MERCHANT: ${tx.merchant}');
        buffer.writeln('   Date: ${DateFormat('yyyy-MM-dd HH:mm:ss').format(tx.date)}');
        buffer.writeln('   Amount: $prefix\u20B9${tx.amount.toStringAsFixed(2)}');
        buffer.writeln('   Category: ${tx.category}');
        buffer.writeln('   Reference: ${tx.bankReference ?? "-"}');
        buffer.writeln('   Note: ${tx.note ?? "-"}');
        buffer.writeln('\n--------------------------------------------------\n');
        index++;
      }

      final textData = buffer.toString();

      // Save file to Downloads folder
      Directory? directory;
      if (Platform.isAndroid) {
        directory = await getDownloadsDirectory();
      }
      directory ??= await getApplicationDocumentsDirectory();

      final dateStr = _isByMonth
          ? DateFormat('yyyy_MM').format(_selectedMonth)
          : '${DateFormat('yyyy-MM-dd').format(start)}_to_${DateFormat('yyyy-MM-dd').format(end)}';
      final filename = 'YourCA_export_$dateStr.txt';
      final file = File('${directory.path}/$filename');
      await file.writeAsString(textData);

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✔ Saved Text report to phone storage: $filename'),
            backgroundColor: AppColors.primary,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error exporting file: $e'),
            backgroundColor: AppColors.debit,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final monthsList = List.generate(12, (index) {
      final now = DateTime.now();
      return DateTime(now.year, now.month - index, 1);
    });

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.download_for_offline_rounded, color: AppColors.primary, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Export Transactions',
                    style: AppTextStyles.headlineSmall.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            
            // Segmented/Radio controls
            Row(
              children: [
                Expanded(
                  child: ChoiceChip(
                    label: const Center(child: Text('By Month')),
                    selected: _isByMonth,
                    onSelected: (val) {
                      if (val) setState(() => _isByMonth = true);
                    },
                    selectedColor: AppColors.primary,
                    labelStyle: TextStyle(
                      color: _isByMonth ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ChoiceChip(
                    label: const Center(child: Text('Custom Range')),
                    selected: !_isByMonth,
                    onSelected: (val) {
                      if (val) setState(() => _isByMonth = false);
                    },
                    selectedColor: AppColors.primary,
                    labelStyle: TextStyle(
                      color: !_isByMonth ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            if (_isByMonth) ...[
              Text('Select Month', style: AppTextStyles.titleMedium),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey[900] : Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<DateTime>(
                    value: _selectedMonth,
                    isExpanded: true,
                    dropdownColor: AppColors.surface,
                    items: monthsList.map((date) {
                      return DropdownMenuItem<DateTime>(
                        value: date,
                        child: Text(DateFormat('MMMM yyyy').format(date)),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _selectedMonth = val);
                      }
                    },
                  ),
                ),
              ),
            ] else ...[
              Text('Select Custom Date Range', style: AppTextStyles.titleMedium),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _selectStartDate,
                      icon: const Icon(Icons.date_range_rounded, size: 16),
                      label: Text(
                        DateFormat('dd-MMM-yyyy').format(_startDate),
                        style: const TextStyle(fontSize: 12),
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text('to'),
                  ),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _selectEndDate,
                      icon: const Icon(Icons.date_range_rounded, size: 16),
                      label: Text(
                        DateFormat('dd-MMM-yyyy').format(_endDate),
                        style: const TextStyle(fontSize: 12),
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 32),

            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: _isLoading ? null : _export,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    minimumSize: const Size(120, 48), // Explicitly override the global theme's double.infinity width
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : Text(
                          'Download TXT',
                          style: AppTextStyles.labelLarge.copyWith(color: Colors.white),
                        ),
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
