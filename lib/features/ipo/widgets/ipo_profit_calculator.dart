import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../models/ipo_model.dart';

class IpoProfitCalculator extends StatefulWidget {
  final IpoItem ipo;

  const IpoProfitCalculator({super.key, required this.ipo});

  @override
  State<IpoProfitCalculator> createState() => _IpoProfitCalculatorState();
}

class _IpoProfitCalculatorState extends State<IpoProfitCalculator> {
  int _selectedLots = 1;

  final List<int> _lotPresets = [1, 2, 5, 14, 30, 68];

  @override
  Widget build(BuildContext context) {
    final ipo = widget.ipo;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final totalShares = _selectedLots * ipo.lotSize;
    final totalInvestment = totalShares * ipo.priceBandMax;
    final totalEstimatedProfit = totalShares * ipo.gmpAmount;
    final totalEstimatedValue = totalInvestment + totalEstimatedProfit;
    final returnPercent = ipo.priceBandMax > 0 ? (ipo.gmpAmount / ipo.priceBandMax) * 100 : 0.0;
    final isProfit = totalEstimatedProfit >= 0;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E2638) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.calculate_rounded, color: AppColors.primary, size: 22),
              const SizedBox(width: 8),
              Text('IPO Profit & Return Estimator', style: AppTextStyles.titleMedium),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Estimate your investment, expected listing price & returns based on current GMP.',
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),

          // ── Presets Selector Row ───────────────────────────────────────────
          Text('Select Number of Lots:', style: AppTextStyles.labelMedium),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _lotPresets.map((lots) {
                final isSelected = _selectedLots == lots;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text('$lots ${lots == 1 ? 'Lot' : 'Lots'}'),
                    selected: isSelected,
                    selectedColor: AppColors.primary,
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.white : AppColors.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                    onSelected: (selected) {
                      if (selected) {
                        setState(() => _selectedLots = lots);
                      }
                    },
                  ),
                );
              }).toList(),
            ),
          ),

          const SizedBox(height: 16),

          // ── Calculations Table Container ──────────────────────────────────
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF141A28) : Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
            ),
            child: Column(
              children: [
                _CalcRow(
                  label: 'Applied Lots / Shares',
                  value: '$_selectedLots Lot (${totalShares} Shares)',
                ),
                const Divider(height: 16),
                _CalcRow(
                  label: 'Total Investment',
                  value: '₹${totalInvestment.toStringAsFixed(0)}',
                  isBold: true,
                ),
                const Divider(height: 16),
                _CalcRow(
                  label: 'Price Band (Cut-off)',
                  value: '₹${ipo.priceBandMax.toStringAsFixed(0)}',
                ),
                const Divider(height: 16),
                _CalcRow(
                  label: 'Current GMP',
                  value: '₹${ipo.gmpAmount.toStringAsFixed(0)} (${isProfit ? '+' : ''}${returnPercent.toStringAsFixed(1)}%)',
                  valueColor: isProfit ? const Color(0xFF10B981) : Colors.red,
                ),
                const Divider(height: 16),
                _CalcRow(
                  label: 'Estimated Listing Price',
                  value: '₹${ipo.estimatedListingPrice.toStringAsFixed(0)}',
                  isBold: true,
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ── Estimated Profit Hero Result Box ──────────────────────────────
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isProfit
                    ? [const Color(0xFF059669), const Color(0xFF10B981)]
                    : [const Color(0xFFDC2626), const Color(0xFFEF4444)],
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: (isProfit ? const Color(0xFF10B981) : Colors.red).withValues(alpha: 0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Estimated Return / Profit',
                      style: AppTextStyles.labelMedium.copyWith(color: Colors.white70),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '₹${totalEstimatedProfit.abs().toStringAsFixed(0)}',
                      style: AppTextStyles.headlineMedium.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${isProfit ? '+' : ''}${returnPercent.toStringAsFixed(1)}% ROI',
                    style: AppTextStyles.labelMedium.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CalcRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isBold;
  final Color? valueColor;

  const _CalcRow({
    required this.label,
    required this.value,
    this.isBold = false,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: AppTextStyles.bodyMedium.copyWith(
            color: AppColors.textSecondary,
            fontSize: 13,
          ),
        ),
        Text(
          value,
          style: AppTextStyles.titleSmall.copyWith(
            fontSize: 13,
            fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}
