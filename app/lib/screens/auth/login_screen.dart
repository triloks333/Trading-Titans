import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../core/theme.dart';
import '../../widgets/crown_logo.dart';
import '../../services/auth_service.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _busy = false;
  String? _error;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _error = null;
      _busy = true;
    });

    final auth = context.read<AuthService>();
    try {
      await auth.login(_emailController.text.trim(), _passwordController.text);
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

  Future<void> _signInWithGoogle() async {
    setState(() {
      _error = null;
      _busy = true;
    });

    final auth = context.read<AuthService>();
    try {
      await auth.signInWithGoogle();
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

  void _showForgotPasswordSheet() {
    final emailController = TextEditingController(text: _emailController.text);
    bool resetting = false;
    String? resetError;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.pureWhite,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(AppRadius.xl),
                    topRight: Radius.circular(AppRadius.xl),
                  ),
                  border: Border.all(color: AppColors.birch),
                ),
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppColors.birch,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      'Reset Password',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Enter your email address and we\'ll send you a recovery link.',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.ink4,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Text('Email', style: TextStyle(fontSize: 12, color: AppColors.ink3)),
                    const SizedBox(height: AppSpacing.xs),
                    TextField(
                      controller: emailController,
                      decoration: InputDecoration(
                        hintText: 'you@example.com',
                        hintStyle: TextStyle(color: AppColors.ink4.withValues(alpha: 0.5)),
                        filled: true,
                        fillColor: AppColors.cream,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          borderSide: BorderSide(color: AppColors.birch),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 16),
                      ),
                    ),
                    if (resetError != null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        resetError!,
                        style: const TextStyle(color: AppColors.bear, fontSize: 13),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.xl),
                    ElevatedButton(
                      onPressed: resetting
                          ? null
                          : () async {
                              final email = emailController.text.trim();
                              if (email.isEmpty) {
                                setSheetState(() {
                                  resetError = 'Please enter your email address.';
                                });
                                return;
                              }
                              setSheetState(() {
                                resetting = true;
                                resetError = null;
                              });
                              try {
                                final auth = context.read<AuthService>();
                                await auth.sendPasswordResetEmail(email);
                                if (!context.mounted) return;
                                Navigator.pop(context);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Recovery link sent! Please check your email.'),
                                    backgroundColor: AppColors.bull,
                                  ),
                                );
                              } catch (e) {
                                setSheetState(() {
                                  resetError = e.toString().replaceFirst('Exception: ', '');
                                  resetting = false;
                                });
                              }
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.imperialGold,
                        minimumSize: const Size.fromHeight(52),
                      ),
                      child: resetting
                          ? CircularProgressIndicator(color: AppColors.pureWhite)
                          : Text(
                              'Send Link',
                              style: TextStyle(
                                color: AppColors.pureWhite,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
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
                const CrownLogo(size: 84),
                const SizedBox(height: AppSpacing.lg),
                Text('Trading Titans', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: AppColors.ink)),
                const SizedBox(height: 8),
                const Text('Trade Bold. Lose Nothing.', style: TextStyle(fontSize: 14, color: AppColors.goldDeep)),
                const SizedBox(height: AppSpacing.xl),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  decoration: BoxDecoration(color: AppColors.pureWhite, borderRadius: BorderRadius.circular(AppRadius.xl), border: Border.all(color: AppColors.birch)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Welcome back, Titan', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.ink)),
                      const SizedBox(height: AppSpacing.sm),
                      Text('Sign in to your trading desk', style: TextStyle(fontSize: 13, color: AppColors.ink4)),
                      const SizedBox(height: AppSpacing.xl),
                      Text('Email', style: TextStyle(fontSize: 12, color: AppColors.ink3)),
                      const SizedBox(height: AppSpacing.xs),
                      _buildField(_emailController, 'you@example.com', false),
                      const SizedBox(height: AppSpacing.md),
                      Text('Password', style: TextStyle(fontSize: 12, color: AppColors.ink3)),
                      const SizedBox(height: AppSpacing.xs),
                      _buildField(_passwordController, '••••••••', true, isPassword: true),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: _showForgotPasswordSheet,
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(0, 30),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text('Forgot Password?', style: TextStyle(color: AppColors.imperialGold, fontSize: 13)),
                        ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: AppSpacing.sm),
                        Text(_error!, style: const TextStyle(color: AppColors.bear, fontSize: 13)),
                      ],
                      const SizedBox(height: AppSpacing.lg),
                      ElevatedButton(
                        onPressed: _busy ? null : _submit,
                        style: ElevatedButton.styleFrom(backgroundColor: AppColors.imperialGold, minimumSize: const Size.fromHeight(52)),
                        child: _busy ? CircularProgressIndicator(color: AppColors.pureWhite) : Text('Sign In', style: TextStyle(color: AppColors.pureWhite, fontWeight: FontWeight.w600)),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Row(
                        children: [
                          Expanded(child: Divider(color: AppColors.birch)),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                            child: Text('OR', style: TextStyle(color: AppColors.ink4, fontSize: 12)),
                          ),
                          Expanded(child: Divider(color: AppColors.birch)),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),
                      OutlinedButton(
                        onPressed: _busy ? null : _signInWithGoogle,
                        style: OutlinedButton.styleFrom(
                          backgroundColor: AppColors.cream,
                          side: BorderSide(color: AppColors.birch, width: 1.5),
                          minimumSize: const Size.fromHeight(52),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadius.md),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SvgPicture.string(
                              '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24">
                                <path fill="#4285F4" d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z"/>
                                <path fill="#34A853" d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z"/>
                                <path fill="#FBBC05" d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.06H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.94l2.85-2.22-.03-.63z"/>
                                <path fill="#EA4335" d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.06l3.66 2.84c.87-2.6 3.3-4.52 6.16-4.52z"/>
                              </svg>''',
                              width: 20,
                              height: 20,
                            ),
                            const SizedBox(width: AppSpacing.md),
                            Text(
                              'Continue with Google',
                              style: TextStyle(
                                color: AppColors.ink,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('New to the desk?', style: TextStyle(color: AppColors.ink4)),
                          TextButton(
                            onPressed: () {
                              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RegisterScreen()));
                            },
                            child: const Text('Create account', style: TextStyle(color: AppColors.imperialGold)),
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
