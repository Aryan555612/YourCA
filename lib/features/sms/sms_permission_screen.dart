import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';

/// Shows a transparent rationale screen before requesting SMS permissions.
/// Only shown on Android.
class SmsPermissionScreen extends ConsumerStatefulWidget {
  final VoidCallback onGranted;
  final VoidCallback onDenied;

  const SmsPermissionScreen({
    super.key,
    required this.onGranted,
    required this.onDenied,
  });

  @override
  ConsumerState<SmsPermissionScreen> createState() =>
      _SmsPermissionScreenState();
}

class _SmsPermissionScreenState extends ConsumerState<SmsPermissionScreen> {
  bool _isRequesting = false;

  Future<void> _requestPermission() async {
    setState(() => _isRequesting = true);

    final statuses = await [
      Permission.sms,
      Permission.phone,
    ].request();

    final smsGranted = statuses[Permission.sms]?.isGranted ?? false;

    if (smsGranted) {
      widget.onGranted();
    } else {
      setState(() => _isRequesting = false);
      if (statuses[Permission.sms]?.isPermanentlyDenied ?? false) {
        // Guide user to settings
        await openAppSettings();
      } else {
        widget.onDenied();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Icon(Icons.sms_outlined,
                    color: Colors.white, size: 40),
              ),
              const SizedBox(height: 24),
              Text('Enable SMS Reading', style: AppTextStyles.displaySmall),
              const SizedBox(height: 12),
              Text(
                'YourCA can automatically detect bank transactions from your SMS messages.',
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyLarge
                    .copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 32),
              // Feature list
              ...[
                _FeatureItem(
                  icon: Icons.auto_awesome_rounded,
                  title: 'Automatic tracking',
                  desc: 'New bank SMS alerts are instantly recorded',
                ),
                _FeatureItem(
                  icon: Icons.lock_outline_rounded,
                  title: 'Your data stays on device',
                  desc:
                      'SMS content is processed locally. Only transaction data is saved.',
                ),
                _FeatureItem(
                  icon: Icons.block_rounded,
                  title: 'We never read personal SMS',
                  desc:
                      'Only SMS from known bank sender IDs are processed.',
                ),
              ],
              const SizedBox(height: 40),
              ElevatedButton(
                onPressed: _isRequesting ? null : _requestPermission,
                child: _isRequesting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('Allow SMS Access'),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: widget.onDenied,
                child: const Text('Skip for now'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeatureItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String desc;

  const _FeatureItem(
      {required this.icon, required this.title, required this.desc});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.primaryGlow,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: AppColors.primaryLight, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTextStyles.titleSmall
                    .copyWith(color: AppColors.textPrimary)),
                const SizedBox(height: 2),
                Text(desc,
                    style: AppTextStyles.bodySmall
                        .copyWith(color: AppColors.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
