import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../models/ipo_model.dart';
import '../providers/ipo_provider.dart';
import '../widgets/ipo_profit_calculator.dart';
import '../widgets/allotment_checker_dialog.dart';

class IpoDetailScreen extends ConsumerWidget {
  final String ipoId;

  const IpoDetailScreen({super.key, required this.ipoId});

  String _formatDate(DateTime dt) {
    return DateFormat('dd MMM yyyy').format(dt);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allIpos = ref.watch(rawIpoListProvider);
    final ipo = allIpos.firstWhere(
      (e) => e.id == ipoId,
      orElse: () => allIpos.first,
    );

    final hasPositiveGmp = ipo.gmpAmount >= 0;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Text(ipo.symbol, style: AppTextStyles.headlineSmall),
        actions: [
          IconButton(
            icon: Icon(
              ipo.isBookmarked ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
              color: ipo.isBookmarked ? AppColors.primary : AppColors.textSecondary,
            ),
            onPressed: () {
              final current = ref.read(bookmarkedIpoIdsProvider);
              final updated = Set<String>.from(current);
              if (updated.contains(ipo.id)) {
                updated.remove(ipo.id);
              } else {
                updated.add(ipo.id);
              }
              ref.read(bookmarkedIpoIdsProvider.notifier).state = updated;
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Hero IPO Header Card ──────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Center(
                        child: Text(ipo.logoEmoji, style: const TextStyle(fontSize: 28)),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            ipo.name,
                            style: AppTextStyles.headlineSmall.copyWith(color: Colors.white),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${ipo.category == IpoCategory.mainline ? "Mainline NSE & BSE" : "SME Platform"} • ${ipo.sector}',
                            style: AppTextStyles.bodySmall.copyWith(color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Price Band', style: AppTextStyles.labelSmall.copyWith(color: Colors.white70)),
                          const SizedBox(height: 2),
                          Text(
                            '₹${ipo.priceBandMin.toStringAsFixed(0)} - ₹${ipo.priceBandMax.toStringAsFixed(0)}',
                            style: AppTextStyles.titleMedium.copyWith(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Lot Size', style: AppTextStyles.labelSmall.copyWith(color: Colors.white70)),
                          const SizedBox(height: 2),
                          Text(
                            '${ipo.lotSize} Shares',
                            style: AppTextStyles.titleMedium.copyWith(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Issue Size', style: AppTextStyles.labelSmall.copyWith(color: Colors.white70)),
                          const SizedBox(height: 2),
                          Text(
                            '₹${ipo.issueSizeCr.toStringAsFixed(0)} Cr',
                            style: AppTextStyles.titleMedium.copyWith(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ── GMP Highlights Banner ──────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Icon(
                  hasPositiveGmp ? Icons.local_fire_department_rounded : Icons.trending_down_rounded,
                  color: hasPositiveGmp ? const Color(0xFF10B981) : Colors.red,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Grey Market Premium (GMP)', style: AppTextStyles.labelMedium.copyWith(color: AppColors.textSecondary)),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text(
                            '₹${ipo.gmpAmount.toStringAsFixed(0)} ',
                            style: AppTextStyles.headlineSmall.copyWith(
                              color: hasPositiveGmp ? const Color(0xFF10B981) : Colors.red,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '(${hasPositiveGmp ? '+' : ''}${ipo.gmpPercent.toStringAsFixed(1)}%)',
                            style: AppTextStyles.titleMedium.copyWith(
                              color: hasPositiveGmp ? const Color(0xFF10B981) : Colors.red,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('Est. Listing Price', style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondary)),
                    const SizedBox(height: 2),
                    Text(
                      '₹${ipo.estimatedListingPrice.toStringAsFixed(0)}',
                      style: AppTextStyles.titleLarge.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // ── Subscription Status Section ──────────────────────────────────
          _SectionHeader(icon: Icons.pie_chart_outline_rounded, title: 'Live Subscription Status'),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                _SubRow(category: 'Qualified Institutional (QIB)', times: ipo.subscription.qib),
                const Divider(height: 16),
                _SubRow(category: 'Non-Institutional (NII / HNI)', times: ipo.subscription.nii),
                const Divider(height: 16),
                _SubRow(category: 'Retail Individual (RII)', times: ipo.subscription.retail),
                if (ipo.subscription.employee != null) ...[
                  const Divider(height: 16),
                  _SubRow(category: 'Employees', times: ipo.subscription.employee!),
                ],
                const Divider(height: 16),
                _SubRow(category: 'Total Subscription', times: ipo.subscription.total, isTotal: true),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // ── IPO Timeline Stepper ──────────────────────────────────────────
          _SectionHeader(icon: Icons.timeline_rounded, title: 'IPO Important Timeline Dates'),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                _TimelineStep(label: 'Offer Bidding Opens', date: _formatDate(ipo.openDate), isCompleted: DateTime.now().isAfter(ipo.openDate)),
                _TimelineStep(label: 'Offer Bidding Closes', date: _formatDate(ipo.closeDate), isCompleted: DateTime.now().isAfter(ipo.closeDate)),
                _TimelineStep(label: 'Allotment Finalization', date: _formatDate(ipo.allotmentDate), isCompleted: DateTime.now().isAfter(ipo.allotmentDate)),
                _TimelineStep(label: 'Initiation of Refunds', date: _formatDate(ipo.refundDate), isCompleted: DateTime.now().isAfter(ipo.refundDate)),
                _TimelineStep(label: 'Listing on Exchanges', date: _formatDate(ipo.listingDate), isCompleted: DateTime.now().isAfter(ipo.listingDate), isLast: true),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // ── Interactive Profit & Return Estimator ─────────────────────────
          IpoProfitCalculator(ipo: ipo),

          const SizedBox(height: 24),

          // ── Company Financial Highlights ──────────────────────────────────
          _SectionHeader(icon: Icons.account_balance_wallet_outlined, title: 'Financial Summary (₹ in Cr)'),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.border),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columnSpacing: 24,
                columns: const [
                  DataColumn(label: Text('Metric')),
                  DataColumn(label: Text('FY22')),
                  DataColumn(label: Text('FY23')),
                  DataColumn(label: Text('FY24')),
                ],
                rows: [
                  DataRow(cells: [
                    const DataCell(Text('Revenue')),
                    ...ipo.financials.map((f) => DataCell(Text(f.revenueCr.toStringAsFixed(1)))),
                  ]),
                  DataRow(cells: [
                    const DataCell(Text('PAT / Profit')),
                    ...ipo.financials.map((f) => DataCell(Text(f.patCr.toStringAsFixed(1)))),
                  ]),
                  DataRow(cells: [
                    const DataCell(Text('Net Worth')),
                    ...ipo.financials.map((f) => DataCell(Text(f.netWorthCr.toStringAsFixed(1)))),
                  ]),
                  DataRow(cells: [
                    const DataCell(Text('Total Assets')),
                    ...ipo.financials.map((f) => DataCell(Text(f.assetsCr.toStringAsFixed(1)))),
                  ]),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // ── Key Valuation KPIs ─────────────────────────────────────────────
          _SectionHeader(icon: Icons.analytics_outlined, title: 'Key Financial Ratios & Valuations'),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                _KpiBox(label: 'P/E Ratio', value: ipo.peRatio > 0 ? ipo.peRatio.toStringAsFixed(1) : 'N/A'),
                _KpiBox(label: 'EPS (₹)', value: ipo.eps.toStringAsFixed(2)),
                _KpiBox(label: 'RoNW', value: '${ipo.ronw.toStringAsFixed(1)}%'),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // ── About Company & Objects of Issue ──────────────────────────────
          _SectionHeader(icon: Icons.info_outline_rounded, title: 'About Company & Issue Objects'),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(ipo.about, style: AppTextStyles.bodyMedium),
                const SizedBox(height: 14),
                Text('Objects of the Issue:', style: AppTextStyles.titleSmall),
                const SizedBox(height: 6),
                ...ipo.objectsOfIssue.map((obj) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('• ', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary)),
                          Expanded(child: Text(obj, style: AppTextStyles.bodySmall)),
                        ],
                      ),
                    )),
              ],
            ),
          ),

          const SizedBox(height: 100),
        ],
      ),
      bottomSheet: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: SafeArea(
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (ctx) => AllotmentCheckerDialog(ipo: ipo),
                );
              },
              icon: const Icon(Icons.verified_user_rounded, size: 20),
              label: const Text('Check Allotment Status'),
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;

  const _SectionHeader({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: AppColors.primary),
        const SizedBox(width: 8),
        Text(title, style: AppTextStyles.headlineSmall),
      ],
    );
  }
}

class _SubRow extends StatelessWidget {
  final String category;
  final double times;
  final bool isTotal;

  const _SubRow({
    required this.category,
    required this.times,
    this.isTotal = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          category,
          style: isTotal
              ? AppTextStyles.titleMedium.copyWith(fontWeight: FontWeight.bold)
              : AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
        ),
        Text(
          '${times.toStringAsFixed(2)}x',
          style: isTotal
              ? AppTextStyles.titleMedium.copyWith(fontWeight: FontWeight.bold, color: AppColors.primary)
              : AppTextStyles.labelLarge.copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

class _TimelineStep extends StatelessWidget {
  final String label;
  final String date;
  final bool isCompleted;
  final bool isLast;

  const _TimelineStep({
    required this.label,
    required this.date,
    this.isCompleted = false,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Column(
          children: [
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isCompleted ? AppColors.primary : AppColors.surfaceVariant,
                border: Border.all(color: isCompleted ? AppColors.primary : AppColors.border, width: 2),
              ),
              child: isCompleted
                  ? const Icon(Icons.check_rounded, size: 12, color: Colors.white)
                  : null,
            ),
            if (!isLast)
              Container(
                width: 2,
                height: 24,
                color: isCompleted ? AppColors.primary : AppColors.border,
              ),
          ],
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(label, style: AppTextStyles.bodyMedium.copyWith(fontWeight: isCompleted ? FontWeight.bold : FontWeight.normal)),
                Text(date, style: AppTextStyles.labelMedium.copyWith(color: AppColors.textSecondary)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _KpiBox extends StatelessWidget {
  final String label;
  final String value;

  const _KpiBox({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(label, style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: 4),
          Text(value, style: AppTextStyles.titleMedium.copyWith(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
