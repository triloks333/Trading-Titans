import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme.dart';
import '../../widgets/crown_logo.dart';
import '../../services/auth_service.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _referralController = TextEditingController();
  bool _hasReferral = false;
  bool _busy = false;
  String? _error;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _referralController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });

    final auth = context.read<AuthService>();
    try {
      await auth.register(
        _emailController.text.trim(),
        _passwordController.text,
        _nameController.text.trim(),
        referralCode: _hasReferral ? _referralController.text.trim() : null,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      // Extract clean error message
      String errMsg = e.toString();
      if (errMsg.contains('Exception: ')) {
        errMsg = errMsg.substring(errMsg.indexOf('Exception: ') + 11);
      }
      setState(() {
        _error = errMsg;
      });
    } finally {
      setState(() {
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.parchment,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: SingleChildScrollView(
            child: Column(
              children: [
                const SizedBox(height: AppSpacing.xxl),
                const CrownLogo(size: 72),
                const SizedBox(height: AppSpacing.lg),
                const Text('Join the Titans', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: AppColors.ink)),
                const SizedBox(height: 8),
                const Text('Real Market. Virtual Risk.', style: TextStyle(fontSize: 14, color: AppColors.goldDeep)),
                const SizedBox(height: AppSpacing.xl),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  decoration: BoxDecoration(color: AppColors.pureWhite, borderRadius: BorderRadius.circular(AppRadius.xl), border: Border.all(color: AppColors.birch)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Create your desk', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.ink)),
                      const SizedBox(height: AppSpacing.sm),
                      const Text('Start with ₹11,000 free dummy cash instantly!', style: TextStyle(fontSize: 13, color: AppColors.ink4)),
                      const SizedBox(height: AppSpacing.xl),
                      const Text('Full Name', style: TextStyle(fontSize: 12, color: AppColors.ink3)),
                      const SizedBox(height: AppSpacing.xs),
                      _buildField(_nameController, 'Arjun Mehra', false),
                      const SizedBox(height: AppSpacing.md),
                      const Text('Email', style: TextStyle(fontSize: 12, color: AppColors.ink3)),
                      const SizedBox(height: AppSpacing.xs),
                      _buildField(_emailController, 'you@example.com', false),
                      const SizedBox(height: AppSpacing.md),
                      const Text('Password', style: TextStyle(fontSize: 12, color: AppColors.ink3)),
                      const SizedBox(height: AppSpacing.xs),
                      _buildField(_passwordController, 'At least 6 characters', true, isPassword: true),
                      const SizedBox(height: AppSpacing.md),
                      Row(
                        children: [
                          SizedBox(
                            width: 24,
                            height: 24,
                            child: Checkbox(
                              value: _hasReferral,
                              onChanged: (val) {
                                setState(() {
                                  _hasReferral = val ?? false;
                                });
                              },
                              activeColor: AppColors.imperialGold,
                              side: const BorderSide(color: AppColors.birch),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Text(
                            'Do you have a referral code?',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              color: AppColors.ink2,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      if (_hasReferral) ...[
                        const SizedBox(height: AppSpacing.md),
                        const Text('Referral Code', style: TextStyle(fontSize: 12, color: AppColors.ink3)),
                        const SizedBox(height: AppSpacing.xs),
                        _buildField(_referralController, 'e.g. TT-XXXXXX', false),
                      ],
                      if (_error != null) ...[
                        const SizedBox(height: AppSpacing.sm),
                        Text(_error!, style: const TextStyle(color: AppColors.bear, fontSize: 13)),
                      ],
                      const SizedBox(height: AppSpacing.lg),
                      ElevatedButton(
                        onPressed: _busy ? null : _submit,
                        style: ElevatedButton.styleFrom(backgroundColor: AppColors.imperialGold, minimumSize: const Size.fromHeight(52)),
                        child: _busy ? const CircularProgressIndicator(color: AppColors.pureWhite) : const Text('Create Account', style: TextStyle(color: AppColors.pureWhite, fontWeight: FontWeight.w600)),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text('Already have an account?', style: TextStyle(color: AppColors.ink4)),
                          TextButton(
                            onPressed: () {
                              Navigator.of(context).pop();
                            },
                            child: const Text('Login', style: TextStyle(color: AppColors.imperialGold)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildField(TextEditingController controller, String placeholder, bool obscureText, {bool isPassword = false}) {
    return TextField(
      controller: controller,
      obscureText: isPassword ? _obscurePassword : obscureText,
      decoration: InputDecoration(
        hintText: placeholder,
        hintStyle: TextStyle(color: AppColors.ink4.withValues(alpha: 0.5)),
        filled: true,
        fillColor: AppColors.cream,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.md), borderSide: BorderSide(color: AppColors.birch)),
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 16),
        suffixIcon: isPassword
            ? IconButton(
                icon: Icon(
                  _obscurePassword ? Icons.visibility_off : Icons.visibility,
                  color: AppColors.ink4,
                ),
                onPressed: () {
                  setState(() {
                    _obscurePassword = !_obscurePassword;
                  });
                },
              )
            : null,
      ),
    );
  }
}
