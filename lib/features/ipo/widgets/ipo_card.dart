import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../models/ipo_model.dart';
import 'allotment_checker_dialog.dart';

class IpoCard extends StatelessWidget {
  final IpoItem ipo;
  final VoidCallback? onBookmarkToggle;

  const IpoCard({
    super.key,
    required this.ipo,
    this.onBookmarkToggle,
  });

  String _formatDate(DateTime dt) {
    return DateFormat('d MMM').format(dt);
  }

  Color _getStatusColor(IpoStatus status) {
    switch (status) {
      case IpoStatus.ongoing:
        return const Color(0xFF10B981); // Emerald Green
      case IpoStatus.upcoming:
        return const Color(0xFF3B82F6); // Electric Blue
      case IpoStatus.closed:
        return const Color(0xFFF59E0B); // Amber
      case IpoStatus.listed:
        return const Color(0xFF8B5CF6); // Purple
    }
  }

  String _getStatusText(IpoStatus status) {
    switch (status) {
      case IpoStatus.ongoing:
        return 'LIVE NOW';
      case IpoStatus.upcoming:
        return 'UPCOMING';
      case IpoStatus.closed:
        return 'CLOSED';
      case IpoStatus.listed:
        return 'LISTED';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final statusColor = _getStatusColor(ipo.status);
    final hasPositiveGmp = ipo.gmpAmount >= 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF161C2E) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.06),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: InkWell(
        onTap: () => context.pushNamed('ipoDetail', pathParameters: {'ipoId': ipo.id}),
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Top Header Row: Logo, Name, Category & Status Badge ─────────
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                    ),
                    child: Center(
                      child: Text(
                        ipo.logoEmoji,
                        style: const TextStyle(fontSize: 24),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                ipo.name,
                                style: AppTextStyles.titleMedium.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: (ipo.category == IpoCategory.mainline
                                        ? AppColors.primary
                                        : Colors.amber)
                                    .withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                ipo.category == IpoCategory.mainline ? 'MAINLINE' : 'SME',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: ipo.category == IpoCategory.mainline
                                      ? AppColors.primary
                                      : Colors.amber.shade800,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                ipo.sector,
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: AppColors.textSecondary,
                                  fontSize: 11,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: statusColor.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: statusColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _getStatusText(ipo.status),
                          style: TextStyle(
                            color: statusColor,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 14),

              // ── GMP Banner (Grey Market Premium) ───────────────────────────
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: hasPositiveGmp
                        ? [
                            const Color(0xFF059669).withValues(alpha: 0.15),
                            const Color(0xFF10B981).withValues(alpha: 0.08),
                          ]
                        : [
                            const Color(0xFFDC2626).withValues(alpha: 0.15),
                            const Color(0xFFEF4444).withValues(alpha: 0.08),
                          ],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: hasPositiveGmp
                        ? const Color(0xFF10B981).withValues(alpha: 0.3)
                        : const Color(0xFFEF4444).withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      hasPositiveGmp ? Icons.local_fire_department_rounded : Icons.trending_down_rounded,
                      size: 18,
                      color: hasPositiveGmp ? const Color(0xFF10B981) : Colors.red,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'GMP: ',
                      style: AppTextStyles.labelMedium.copyWith(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      '₹${ipo.gmpAmount.toStringAsFixed(0)} ',
                      style: AppTextStyles.labelLarge.copyWith(
                        fontWeight: FontWeight.bold,
                        color: hasPositiveGmp ? const Color(0xFF10B981) : Colors.red,
                      ),
                    ),
                    Text(
                      '(${hasPositiveGmp ? '+' : ''}${ipo.gmpPercent.toStringAsFixed(1)}%)',
                      style: AppTextStyles.labelMedium.copyWith(
                        fontWeight: FontWeight.bold,
                        color: hasPositiveGmp ? const Color(0xFF10B981) : Colors.red,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      'Est. Listing: ₹${ipo.estimatedListingPrice.toStringAsFixed(0)}',
                      style: AppTextStyles.bodySmall.copyWith(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // ── Key Metrics Grid (Price Band, Lot, Size, Sub) ──────────────
              Row(
                children: [
                  _MetricColumn(
                    label: 'Price Band',
                    value: '₹${ipo.priceBandMin.toStringAsFixed(0)} - ₹${ipo.priceBandMax.toStringAsFixed(0)}',
                  ),
                  _MetricColumn(
                    label: 'Lot Size',
                    value: '${ipo.lotSize} Shares',
                    subValue: 'Min ₹${(ipo.minInvestment).toStringAsFixed(0)}',
                  ),
                  _MetricColumn(
                    label: 'Issue Size',
                    value: '₹${ipo.issueSizeCr.toStringAsFixed(0)} Cr',
                  ),
                  _MetricColumn(
                    label: 'Subscribed',
                    value: ipo.subscription.total > 0
                        ? '${ipo.subscription.total}x'
                        : 'N/A',
                    isHighlight: ipo.subscription.total > 5,
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // ── Bottom Dates & Action Bar ─────────────────────────────────
              Row(
                children: [
                  Icon(Icons.date_range_rounded, size: 14, color: AppColors.textSecondary),
                  const SizedBox(width: 4),
                  Text(
                    '${_formatDate(ipo.openDate)} - ${_formatDate(ipo.closeDate)}',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                  const Spacer(),
                  if (onBookmarkToggle != null)
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      icon: Icon(
                        ipo.isBookmarked ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                        size: 20,
                        color: ipo.isBookmarked ? AppColors.primary : AppColors.textSecondary,
                      ),
                      onPressed: onBookmarkToggle,
                    ),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: () {
                      showDialog(
                        context: context,
                        builder: (ctx) => AllotmentCheckerDialog(ipo: ipo),
                      );
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.verified_user_outlined, size: 14, color: AppColors.primary),
                          const SizedBox(width: 4),
                          Text(
                            'Check Allotment',
                            style: AppTextStyles.labelSmall.copyWith(
                              color: AppColors.primary,
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
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

class _MetricColumn extends StatelessWidget {
  final String label;
  final String value;
  final String? subValue;
  final bool isHighlight;

  const _MetricColumn({
    required this.label,
    required this.value,
    this.subValue,
    this.isHighlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTextStyles.labelSmall.copyWith(
              color: AppColors.textSecondary,
              fontSize: 10,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: AppTextStyles.labelMedium.copyWith(
              fontWeight: FontWeight.bold,
              fontSize: 11,
              color: isHighlight ? AppColors.primary : null,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (subValue != null) ...[
            const SizedBox(height: 1),
            Text(
              subValue!,
              style: AppTextStyles.labelSmall.copyWith(
                color: AppColors.textSecondary,
                fontSize: 9,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}
