import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../shared/models/models.dart';
import '../../shared/repositories/transaction_repository.dart';
import '../../features/auth/auth_provider.dart';
import '../../features/categories/categorization_service.dart';
import '../../core/utils/format_utils.dart';
import '../../core/constants/app_categories.dart';
import 'package:uuid/uuid.dart';

class AddTransactionScreen extends ConsumerStatefulWidget {
  final Transaction? editTransaction;

  const AddTransactionScreen({super.key, this.editTransaction});

  @override
  ConsumerState<AddTransactionScreen> createState() =>
      _AddTransactionScreenState();
}

class _AddTransactionScreenState extends ConsumerState<AddTransactionScreen>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _merchantController = TextEditingController();
  final _noteController = TextEditingController();

  TransactionType _selectedType = TransactionType.debit;
  String _selectedCategory = 'Other';
  DateTime _selectedDate = DateTime.now();
  bool _isLoading = false;

  late TabController _typeTabController;

  @override
  void initState() {
    super.initState();
    _typeTabController =
        TabController(length: 2, vsync: this, initialIndex: 0);
    _typeTabController.addListener(() {
      setState(() {
        _selectedType = _typeTabController.index == 0
            ? TransactionType.debit
            : TransactionType.credit;
        if (_selectedType == TransactionType.credit) {
          _selectedCategory = 'Income';
        } else if (_selectedCategory == 'Income') {
          _selectedCategory = 'Other';
        }
      });
    });

    if (widget.editTransaction != null) {
      final tx = widget.editTransaction!;
      _amountController.text = tx.amount.toString();
      _merchantController.text = tx.merchant;
      _noteController.text = tx.note ?? '';
      _selectedType = tx.type;
      _selectedCategory = tx.category;
      _selectedDate = tx.date;
      _typeTabController.index =
          tx.type == TransactionType.debit ? 0 : 1;
    }

    // Auto-categorize on merchant change
    _merchantController.addListener(() {
      if (_merchantController.text.isNotEmpty) {
        final category = CategorizationService.instance
            .categorize(_merchantController.text);
        if (category != 'Other') {
          setState(() => _selectedCategory = category);
        }
      }
    });
  }

  @override
  void dispose() {
    _amountController.dispose();
    _merchantController.dispose();
    _noteController.dispose();
    _typeTabController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: AppColors.primary,
            surface: AppColors.surface,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    final userId = ref.read(currentUserIdProvider) ?? '';
    final repo = ref.read(transactionRepositoryProvider);

    final tx = Transaction(
      id: widget.editTransaction?.id ?? const Uuid().v4(),
      userId: userId,
      amount: double.parse(_amountController.text.trim()),
      type: _selectedType,
      category: _selectedCategory,
      merchant: _merchantController.text.trim(),
      date: _selectedDate,
      source: widget.editTransaction?.source ?? TransactionSource.manual,
      createdAt: widget.editTransaction?.createdAt ?? DateTime.now(),
      note: _noteController.text.trim().isEmpty
          ? null
          : _noteController.text.trim(),
    );

    try {
      if (widget.editTransaction != null) {
        await repo.update(tx);
      } else {
        await repo.add(tx);
      }
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error: $e'),
              backgroundColor: AppColors.debit),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.editTransaction != null;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(isEdit ? 'Edit Transaction' : 'Add Transaction'),
        backgroundColor: AppColors.background,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // ── Type selector ──────────────────────────────────────
            _buildTypeSelector(),
            const SizedBox(height: 24),

            // ── Amount ────────────────────────────────────────────
            _buildAmountField(),
            const SizedBox(height: 16),

            // ── Merchant ──────────────────────────────────────────
            TextFormField(
              controller: _merchantController,
              style: AppTextStyles.bodyLarge,
              decoration: const InputDecoration(
                labelText: 'Merchant / Payee',
                prefixIcon: Icon(Icons.storefront_outlined),
              ),
              validator: (v) =>
                  v == null || v.isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 16),

            // ── Category picker ───────────────────────────────────
            _buildCategoryPicker(),
            const SizedBox(height: 16),

            // ── Date picker ───────────────────────────────────────
            _buildDatePicker(),
            const SizedBox(height: 16),

            // ── Note ──────────────────────────────────────────────
            TextFormField(
              controller: _noteController,
              style: AppTextStyles.bodyLarge,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Note (optional)',
                prefixIcon: Icon(Icons.notes_outlined),
              ),
            ),
            const SizedBox(height: 32),

            // ── Save button ───────────────────────────────────────
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _save,
                child: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : Text(isEdit ? 'Update' : 'Add Transaction'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeSelector() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: TabBar(
        controller: _typeTabController,
        indicator: BoxDecoration(
          gradient: _selectedType == TransactionType.debit
              ? AppColors.expenseGradient
              : AppColors.incomeGradient,
          borderRadius: BorderRadius.circular(12),
        ),
        dividerColor: Colors.transparent,
        labelStyle: AppTextStyles.titleMedium,
        unselectedLabelColor: AppColors.textSecondary,
        tabs: const [
          Tab(text: '↑  Debit / Expense'),
          Tab(text: '↓  Credit / Income'),
        ],
      ),
    );
  }

  Widget _buildAmountField() {
    final color = _selectedType == TransactionType.debit
        ? AppColors.debit
        : AppColors.credit;
    return TextFormField(
      controller: _amountController,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: AppTextStyles.moneyMedium.copyWith(color: color),
      decoration: InputDecoration(
        labelText: 'Amount',
        prefixText: '₹  ',
        prefixStyle: AppTextStyles.bodyLarge.copyWith(color: color),
        prefixIcon: Icon(Icons.currency_rupee_rounded, color: color),
      ),
      validator: (v) {
        if (v == null || v.isEmpty) return 'Enter an amount';
        if (double.tryParse(v) == null) return 'Enter a valid number';
        if (double.parse(v) <= 0) return 'Amount must be positive';
        return null;
      },
    );
  }

  Widget _buildCategoryPicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Category', style: AppTextStyles.labelLarge
            .copyWith(color: AppColors.textSecondary)),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: AppCategories.all
              .where((c) =>
                  _selectedType == TransactionType.credit ||
                  c.name != 'Income')
              .map((cat) {
            final selected = _selectedCategory == cat.name;
            return GestureDetector(
              onTap: () => setState(() => _selectedCategory = cat.name),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 8),
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
      ],
    );
  }

  Widget _buildDatePicker() {
    return GestureDetector(
      onTap: _pickDate,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            const Icon(Icons.calendar_month_outlined,
                color: AppColors.textSecondary),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Date',
                    style: AppTextStyles.labelMedium
                        .copyWith(color: AppColors.textSecondary)),
                Text(
                  DateUtils2.toFullDate(_selectedDate),
                  style: AppTextStyles.bodyMedium,
                ),
              ],
            ),
            const Spacer(),
            const Icon(Icons.chevron_right_rounded,
                color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}
