import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../models/ipo_model.dart';

class AllotmentCheckerDialog extends StatefulWidget {
  final IpoItem ipo;

  const AllotmentCheckerDialog({super.key, required this.ipo});

  @override
  State<AllotmentCheckerDialog> createState() => _AllotmentCheckerDialogState();
}

class _AllotmentCheckerDialogState extends State<AllotmentCheckerDialog> {
  final TextEditingController _panController = TextEditingController();
  bool _copiedPan = false;

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (_panController.text.trim().isNotEmpty) {
      await Clipboard.setData(ClipboardData(text: _panController.text.trim()));
      setState(() => _copiedPan = true);
    }
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        await launchUrl(uri, mode: LaunchMode.platformDefault);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Opening portal: $url')),
        );
      }
    }
  }

  @override
  void dispose() {
    _panController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ipo = widget.ipo;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final isAllotmentOut = DateTime.now().isAfter(ipo.allotmentDate);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: isDark ? const Color(0xFF161C2E) : Colors.white,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header Row ────────────────────────────────────────────────
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.how_to_reg_rounded, color: AppColors.primary, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Check Allotment Status', style: AppTextStyles.titleMedium.copyWith(fontWeight: FontWeight.bold)),
                        Text(
                          ipo.name,
                          style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // ── Status Banner (Allotment Out vs Pending) ──────────────────
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: isAllotmentOut
                      ? const Color(0xFF10B981).withValues(alpha: 0.12)
                      : const Color(0xFFF59E0B).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isAllotmentOut
                        ? const Color(0xFF10B981).withValues(alpha: 0.3)
                        : const Color(0xFFF59E0B).withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      isAllotmentOut ? Icons.check_circle_rounded : Icons.pending_actions_rounded,
                      color: isAllotmentOut ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        isAllotmentOut
                            ? 'Allotment declared! Check status below.'
                            : 'Expected Allotment Date: ${_formatDate(ipo.allotmentDate)}',
                        style: TextStyle(
                          color: isAllotmentOut ? const Color(0xFF10B981) : const Color(0xFFD97706),
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // ── PAN Copy Helper TextField ─────────────────────────────────
              Text('Enter PAN (Auto-copied when opening portal):', style: AppTextStyles.labelMedium),
              const SizedBox(height: 6),
              TextField(
                controller: _panController,
                textCapitalization: TextCapitalization.characters,
                maxLength: 10,
                style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1),
                decoration: InputDecoration(
                  hintText: 'e.g. ABCDE1234F',
                  counterText: '',
                  isDense: true,
                  filled: true,
                  fillColor: isDark ? const Color(0xFF1E2638) : const Color(0xFFF1F5F9),
                  suffixIcon: _copiedPan
                      ? const Icon(Icons.check_rounded, color: Colors.green, size: 20)
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppColors.border),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // ── Primary Registrar Action ─────────────────────────────────
              Text('Official Registrar Portal:', style: AppTextStyles.labelMedium.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.business_rounded, color: AppColors.primary, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            ipo.registrarName,
                            style: AppTextStyles.titleSmall.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () => _launchUrl(ipo.registrarUrl),
                        icon: const Icon(Icons.open_in_browser_rounded, size: 18),
                        label: const Text('Open Direct Allotment Portal 🚀'),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // ── Stock Exchange & Alternative Allotment Portals ─────────────
              Text('Stock Exchanges & Alternative Links:', style: AppTextStyles.labelMedium),
              const SizedBox(height: 8),

              _PortalTile(
                title: 'BSE Official IPO Status',
                subtitle: 'Bombay Stock Exchange (BSE India)',
                icon: Icons.account_balance_rounded,
                color: const Color(0xFF2563EB),
                onTap: () => _launchUrl('https://www.bseindia.com/investors/appli_check.aspx'),
              ),
              const SizedBox(height: 8),

              _PortalTile(
                title: 'NSE Official Allotment Check',
                subtitle: 'National Stock Exchange (NSE India)',
                icon: Icons.show_chart_rounded,
                color: const Color(0xFFD97706),
                onTap: () => _launchUrl('https://www.nseindia.com/investors/check-allotment-status'),
              ),

              const SizedBox(height: 16),

              // ── All Registrars Directory ───────────────────────────────────
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text('All Major Registrars Directory', style: AppTextStyles.labelMedium.copyWith(color: AppColors.primary)),
                subtitle: Text('Link Intime, KFintech, Bigshare, Skyline', style: AppTextStyles.bodySmall.copyWith(fontSize: 11)),
                children: [
                  _PortalTile(
                    title: 'Link Intime Allotment',
                    subtitle: 'linkintime.co.in',
                    icon: Icons.link_rounded,
                    color: Colors.blue,
                    onTap: () => _launchUrl('https://linkintime.co.in/initial_offer/public-issues.html'),
                  ),
                  const SizedBox(height: 6),
                  _PortalTile(
                    title: 'KFintech Allotment Portal',
                    subtitle: 'ris.kfintech.com',
                    icon: Icons.link_rounded,
                    color: Colors.purple,
                    onTap: () => _launchUrl('https://ris.kfintech.com/ipostatus/'),
                  ),
                  const SizedBox(height: 6),
                  _PortalTile(
                    title: 'Bigshare Services Portal',
                    subtitle: 'bigshareonline.com',
                    icon: Icons.link_rounded,
                    color: Colors.teal,
                    onTap: () => _launchUrl('https://www.bigshareonline.com/ipo_status.html'),
                  ),
                  const SizedBox(height: 6),
                  _PortalTile(
                    title: 'Skyline Financial Portal',
                    subtitle: 'skylinefta.com',
                    icon: Icons.link_rounded,
                    color: Colors.orange,
                    onTap: () => _launchUrl('https://www.skylinefta.com/ipo_status.html'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }
}

class _PortalTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _PortalTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E2638) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.6)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        title: Text(title, style: AppTextStyles.labelMedium.copyWith(fontWeight: FontWeight.bold, fontSize: 13)),
        subtitle: Text(subtitle, style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary, fontSize: 10)),
        trailing: Icon(Icons.arrow_forward_ios_rounded, size: 14, color: AppColors.textSecondary),
        onTap: onTap,
      ),
    );
  }
}
