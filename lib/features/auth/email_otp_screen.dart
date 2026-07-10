import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../shared/widgets/gradient_button.dart';
import 'auth_provider.dart';

class EmailOtpScreen extends ConsumerStatefulWidget {
  const EmailOtpScreen({super.key});

  @override
  ConsumerState<EmailOtpScreen> createState() => _EmailOtpScreenState();
}

class _EmailOtpScreenState extends ConsumerState<EmailOtpScreen>
    with TickerProviderStateMixin {
  final _emailController = TextEditingController();
  final List<TextEditingController> _controllers =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());
  
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _codeSent = false;
  
  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _shakeAnimation = Tween<double>(begin: 0, end: 12).animate(
      CurvedAnimation(parent: _shakeController, curve: Curves.elasticIn),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    for (final c in _controllers) c.dispose();
    for (final f in _focusNodes) f.dispose();
    _shakeController.dispose();
    super.dispose();
  }

  String get _otp => _controllers.map((c) => c.text).join();

  void _onOtpDigitChanged(int index, String value) {
    if (value.isNotEmpty && index < 5) {
      _focusNodes[index + 1].requestFocus();
    }
    if (value.isEmpty && index > 0) {
      _focusNodes[index - 1].requestFocus();
    }
    if (_otp.length == 6) {
      _verifyOtp();
    }
  }

  Future<void> _sendOtp() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      await ref.read(authNotifierProvider.notifier).sendEmailOtp(
            email: _emailController.text.trim(),
          );
      if (mounted) {
        setState(() {
          _isLoading = false;
          _codeSent = true;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _focusNodes[0].requestFocus();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showSnackBar(e.toString().replaceAll(RegExp(r'\[.*\]'), '').trim(), AppColors.debit);
      }
    }
  }

  Future<void> _verifyOtp() async {
    if (_otp.length != 6) return;
    setState(() => _isLoading = true);

    try {
      await ref.read(authNotifierProvider.notifier).verifyEmailOtp(
            email: _emailController.text.trim(),
            otp: _otp,
          );
      if (mounted) {
        context.goNamed('dashboard');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _shakeController.forward(from: 0);
        for (final c in _controllers) c.clear();
        _focusNodes[0].requestFocus();
        _showSnackBar(e.toString().replaceAll(RegExp(r'\[.*\]'), '').trim(), AppColors.debit);
      }
    }
  }

  void _showSnackBar(String message, Color bgColor) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: bgColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.backgroundGradient),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 32),
                
                // Back button if on verification view
                if (_codeSent)
                  IconButton(
                    onPressed: () => setState(() {
                      _codeSent = false;
                      for (final c in _controllers) c.clear();
                    }),
                    icon: const Icon(Icons.arrow_back_ios_new_rounded,
                        color: AppColors.textPrimary),
                  )
                else
                  _buildBrandHeader(),

                const SizedBox(height: 32),
                
                // Dynamic header titles
                Text(
                  _codeSent ? 'Verify your\nemail' : 'Sign in with\nEmail OTP',
                  style: AppTextStyles.displayMedium.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  _codeSent 
                      ? 'We sent a 6-digit OTP code to ${_emailController.text}'
                      : 'Enter your email address to receive a verification code.',
                  style: AppTextStyles.bodyLarge.copyWith(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 40),

                Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      if (!_codeSent) ...[
                        TextFormField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          style: AppTextStyles.bodyLarge,
                          decoration: const InputDecoration(
                            hintText: 'Enter email address',
                            prefixIcon: Icon(Icons.email_outlined),
                          ),
                          validator: (v) {
                            if (v == null || v.isEmpty) return 'Enter email address';
                            if (!v.contains('@')) return 'Enter a valid email';
                            return null;
                          },
                        ),
                        const SizedBox(height: 24),
                        GradientButton(
                          onPressed: _isLoading ? null : _sendOtp,
                          isLoading: _isLoading,
                          label: 'Send OTP',
                        ),
                      ] else ...[
                        AnimatedBuilder(
                          animation: _shakeAnimation,
                          builder: (context, child) {
                            return Transform.translate(
                              offset: Offset(_shakeAnimation.value * (1 - (_shakeController.value - 0.5).abs() * 2), 0),
                              child: child,
                            );
                          },
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: List.generate(6, (index) => _buildOtpField(index)),
                          ),
                        ),
                        const SizedBox(height: 36),
                        GradientButton(
                          onPressed: _isLoading ? null : _verifyOtp,
                          isLoading: _isLoading,
                          label: 'Verify OTP',
                        ),
                      ],
                    ],
                  ),
                ),
                const Spacer(),
                _buildFooter(),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBrandHeader() {
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            gradient: AppColors.primaryGradient,
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Icon(Icons.account_balance_wallet_rounded,
              color: Colors.white, size: 26),
        ),
        const SizedBox(width: 12),
        Text('YourCA', style: AppTextStyles.headlineLarge.copyWith(fontWeight: FontWeight.w800)),
      ],
    );
  }

  Widget _buildOtpField(int index) {
    return SizedBox(
      width: 48,
      child: TextFormField(
        controller: _controllers[index],
        focusNode: _focusNodes[index],
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        style: AppTextStyles.headlineLarge.copyWith(fontWeight: FontWeight.bold),
        inputFormatters: [
          LengthLimitingTextInputFormatter(1),
          FilteringTextInputFormatter.digitsOnly,
        ],
        onChanged: (v) => _onOtpDigitChanged(index, v),
        decoration: InputDecoration(
          contentPadding: const EdgeInsets.symmetric(vertical: 16),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: AppColors.border, width: 1.5),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: AppColors.primary, width: 2),
          ),
        ),
      ),
    );
  }

  Widget _buildFooter() {
    return Center(
      child: Text(
        'YourCA Finance Planner • Secured by Firebase',
        textAlign: TextAlign.center,
        style: AppTextStyles.labelSmall.copyWith(color: AppColors.textTertiary),
      ),
    );
  }
}
