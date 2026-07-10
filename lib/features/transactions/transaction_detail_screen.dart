import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/format_utils.dart';
import '../../core/constants/app_categories.dart';
import '../../shared/models/models.dart';
import '../../shared/repositories/transaction_repository.dart';
import '../../shared/repositories/user_repository.dart';
import '../../features/auth/auth_provider.dart';

final _txDetailProvider =
    FutureProvider.autoDispose.family<Transaction?, String>((ref, txId) async {
  final userId = ref.read(currentUserIdProvider);
  if (userId == null) return null;
  return ref.read(transactionRepositoryProvider).fetchById(userId, txId);
});

class TransactionDetailScreen extends ConsumerWidget {
  final String txId;

  const TransactionDetailScreen({super.key, required this.txId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final txAsync = ref.watch(_txDetailProvider(txId));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Transaction'),
        actions: [
          txAsync.whenOrNull(
            data: (tx) => tx != null
                ? PopupMenuButton<String>(
                    color: AppColors.surface,
                    onSelected: (val) async {
                      if (val == 'edit') {
                        await context.pushNamed(
                          'addTransaction',
                          extra: tx,
                        );
                        ref.invalidate(_txDetailProvider(txId));
                      } else if (val == 'delete') {
                        _confirmDelete(context, ref, tx);
                      }
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'edit',
                        child: Row(children: [
                          Icon(Icons.edit_outlined,
                              color: AppColors.textSecondary, size: 18),
                          const SizedBox(width: 8),
                          Text('Edit', style: AppTextStyles.bodyMedium),
                        ]),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Row(children: [
                          const Icon(Icons.delete_outline_rounded,
                              color: AppColors.debit, size: 18),
                          const SizedBox(width: 8),
                          Text('Delete',
                              style: AppTextStyles.bodyMedium
                                  .copyWith(color: AppColors.debit)),
                        ]),
                      ),
                    ],
                    icon: const Icon(Icons.more_vert_rounded),
                  )
                : null,
          ) ??
              const SizedBox.shrink(),
        ],
      ),
      body: txAsync.when(
        data: (tx) => tx == null
            ? const Center(child: Text('Transaction not found'))
            : _TxDetailBody(tx: tx, ref: ref),
        loading: () =>
            const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref, Transaction tx) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete transaction?'),
        content: Text(
            'Are you sure you want to delete the ₹${tx.amount} transaction at ${tx.merchant}?'),
        actions: [
          TextButton(
              onPressed: () => ctx.pop(), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              ctx.pop();
              await ref
                  .read(transactionRepositoryProvider)
                  .delete(tx.userId, tx.id);
              if (context.mounted) context.pop();
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.debit),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

class _TxDetailBody extends ConsumerStatefulWidget {
  final Transaction tx;
  final WidgetRef ref;

  const _TxDetailBody({required this.tx, required this.ref});

  @override
  ConsumerState<_TxDetailBody> createState() => _TxDetailBodyState();
}

class _TxDetailBodyState extends ConsumerState<_TxDetailBody> {
  String? _selectedCategory;
  bool _savingCategory = false;

  @override
  void initState() {
    super.initState();
    _selectedCategory = widget.tx.category;
  }

  Future<void> _saveCategory() async {
    if (_selectedCategory == null ||
        _selectedCategory == widget.tx.category) return;

    setState(() => _savingCategory = true);
    final userId = ref.read(currentUserIdProvider) ?? '';
    final repo = ref.read(transactionRepositoryProvider);
    final userRepo = ref.read(userRepositoryProvider);

    final updated = widget.tx.copyWith(category: _selectedCategory);
    await repo.update(updated);
    await userRepo.saveMerchantCorrection(
        userId, widget.tx.merchant, _selectedCategory!);

    if (mounted) {
      setState(() => _savingCategory = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Category updated & remembered for ${widget.tx.merchant}'),
          backgroundColor: AppColors.credit,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final tx = widget.tx;
    final isDebit = tx.type == TransactionType.debit;
    final catInfo = AppCategories.getCategory(tx.category);

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // ── Hero amount card ─────────────────────────────────
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: isDebit
                ? AppColors.expenseGradient
                : AppColors.incomeGradient,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            children: [
              Text(catInfo.emoji,
                  style: const TextStyle(fontSize: 48)),
              const SizedBox(height: 12),
              Text(
                '${isDebit ? '-' : '+'}${CurrencyUtils.format(tx.amount)}',
                style: AppTextStyles.moneyLarge,
              ),
              const SizedBox(height: 4),
              Text(tx.merchant, style: AppTextStyles.titleLarge),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // ── Details ──────────────────────────────────────────
        _DetailTile(
            icon: Icons.calendar_today_outlined,
            label: 'Date',
            value: DateUtils2.toFullDate(tx.date)),
        _DetailTile(
            icon: Icons.swap_vert_rounded,
            label: 'Type',
            value: isDebit ? 'Debit / Expense' : 'Credit / Income'),
        _DetailTile(
            icon: Icons.source_outlined,
            label: 'Source',
            value: _sourceLabel(tx.source)),
        if (tx.bankReference != null)
          _DetailTile(
              icon: Icons.tag_rounded,
              label: 'Reference',
              value: tx.bankReference!),
        if (tx.note != null)
          _DetailTile(
              icon: Icons.notes_outlined,
              label: 'Note',
              value: tx.note!),
        if (tx.rawText != null) ...[
          const SizedBox(height: 8),
          _DetailTile(
              icon: Icons.sms_outlined,
              label: 'Original SMS',
              value: tx.rawText!),
        ],

        const SizedBox(height: 24),
        Divider(color: AppColors.divider),
        const SizedBox(height: 16),

        // ── Category re-assign ───────────────────────────────
        Text('Category', style: AppTextStyles.headlineSmall),
        const SizedBox(height: 6),
        Text(
          'Changing the category will be remembered for future transactions from ${tx.merchant}.',
          style: AppTextStyles.bodySmall
              .copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: AppCategories.all.map((cat) {
            final selected = _selectedCategory == cat.name;
            return GestureDetector(
              onTap: () => setState(() => _selectedCategory = cat.name),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: selected
                      ? AppColors.primaryGlow
                      : AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: selected ? AppColors.primary : AppColors.border,
                    width: selected ? 1.5 : 1,
                  ),
                ),
                child: Text(
                  '${cat.emoji} ${cat.name}',
                  style: AppTextStyles.labelMedium.copyWith(
                    color: selected
                        ? AppColors.primaryLight
                        : AppColors.textSecondary,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 20),
        if (_selectedCategory != tx.category)
          ElevatedButton.icon(
            onPressed: _savingCategory ? null : _saveCategory,
            icon: _savingCategory
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.save_rounded, size: 18),
            label: const Text('Save Category'),
          ),
        const SizedBox(height: 32),
      ],
    );
  }

  String _sourceLabel(TransactionSource source) {
    switch (source) {
      case TransactionSource.sms:
        return '📱 SMS Auto-detected';
      case TransactionSource.manual:
        return '✏️ Manually entered';
      case TransactionSource.statementImport:
        return '📄 Statement import';
      case TransactionSource.aa:
        return '🏦 Account Aggregator';
    }
  }
}

class _DetailTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _DetailTile(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.textTertiary, size: 20),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: AppTextStyles.labelMedium
                      .copyWith(color: AppColors.textSecondary)),
              const SizedBox(height: 2),
              Text(value, style: AppTextStyles.bodyMedium),
            ],
          ),
        ],
      ),
    );
  }
}
