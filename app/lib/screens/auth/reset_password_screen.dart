import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme.dart';
import '../../widgets/crown_logo.dart';
import '../../services/auth_service.dart';

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _busy = false;
  String? _error;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmPasswordController.dispose();
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

    if (_passwordController.text != _confirmPasswordController.text) {
      setState(() {
        _error = 'Passwords do not match.';
      });
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final auth = context.read<AuthService>();
      await auth.updatePassword(_passwordController.text);
      auth.clearRecoveringPassword();
      if (!mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Password updated successfully!'),
          backgroundColor: AppColors.bull,
        ),
      );
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
      appBar: AppBar(
        title: Text('Reset Password', style: TextStyle(color: AppColors.ink)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: AppColors.ink),
          onPressed: () {
            context.read<AuthService>().clearRecoveringPassword();
          },
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: SingleChildScrollView(
            child: Column(
              children: [
                const SizedBox(height: AppSpacing.xl),
                const CrownLogo(size: 72),
                const SizedBox(height: AppSpacing.lg),
                Text('Secure Your Account', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: AppColors.ink)),
                const SizedBox(height: 8),
                Text('Enter a strong, new password below.', style: TextStyle(fontSize: 14, color: AppColors.ink3)),
                const SizedBox(height: AppSpacing.xl),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  decoration: BoxDecoration(
                    color: AppColors.pureWhite,
                    borderRadius: BorderRadius.circular(AppRadius.xl),
                    border: Border.all(color: AppColors.birch),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Update Password', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.ink)),
                      const SizedBox(height: AppSpacing.sm),
                      Text('Your new password must satisfy all checklist items.', style: TextStyle(fontSize: 13, color: AppColors.ink4)),
                      const SizedBox(height: AppSpacing.xl),
                      Text('New Password', style: TextStyle(fontSize: 12, color: AppColors.ink3)),
                      const SizedBox(height: AppSpacing.xs),
                      _buildField(_passwordController, 'Enter new password', _obscurePassword, isPassword: true, onToggleObscure: () {
                        setState(() {
                          _obscurePassword = !_obscurePassword;
                        });
                      }),
                      const SizedBox(height: AppSpacing.md),
                      _buildChecklist(),
                      const SizedBox(height: AppSpacing.md),
                      Text('Confirm New Password', style: TextStyle(fontSize: 12, color: AppColors.ink3)),
                      const SizedBox(height: AppSpacing.xs),
                      _buildField(_confirmPasswordController, 'Confirm new password', _obscureConfirmPassword, isPassword: true, onToggleObscure: () {
                        setState(() {
                          _obscureConfirmPassword = !_obscureConfirmPassword;
                        });
                      }),
                      if (_error != null) ...[
                        const SizedBox(height: AppSpacing.sm),
                        Text(_error!, style: TextStyle(color: AppColors.bear, fontSize: 13)),
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
                            ? const CircularProgressIndicator(color: Colors.white)
                            : Text('Update Password', style: TextStyle(color: _isValid ? Colors.white : AppColors.ink4, fontWeight: FontWeight.w600)),
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

  Widget _buildField(TextEditingController controller, String placeholder, bool obscureText, {bool isPassword = false, VoidCallback? onToggleObscure}) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      onChanged: (text) {
        if (isPassword) {
          setState(() {});
        }
      },
      decoration: InputDecoration(
        hintText: placeholder,
        suffixIcon: isPassword
            ? IconButton(
                icon: Icon(
                  obscureText ? Icons.visibility_off : Icons.visibility,
                  color: AppColors.ink4,
                ),
                onPressed: onToggleObscure,
              )
            : null,
      ),
    );
  }
}
