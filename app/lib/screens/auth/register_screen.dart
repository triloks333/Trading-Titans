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

  bool get _isLengthValid => _passwordController.text.length >= 8;
  bool get _hasUppercase => RegExp(r'[A-Z]').hasMatch(_passwordController.text);
  bool get _hasLowercase => RegExp(r'[a-z]').hasMatch(_passwordController.text);
  bool get _hasDigits => RegExp(r'[0-9]').hasMatch(_passwordController.text);
  bool get _hasSpecial => RegExp(r'[!@#$%^&*(),.?":{}|<>]').hasMatch(_passwordController.text);

  bool get _isValid => _isLengthValid && _hasUppercase && _hasLowercase && _hasDigits && _hasSpecial;

  Future<void> _submit() async {
    if (!_isValid) return;

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
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
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
                Text('Join the Titans', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: AppColors.ink)),
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
                      Text('Create your desk', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.ink)),
                      const SizedBox(height: AppSpacing.sm),
                      Text('Start with ₹11,000 free dummy cash instantly!', style: TextStyle(fontSize: 13, color: AppColors.ink4)),
                      const SizedBox(height: AppSpacing.xl),
                      Text('Full Name', style: TextStyle(fontSize: 12, color: AppColors.ink3)),
                      const SizedBox(height: AppSpacing.xs),
                      _buildField(_nameController, 'Arjun Mehra', false),
                      const SizedBox(height: AppSpacing.md),
                      Text('Email', style: TextStyle(fontSize: 12, color: AppColors.ink3)),
                      const SizedBox(height: AppSpacing.xs),
                      _buildField(_emailController, 'you@example.com', false),
                      const SizedBox(height: AppSpacing.md),
                      Text('Password', style: TextStyle(fontSize: 12, color: AppColors.ink3)),
                      const SizedBox(height: AppSpacing.xs),
                      _buildField(_passwordController, 'Min. 8 chars (letters, digits & symbols)', true, isPassword: true),
                      const SizedBox(height: AppSpacing.md),
                      _buildChecklist(),
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
                              side: BorderSide(color: AppColors.birch),
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
                        Text('Referral Code', style: TextStyle(fontSize: 12, color: AppColors.ink3)),
                        const SizedBox(height: AppSpacing.xs),
                        _buildField(_referralController, 'e.g. TT-XXXXXX', false),
                      ],
                      if (_error != null) ...[
                        const SizedBox(height: AppSpacing.sm),
                        Text(_error!, style: const TextStyle(color: AppColors.bear, fontSize: 13)),
                      ],
                      const SizedBox(height: AppSpacing.lg),
                      ElevatedButton(
                        onPressed: _busy || !_isValid ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.imperialGold,
                          disabledBackgroundColor: AppColors.birch,
                          minimumSize: const Size.fromHeight(52),
                        ),
                        child: _busy
                            ? CircularProgressIndicator(color: AppColors.pureWhite)
                            : Text('Create Account', style: TextStyle(color: _isValid ? AppColors.pureWhite : AppColors.ink4, fontWeight: FontWeight.w600)),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('Already have an account?', style: TextStyle(color: AppColors.ink4)),
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

  Widget _buildChecklist() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildCheckItem('Minimum 8 characters', _isLengthValid),
        const SizedBox(height: 6),
        _buildCheckItem('At least 1 uppercase letter', _hasUppercase),
        const SizedBox(height: 6),
        _buildCheckItem('At least 1 lowercase letter', _hasLowercase),
        const SizedBox(height: 6),
        _buildCheckItem('At least 1 number', _hasDigits),
        const SizedBox(height: 6),
        _buildCheckItem('At least 1 special character', _hasSpecial),
      ],
    );
  }

  Widget _buildCheckItem(String text, bool isValid) {
    return Row(
      children: [
        Icon(
          isValid ? Icons.check_circle : Icons.cancel,
          color: isValid ? AppColors.bull : AppColors.bear,
          size: 16,
        ),
        const SizedBox(width: 8),
        Text(
          text,
          style: TextStyle(
            fontSize: 12,
            color: isValid ? AppColors.ink : AppColors.ink4,
            fontWeight: isValid ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ],
    );
  }

  Widget _buildField(TextEditingController controller, String placeholder, bool obscureText, {bool isPassword = false}) {
    return TextField(
      controller: controller,
      obscureText: isPassword ? _obscurePassword : obscureText,
      onChanged: (text) {
        if (isPassword) {
          setState(() {});
        }
      },
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
