import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:another_telephony/telephony.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../sms/bank_sms_parser.dart';

// ── Constants ──────────────────────────────────────────────────────────────
const _pinHashKey = 'balance_check_pin_hash';
const _pinSetKey = 'balance_check_pin_set';

// ── Providers ──────────────────────────────────────────────────────────────
final balanceResultProvider = StateProvider<BalanceParseResult?>((ref) => null);
final balanceLoadingProvider = StateProvider<bool>((ref) => false);
final balanceErrorProvider = StateProvider<String?>((ref) => null);

// ── PIN utility functions ──────────────────────────────────────────────────
String _hashPin(String pin) {
  final bytes = utf8.encode(pin + 'yourca_balance_salt_v1');
  return sha256.convert(bytes).toString();
}

Future<bool> _isPinSet() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(_pinSetKey) ?? false;
}

Future<bool> _verifyPin(String pin) async {
  final prefs = await SharedPreferences.getInstance();
  final stored = prefs.getString(_pinHashKey);
  if (stored == null) return false;
  return stored == _hashPin(pin);
}

Future<void> _savePin(String pin) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_pinHashKey, _hashPin(pin));
  await prefs.setBool(_pinSetKey, true);
}

// ── Main Screen ────────────────────────────────────────────────────────────
class BalanceCheckScreen extends ConsumerStatefulWidget {
  const BalanceCheckScreen({super.key});

  @override
  ConsumerState<BalanceCheckScreen> createState() => _BalanceCheckScreenState();
}

class _BalanceCheckScreenState extends ConsumerState<BalanceCheckScreen>
    with TickerProviderStateMixin {
  late AnimationController _cardController;
  late AnimationController _shakeController;
  late Animation<double> _cardFade;
  late Animation<double> _cardSlide;

  bool _pinVerified = false;

  @override
  void initState() {
    super.initState();
    _cardController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    _cardFade = CurvedAnimation(parent: _cardController, curve: Curves.easeOut);
    _cardSlide = Tween<double>(begin: 40, end: 0).animate(
      CurvedAnimation(parent: _cardController, curve: Curves.easeOutCubic),
    );
    _checkPinAndProceed();
  }

  @override
  void dispose() {
    _cardController.dispose();
    _shakeController.dispose();
    super.dispose();
  }

  Future<void> _checkPinAndProceed() async {
    final set = await _isPinSet();
    if (!set) {
      // First time — show setup flow
      if (mounted) _showPinDialog(isSetup: true);
    } else {
      if (mounted) _showPinDialog(isSetup: false);
    }
  }

  void _showPinDialog({required bool isSetup}) {
    showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _PinDialog(
        isSetup: isSetup,
        onShake: () => _shakeController.forward(from: 0),
      ),
    ).then((success) {
      if (success == true) {
        setState(() => _pinVerified = true);
        _loadBalance();
      } else {
        // User cancelled — go back
        if (mounted) Navigator.of(context).pop();
      }
    });
  }

  Future<void> _loadBalance() async {
    if (!Platform.isAndroid) {
      ref.read(balanceErrorProvider.notifier).state =
          'SMS balance reading is only available on Android.';
      return;
    }

    ref.read(balanceLoadingProvider.notifier).state = true;
    ref.read(balanceErrorProvider.notifier).state = null;
    ref.read(balanceResultProvider.notifier).state = null;

    try {
      // Check SMS permission
      final status = await Permission.sms.status;
      if (!status.isGranted) {
        final result = await Permission.sms.request();
        if (!result.isGranted) {
          ref.read(balanceErrorProvider.notifier).state =
              'SMS permission is required to read your bank balance.';
          ref.read(balanceLoadingProvider.notifier).state = false;
          return;
        }
      }

      // Read recent SMS messages (last 50)
      final telephony = Telephony.instance;
      final messages = await telephony.getInboxSms(
        columns: [SmsColumn.ADDRESS, SmsColumn.BODY, SmsColumn.DATE],
        filter: SmsFilter.where(SmsColumn.DATE)
            .greaterThan(
              DateTime.now().subtract(const Duration(days: 30)).millisecondsSinceEpoch.toString(),
            ),
        sortOrder: [OrderBy(SmsColumn.DATE, sort: Sort.DESC)],
      );

      // Try to find balance in each message
      BalanceParseResult? found;
      for (final msg in messages) {
        final body = msg.body ?? '';
        final sender = msg.address ?? '';
        final result = BankSmsParser.instance.parseBalance(body: body, sender: sender);
        if (result != null) {
          found = result;
          break; // Use the most recent balance SMS
        }
      }

      if (found != null) {
        ref.read(balanceResultProvider.notifier).state = found;
        _cardController.forward();
      } else {
        ref.read(balanceErrorProvider.notifier).state =
            'No recent bank balance SMS found.\nPlease make a transaction or check your bank app to trigger an SMS with your balance.';
      }
    } catch (e) {
      ref.read(balanceErrorProvider.notifier).state = 'Error reading SMS: $e';
    } finally {
      ref.read(balanceLoadingProvider.notifier).state = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final balance = ref.watch(balanceResultProvider);
    final isLoading = ref.watch(balanceLoadingProvider);
    final error = ref.watch(balanceErrorProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Bank Balance',
          style: AppTextStyles.headlineSmall,
        ),
        actions: [
          if (_pinVerified)
            IconButton(
              icon: Icon(Icons.refresh_rounded, color: AppColors.primary),
              tooltip: 'Refresh',
              onPressed: _loadBalance,
            ),
        ],
      ),
      body: _pinVerified
          ? _buildContent(balance, isLoading, error)
          : const Center(child: CircularProgressIndicator()),
    );
  }

  Widget _buildContent(BalanceParseResult? balance, bool isLoading, String? error) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Text(
            'Available Balance',
            style: AppTextStyles.titleLarge.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Securely read from your bank SMS',
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.textTertiary),
          ),
          const SizedBox(height: 28),

          if (isLoading) _buildLoadingCard(),
          if (error != null && !isLoading) _buildErrorCard(error),
          if (balance != null && !isLoading) _buildBalanceCard(balance),

          const SizedBox(height: 24),

          // Security note
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.15),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lock_outline_rounded, color: AppColors.primary, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Your data stays private',
                        style: AppTextStyles.labelMedium.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Balance is read only from SMS messages on your device. No data is sent to any server. Protected by your 4-digit PIN.',
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

          const Spacer(),

          // Change PIN button
          TextButton.icon(
            onPressed: () => _showPinDialog(isSetup: true),
            icon: Icon(Icons.pin_outlined, size: 18, color: AppColors.textSecondary),
            label: Text(
              'Change PIN',
              style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.3),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          const SizedBox(height: 8),
          const CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            strokeWidth: 2,
          ),
          const SizedBox(height: 16),
          Text(
            'Reading balance from SMS...',
            style: AppTextStyles.bodyMedium.copyWith(color: Colors.white70),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildErrorCard(String error) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Icon(Icons.sms_failed_outlined, color: AppColors.debit, size: 48),
          const SizedBox(height: 16),
          Text(
            error,
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: _loadBalance,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Try Again'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBalanceCard(BalanceParseResult balance) {
    return AnimatedBuilder(
      animation: _cardController,
      builder: (context, child) {
        return Opacity(
          opacity: _cardFade.value,
          child: Transform.translate(
            offset: Offset(0, _cardSlide.value),
            child: child,
          ),
        );
      },
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          gradient: const LinearGradient(
            colors: [Color(0xFF1B3A7A), Color(0xFF0D1F45)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF1B3A7A).withValues(alpha: 0.5),
              blurRadius: 32,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Stack(
          children: [
            // Decorative circles
            Positioned(
              top: -30,
              right: -30,
              child: Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.05),
                ),
              ),
            ),
            Positioned(
              bottom: -20,
              left: -20,
              child: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.04),
                ),
              ),
            ),
            // Content
            Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Bank logo row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              balance.bank.toUpperCase(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          if (balance.accountSuffix != null)
                            Text(
                              '•••• ${balance.accountSuffix}',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.6),
                                fontSize: 13,
                                letterSpacing: 2,
                              ),
                            ),
                        ],
                      ),
                      Icon(
                        Icons.account_balance_rounded,
                        color: Colors.white.withValues(alpha: 0.5),
                        size: 28,
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),

                  // Balance label
                  Text(
                    'Available Balance',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Balance amount — big and bold
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          '₹',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _formatBalance(balance.balance),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 48,
                          fontWeight: FontWeight.w800,
                          height: 1,
                          letterSpacing: -1,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),

                  // Footer
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Last Updated',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.4),
                              fontSize: 11,
                            ),
                          ),
                          Text(
                            _formatTime(balance.parsedAt),
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.8),
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.credit.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: AppColors.credit.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.verified_rounded, color: AppColors.credit, size: 14),
                            const SizedBox(width: 5),
                            Text(
                              'Verified via SMS',
                              style: TextStyle(
                                color: AppColors.credit,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatBalance(double amount) {
    if (amount >= 100000) {
      return '${(amount / 100000).toStringAsFixed(2)}L';
    }
    if (amount >= 1000) {
      final parts = amount.toStringAsFixed(2).split('.');
      final intPart = parts[0];
      final decPart = parts[1];
      // Indian number formatting
      final reversed = intPart.split('').reversed.toList();
      final groups = <String>[];
      for (int i = 0; i < reversed.length; i++) {
        if (i == 3 || (i > 3 && (i - 1) % 2 == 0)) groups.add(',');
        groups.add(reversed[i]);
      }
      return '${groups.reversed.join()}.$decPart';
    }
    return amount.toStringAsFixed(2);
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    return '${dt.day}/${dt.month} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

// ── PIN Dialog ─────────────────────────────────────────────────────────────
class _PinDialog extends StatefulWidget {
  final bool isSetup;
  final VoidCallback onShake;

  const _PinDialog({required this.isSetup, required this.onShake});

  @override
  State<_PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends State<_PinDialog>
    with SingleTickerProviderStateMixin {
  final List<TextEditingController> _pinControllers =
      List.generate(4, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(4, (_) => FocusNode());
  final List<TextEditingController> _confirmControllers =
      List.generate(4, (_) => TextEditingController());
  final List<FocusNode> _confirmFocusNodes = List.generate(4, (_) => FocusNode());

  bool _isConfirmStep = false;
  bool _isLoading = false;
  String? _errorText;

  late AnimationController _shakeCtrl;
  late Animation<double> _shakeAnim;

  @override
  void initState() {
    super.initState();
    _shakeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _shakeAnim = Tween<double>(begin: 0, end: 10)
        .animate(CurvedAnimation(parent: _shakeCtrl, curve: Curves.elasticIn));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNodes[0].requestFocus();
    });
  }

  @override
  void dispose() {
    for (final c in _pinControllers) c.dispose();
    for (final f in _focusNodes) f.dispose();
    for (final c in _confirmControllers) c.dispose();
    for (final f in _confirmFocusNodes) f.dispose();
    _shakeCtrl.dispose();
    super.dispose();
  }

  String get _pin => _pinControllers.map((c) => c.text).join();
  String get _confirmPin => _confirmControllers.map((c) => c.text).join();

  void _onPinChanged(int index, String value, {bool isConfirm = false}) {
    final focusNodes = isConfirm ? _confirmFocusNodes : _focusNodes;
    final pin = isConfirm ? _confirmPin : _pin;

    if (value.isNotEmpty && index < 3) {
      focusNodes[index + 1].requestFocus();
    }
    if (value.isEmpty && index > 0) {
      focusNodes[index - 1].requestFocus();
    }

    if (pin.length == 4) {
      if (widget.isSetup) {
        if (!isConfirm) {
          // Move to confirm step
          Future.delayed(const Duration(milliseconds: 100), () {
            if (mounted) {
              setState(() => _isConfirmStep = true);
              Future.delayed(const Duration(milliseconds: 50), () {
                _confirmFocusNodes[0].requestFocus();
              });
            }
          });
        } else {
          _finishSetup();
        }
      } else {
        _verifyAndClose();
      }
    }
  }

  Future<void> _finishSetup() async {
    if (_pin != _confirmPin) {
      setState(() => _errorText = 'PINs do not match. Try again.');
      _shakeCtrl.forward(from: 0);
      widget.onShake();
      for (final c in _confirmControllers) c.clear();
      _confirmFocusNodes[0].requestFocus();
      return;
    }
    setState(() => _isLoading = true);
    await _savePin(_pin);
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _verifyAndClose() async {
    setState(() => _isLoading = true);
    final valid = await _verifyPin(_pin);
    if (valid) {
      if (mounted) Navigator.of(context).pop(true);
    } else {
      setState(() {
        _isLoading = false;
        _errorText = 'Incorrect PIN. Try again.';
      });
      _shakeCtrl.forward(from: 0);
      widget.onShake();
      for (final c in _pinControllers) c.clear();
      _focusNodes[0].requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.isSetup
        ? (_isConfirmStep ? 'Confirm PIN' : 'Set a 4-Digit PIN')
        : 'Enter PIN';
    final subtitle = widget.isSetup
        ? (_isConfirmStep
            ? 'Re-enter your PIN to confirm'
            : 'Create a PIN to protect your bank balance')
        : 'Enter your PIN to view balance';

    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Center(
                child: Icon(Icons.lock_rounded, color: Colors.white, size: 30),
              ),
            ),
            const SizedBox(height: 20),

            Text(title, style: AppTextStyles.headlineSmall),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 28),

            // PIN dots
            AnimatedBuilder(
              animation: _shakeCtrl,
              builder: (ctx, child) => Transform.translate(
                offset: Offset(
                  _shakeAnim.value * (1 - (_shakeCtrl.value - 0.5).abs() * 2),
                  0,
                ),
                child: child,
              ),
              child: _isConfirmStep
                  ? _buildPinRow(_confirmControllers, _confirmFocusNodes, isConfirm: true)
                  : _buildPinRow(_pinControllers, _focusNodes),
            ),

            if (_errorText != null) ...[
              const SizedBox(height: 12),
              Text(
                _errorText!,
                textAlign: TextAlign.center,
                style: AppTextStyles.bodySmall.copyWith(color: AppColors.debit),
              ),
            ],

            const SizedBox(height: 28),

            if (_isLoading)
              const CircularProgressIndicator()
            else
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: Text(
                        'Cancel',
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPinRow(
    List<TextEditingController> controllers,
    List<FocusNode> focusNodes, {
    bool isConfirm = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(4, (index) {
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 8),
          width: 56,
          height: 60,
          child: TextFormField(
            controller: controllers[index],
            focusNode: focusNodes[index],
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            obscureText: true,
            style: AppTextStyles.headlineMedium.copyWith(
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
            inputFormatters: [
              LengthLimitingTextInputFormatter(1),
              FilteringTextInputFormatter.digitsOnly,
            ],
            onChanged: (v) => _onPinChanged(index, v, isConfirm: isConfirm),
            decoration: InputDecoration(
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: AppColors.border, width: 1.5),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: AppColors.primary, width: 2.5),
              ),
              filled: true,
              fillColor: AppColors.surfaceVariant,
            ),
          ),
        );
      }),
    );
  }
}
