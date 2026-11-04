import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../core/theme.dart';
import '../../widgets/crown_logo.dart';
import '../../widgets/legal_consent.dart';
import '../../widgets/web_page.dart';
import '../../services/auth_service.dart';
import '../../services/analytics_service.dart';

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

  /// Consent for account creation. Both paths on this screen create an account.
  bool _acceptedLegal = false;
  bool _showLegalError = false;
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

  // Only a minimum length is required now (lower onboarding friction). The
  // other rules feed a soft strength meter but never block sign-up.
  bool get _isValid => _isLengthValid;

  /// 0..4 strength score from the optional criteria, used only for the meter.
  int get _strengthScore =>
      (_hasUppercase ? 1 : 0) +
      (_hasLowercase ? 1 : 0) +
      (_hasDigits ? 1 : 0) +
      (_hasSpecial ? 1 : 0);

  String get _strengthLabel {
    if (!_isLengthValid) return 'Too short';
    switch (_strengthScore) {
      case 4:
        return 'Strong';
      case 3:
        return 'Good';
      case 2:
        return 'Fair';
      default:
        return 'Weak';
    }
  }

  Color get _strengthColor {
    if (!_isLengthValid) return AppColors.bear;
    switch (_strengthScore) {
      case 4:
        return AppColors.bull;
      case 3:
        return AppColors.bull;
      case 2:
        return AppColors.imperialGold;
      default:
        return AppColors.bear;
    }
  }

  /// Consent gate for both account-creating paths on this screen.
  ///
  /// Not folded into [_isValid] on purpose: that disables the Create Account
  /// button, and a dead button gives the user no reason. Checking here lets the
  /// tap through to a visible explanation instead.
  bool _requireLegalConsent() {
    if (_acceptedLegal) return true;
    setState(() {
      _showLegalError = true;
      _error = null;
    });
    return false;
  }

  Future<void> _submit() async {
    if (!_isValid) return;
    if (!_requireLegalConsent()) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    final auth = context.read<AuthService>();
    try {
      await AnalyticsService.logSignupMethodSelected('email');
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

  Future<void> _signInWithGoogle() async {
    if (!_requireLegalConsent()) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    final auth = context.read<AuthService>();
    try {
      // The referral code (if entered) is carried through the OAuth round-trip
      // and applied automatically when the user returns signed-in.
      await AnalyticsService.logSignupMethodSelected('google');
      await auth.signInWithGoogle(
        referralCode: _hasReferral ? _referralController.text.trim() : null,
      );
    } catch (e) {
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _signInWithApple() async {
    if (!_requireLegalConsent()) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    final auth = context.read<AuthService>();
    try {
      await AnalyticsService.logSignupMethodSelected('apple');
      await auth.signInWithApple(
        referralCode: _hasReferral ? _referralController.text.trim() : null,
      );
    } catch (e) {
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.parchment,
      // Capped for the browser: this screen is pushed from the login screen, so
      // it never passes through the gate in main.dart that caps the others.
      body: webFormPage(SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: SingleChildScrollView(
            child: Column(
              children: [
                const SizedBox(height: AppSpacing.xxl),
                const CrownLogo(size: 72),
                const SizedBox(height: AppSpacing.lg),
                Text('Join the Titans', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: AppColors.ink)),
                const SizedBox(height: 8),
                Text('Real Market. Virtual Risk.', style: TextStyle(fontSize: 14, color: AppColors.ink3)),
                const SizedBox(height: AppSpacing.xl),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  decoration: BoxDecoration(color: AppColors.pureWhite, borderRadius: BorderRadius.circular(AppRadius.xl), border: Border.all(color: AppColors.birch)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Create your desk', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: AppColors.ink)),
                      const SizedBox(height: AppSpacing.sm),
                      Text('Start with ₹1,100 free demo cash instantly!', style: TextStyle(fontSize: 13, color: AppColors.ink4)),
                      const SizedBox(height: AppSpacing.xl),
                      Text('Full Name (optional)', style: TextStyle(fontSize: 12, color: AppColors.ink3)),
                      const SizedBox(height: AppSpacing.xs),
                      _buildField(_nameController, 'Arjun Mehra', false),
                      const SizedBox(height: AppSpacing.md),
                      Text('Email', style: TextStyle(fontSize: 12, color: AppColors.ink3)),
                      const SizedBox(height: AppSpacing.xs),
                      _buildField(_emailController, 'you@example.com', false),
                      const SizedBox(height: AppSpacing.md),
                      Text('Password', style: TextStyle(fontSize: 12, color: AppColors.ink3)),
                      const SizedBox(height: AppSpacing.xs),
                      _buildField(_passwordController, 'Min. 8 characters', true, isPassword: true),
                      const SizedBox(height: AppSpacing.md),
                      _buildStrengthMeter(),
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
                            style: GoogleFonts.ibmPlexSans(
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
                      const SizedBox(height: AppSpacing.md),
                      // Above the Create Account button and the Google button
                      // below it: on this screen both create an account, so the
                      // checkbox governs everything that follows.
                      LegalConsentCheckbox(
                        value: _acceptedLegal,
                        showError: _showLegalError,
                        onChanged: (v) => setState(() {
                          _acceptedLegal = v;
                          if (v) _showLegalError = false;
                        }),
                      ),
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
                            : Text('Create Account', style: TextStyle(color: _isValid ? Colors.white : AppColors.ink4, fontWeight: FontWeight.w600)),
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
                      if (Platform.isIOS) ...[
                        OutlinedButton(
                          onPressed: _busy ? null : _signInWithApple,
                          style: OutlinedButton.styleFrom(
                            backgroundColor: Colors.black,
                            side: const BorderSide(color: Colors.black),
                            minimumSize: const Size.fromHeight(52),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(AppRadius.md),
                            ),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.apple, color: Colors.white, size: 24),
                              SizedBox(width: AppSpacing.sm),
                              Text(
                                'Sign in with Apple',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                      ],
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
                          Text('Already have an account?', style: TextStyle(color: AppColors.ink4)),
                          TextButton(
                            onPressed: () {
                              Navigator.of(context).pop();
                            },
                            child: Text('Login', style: TextStyle(color: AppColors.imperialGold)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // Foot of the page, outside the card and separate from the consent
                // checkbox, aligned to the same horizontal padding as the card.
                const SizedBox(height: AppSpacing.lg),
                const AuthDisclaimer(),
                const SizedBox(height: AppSpacing.xl),
              ],
            ),
          ),
        ),
      )),
    );
  }

  Widget _buildStrengthMeter() {
    final filled = _isLengthValid ? (_strengthScore == 0 ? 1 : _strengthScore) : 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: List.generate(4, (i) {
            return Expanded(
              child: Container(
                height: 4,
                margin: EdgeInsets.only(right: i < 3 ? 4 : 0),
                decoration: BoxDecoration(
                  color: i < filled ? _strengthColor : AppColors.birch,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 6),
        Text(
          _passwordController.text.isEmpty
              ? 'At least 8 characters'
              : 'Password strength: $_strengthLabel',
          style: TextStyle(
            fontSize: 12,
            color: _isLengthValid ? AppColors.ink3 : AppColors.ink4,
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
