import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../models/ipo_model.dart';
import '../providers/ipo_provider.dart';
import '../widgets/ipo_card.dart';
import '../widgets/allotment_checker_dialog.dart';

class IpoListScreen extends ConsumerStatefulWidget {
  const IpoListScreen({super.key});

  @override
  ConsumerState<IpoListScreen> createState() => _IpoListScreenState();
}

class _IpoListScreenState extends ConsumerState<IpoListScreen> {
  final TextEditingController _searchController = TextEditingController();
  bool _showSearch = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ipos = ref.watch(filteredIpoListProvider);
    final rawIpos = ref.watch(rawIpoListProvider);
    final selectedCategory = ref.watch(selectedIpoCategoryProvider);
    final selectedStatus = ref.watch(selectedIpoStatusProvider);
    final bookmarkedIds = ref.watch(bookmarkedIpoIdsProvider);

    final ongoingCount = rawIpos.where((e) => e.status == IpoStatus.ongoing).length;
    final upcomingCount = rawIpos.where((e) => e.status == IpoStatus.upcoming).length;
    final avgGmp = rawIpos.isNotEmpty
        ? (rawIpos.map((e) => e.gmpPercent).reduce((a, b) => a + b) / rawIpos.length)
        : 0.0;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: _showSearch
            ? TextField(
                controller: _searchController,
                autofocus: true,
                style: AppTextStyles.bodyLarge,
                decoration: const InputDecoration(
                  hintText: 'Search IPO by name or symbol...',
                  border: InputBorder.none,
                ),
                onChanged: (val) {
                  ref.read(ipoSearchQueryProvider.notifier).state = val;
                },
              )
            : Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      gradient: AppColors.primaryGradient,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.candlestick_chart_rounded, color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Text('IPO Tracker & Hub', style: AppTextStyles.headlineSmall),
                ],
              ),
        actions: [
          IconButton(
            tooltip: 'Check Allotment Status',
            icon: const Icon(Icons.how_to_reg_rounded, color: AppColors.primary),
            onPressed: () {
              if (rawIpos.isNotEmpty) {
                showDialog(
                  context: context,
                  builder: (ctx) => AllotmentCheckerDialog(ipo: rawIpos.first),
                );
              }
            },
          ),
          IconButton(
            icon: Icon(_showSearch ? Icons.close_rounded : Icons.search_rounded),
            onPressed: () {
              setState(() {
                _showSearch = !_showSearch;
                if (!_showSearch) {
                  _searchController.clear();
                  ref.read(ipoSearchQueryProvider.notifier).state = '';
                }
              });
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(rawIpoListProvider);
        },
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          children: [
            // ── Market Stats Hero Card ──────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.3),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Live IPO Watch',
                              style: AppTextStyles.labelMedium.copyWith(color: Colors.white70),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '$ongoingCount Active • $upcomingCount Upcoming',
                              style: AppTextStyles.titleMedium.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Column(
                          children: [
                            Text(
                              'Avg GMP',
                              style: AppTextStyles.labelSmall.copyWith(color: Colors.white70, fontSize: 10),
                            ),
                            Text(
                              '+${avgGmp.toStringAsFixed(1)}%',
                              style: AppTextStyles.labelLarge.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  InkWell(
                    onTap: () {
                      if (rawIpos.isNotEmpty) {
                        showDialog(
                          context: context,
                          builder: (ctx) => AllotmentCheckerDialog(ipo: rawIpos.first),
                        );
                      }
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.how_to_reg_rounded, color: Colors.white, size: 18),
                          SizedBox(width: 8),
                          Text(
                            'Check Allotment Status (All Registrars) 🔗',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ── Category Selector Tabs (All, Mainline, SME) ──────────────────
            Row(
              children: [
                _CategoryTab(
                  label: 'All',
                  isSelected: selectedCategory == null,
                  onTap: () {
                    ref.read(selectedIpoCategoryProvider.notifier).state = null;
                  },
                ),
                const SizedBox(width: 8),
                _CategoryTab(
                  label: 'Mainline',
                  isSelected: selectedCategory == IpoCategory.mainline,
                  onTap: () {
                    ref.read(selectedIpoCategoryProvider.notifier).state = IpoCategory.mainline;
                  },
                ),
                const SizedBox(width: 8),
                _CategoryTab(
                  label: 'SME',
                  isSelected: selectedCategory == IpoCategory.sme,
                  onTap: () {
                    ref.read(selectedIpoCategoryProvider.notifier).state = IpoCategory.sme;
                  },
                ),
              ],
            ),

            const SizedBox(height: 12),

            // ── Status Filter Chips ──────────────────────────────────────────
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _StatusChip(
                    label: 'All Status',
                    isSelected: selectedStatus == null,
                    onTap: () => ref.read(selectedIpoStatusProvider.notifier).state = null,
                  ),
                  _StatusChip(
                    label: '🟢 Live Now',
                    isSelected: selectedStatus == IpoStatus.ongoing,
                    onTap: () => ref.read(selectedIpoStatusProvider.notifier).state = IpoStatus.ongoing,
                  ),
                  _StatusChip(
                    label: '🔵 Upcoming',
                    isSelected: selectedStatus == IpoStatus.upcoming,
                    onTap: () => ref.read(selectedIpoStatusProvider.notifier).state = IpoStatus.upcoming,
                  ),
                  _StatusChip(
                    label: '🟣 Listed',
                    isSelected: selectedStatus == IpoStatus.listed,
                    onTap: () => ref.read(selectedIpoStatusProvider.notifier).state = IpoStatus.listed,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ── IPO List View ──────────────────────────────────────────────
            if (ipos.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.search_off_rounded, size: 48, color: AppColors.textSecondary),
                      const SizedBox(height: 12),
                      Text('No IPOs found', style: AppTextStyles.titleMedium),
                      const SizedBox(height: 4),
                      Text(
                        'Try adjusting your search or category filters.',
                        style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
              )
            else
              ...ipos.map((ipo) => IpoCard(
                    ipo: ipo,
                    onBookmarkToggle: () {
                      final current = ref.read(bookmarkedIpoIdsProvider);
                      final updated = Set<String>.from(current);
                      if (updated.contains(ipo.id)) {
                        updated.remove(ipo.id);
                      } else {
                        updated.add(ipo.id);
                      }
                      ref.read(bookmarkedIpoIdsProvider.notifier).state = updated;
                    },
                  )),

            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }
}

class _CategoryTab extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _CategoryTab({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primaryGlow : AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? AppColors.primary : AppColors.border,
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: AppTextStyles.labelMedium.copyWith(
                color: isSelected ? AppColors.primaryLight : AppColors.textSecondary,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _StatusChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: isSelected,
        selectedColor: AppColors.primary.withValues(alpha: 0.2),
        onSelected: (_) => onTap(),
        labelStyle: TextStyle(
          fontSize: 12,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          color: isSelected ? AppColors.primary : AppColors.textSecondary,
        ),
      ),
    );
  }
}
