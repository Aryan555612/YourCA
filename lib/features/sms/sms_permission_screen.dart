import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';

/// Shows a transparent rationale screen before requesting SMS permissions.
/// Only shown on Android (sideloaded APK version).
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

enum _PermissionState { initial, denied, permanentlyDenied }

class _SmsPermissionScreenState extends ConsumerState<SmsPermissionScreen> {
  bool _isRequesting = false;
  _PermissionState _state = _PermissionState.initial;

  Future<void> _requestPermission() async {
    setState(() => _isRequesting = true);

    final statuses = await [
      Permission.sms,
      Permission.phone,
      Permission.notification,
    ].request();

    final smsStatus = statuses[Permission.sms] ?? PermissionStatus.denied;

    if (smsStatus.isGranted) {
      widget.onGranted();
      return;
    }

    if (smsStatus.isPermanentlyDenied) {
      setState(() {
        _isRequesting = false;
        _state = _PermissionState.permanentlyDenied;
      });
    } else {
      setState(() {
        _isRequesting = false;
        _state = _PermissionState.denied;
      });
    }
  }

  Future<void> _openSettings() async {
    await openAppSettings();
    // Re-check after returning from settings
    final status = await Permission.sms.status;
    if (status.isGranted && mounted) {
      widget.onGranted();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPermanent = _state == _PermissionState.permanentlyDenied;
    final isDenied = _state == _PermissionState.denied;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Icon
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.35),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: const Icon(Icons.sms_outlined,
                    color: Colors.white, size: 42),
              ),
              const SizedBox(height: 28),

              // Title
              Text(
                isPermanent ? 'Sync Access Blocked' : 'Secure Account Sync',
                style: AppTextStyles.displaySmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),

              // Subtitle — changes based on state
              Text(
                isPermanent
                    ? 'Sync permission was permanently denied. Please open Settings and enable it under App Permissions → SMS.'
                    : isDenied
                        ? 'Sync access was denied. Tap below to try again — YourCA needs this permission to securely sync details.'
                        : 'YourCA automatically synchronizes and updates your transaction details securely on this device.',
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyLarge
                    .copyWith(color: AppColors.textSecondary, height: 1.5),
              ),
              const SizedBox(height: 36),

              // Feature bullets — only on initial state
              if (_state == _PermissionState.initial) ...[
                const _FeatureItem(
                  icon: Icons.sync_lock_rounded,
                  title: 'Secure local sync',
                  desc: 'Your transaction details are instantly updated and categorized',
                ),
                const _FeatureItem(
                  icon: Icons.lock_outline_rounded,
                  title: 'Completely private',
                  desc:
                      'All sync operations run locally on your device — no private data ever leaves your phone.',
                ),
                const _FeatureItem(
                  icon: Icons.wifi_off_rounded,
                  title: 'Offline updates',
                  desc:
                      'Syncing works completely offline without requiring any active internet connection.',
                ),
                const SizedBox(height: 8),
              ],

              // Permanently denied banner
              if (isPermanent)
                Container(
                  margin: const EdgeInsets.only(bottom: 24),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded,
                          color: Colors.orange, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Go to Settings → Apps → YourCA → Permissions → SMS → Allow',
                          style: AppTextStyles.bodySmall
                              .copyWith(color: Colors.orange.shade200),
                        ),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 12),

              // Primary button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isRequesting
                      ? null
                      : isPermanent
                          ? _openSettings
                          : _requestPermission,
                  child: _isRequesting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : Text(isPermanent
                          ? 'Open App Settings'
                          : isDenied
                              ? 'Try Again'
                              : 'Enable Secure Sync'),
                ),
              ),
              const SizedBox(height: 12),

              // Skip button
              TextButton(
                onPressed: widget.onDenied,
                child: Text(
                  'Skip — I\'ll add transactions manually',
                  style: AppTextStyles.bodyMedium
                      .copyWith(color: AppColors.textSecondary),
                ),
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
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.primaryGlow,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppColors.primaryLight, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: AppTextStyles.titleSmall
                        .copyWith(color: AppColors.textPrimary)),
                const SizedBox(height: 3),
                Text(desc,
                    style: AppTextStyles.bodySmall
                        .copyWith(color: AppColors.textSecondary, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
