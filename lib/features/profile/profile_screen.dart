import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/theme/theme_provider.dart';
import '../auth/auth_provider.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _nameController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _showEditNameDialog(String currentName) {
    _nameController.text = currentName;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Name'),
        content: TextField(
          controller: _nameController,
          decoration: const InputDecoration(
            hintText: 'Enter your name',
            labelText: 'Display Name',
          ),
          autofocus: true,
          textCapitalization: TextCapitalization.words,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final newName = _nameController.text.trim();
              if (newName.isNotEmpty) {
                await ref.read(authNotifierProvider.notifier).updateUserName(newName);
              }
              if (mounted) Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(userProfileProvider);
    final themeMode = ref.watch(themeModeProvider);
    final isDark = themeMode == ThemeMode.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile Settings'),
      ),
      body: userAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error: $err')),
        data: (profile) {
          final emailOrPhone = profile?.phoneNumber ?? 'No email associated';
          final name = profile?.name ?? 'User';

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              // ── Header Profile Card ─────────────────────────────
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.surfaceVariant : Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: isDark
                      ? null
                      : Border.all(color: const Color(0xFFE5E5EA), width: 0.8),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 30,
                      backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                      child: Text(
                        name.isNotEmpty ? name[0].toUpperCase() : 'U',
                        style: AppTextStyles.headlineSmall.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: AppTextStyles.titleLarge,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            emailOrPhone,
                            style: AppTextStyles.bodyMedium.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit_rounded, color: AppColors.primary),
                      onPressed: () => _showEditNameDialog(name),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // ── Settings Section Title ──────────────────────────
              Text(
                'PREFERENCES',
                style: AppTextStyles.labelMedium.copyWith(
                  color: AppColors.textSecondary,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 10),

              // ── Theme Option ──────────────────────────────────
              Container(
                decoration: BoxDecoration(
                  color: isDark ? AppColors.surfaceVariant : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: isDark
                      ? null
                      : Border.all(color: const Color(0xFFE5E5EA), width: 0.8),
                ),
                child: ListTile(
                  leading: Icon(
                    isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                    color: isDark ? AppColors.primary : Colors.orange,
                  ),
                  title: const Text('App Theme'),
                  subtitle: Text(isDark ? 'Dark Mode' : 'Light Mode'),
                  trailing: Switch(
                    value: isDark,
                    onChanged: (_) {
                      ref.read(themeModeProvider.notifier).toggleTheme();
                    },
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // ── Security & Privacy Info Card ───────────────────
              Text(
                'SECURITY & PRIVACY',
                style: AppTextStyles.labelMedium.copyWith(
                  color: AppColors.textSecondary,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.surfaceVariant : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: isDark
                      ? null
                      : Border.all(color: const Color(0xFFE5E5EA), width: 0.8),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.security_rounded, color: AppColors.credit, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'On-Device Processing',
                            style: AppTextStyles.titleSmall,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'All bank transaction SMS alerts are processed locally on your phone. SMS content never leaves your device — only parsed amount, category, and merchant name are saved to your profile database.',
                            style: AppTextStyles.bodySmall.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.debit.withValues(alpha: 0.15),
                  foregroundColor: AppColors.debit,
                  elevation: 0,
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.logout_rounded),
                    SizedBox(width: 8),
                    Text('Log Out'),
                  ],
                ),
                onPressed: () async {
                  await ref.read(authNotifierProvider.notifier).signOut();
                  // Router will automatically redirect to auth screen
                },
              ),
            ],
          );
        },
      ),
    );
  }
}
