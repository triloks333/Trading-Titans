import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme.dart';
import '../../widgets/auth_kit.dart';
import '../../widgets/legal_consent.dart';
import '../../widgets/web_page.dart';
import '../../services/auth_service.dart';
import '../../services/analytics_service.dart';
import 'login_screen.dart';

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

  void _toSignIn() =>
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const LoginScreen()));

  @override
  Widget build(BuildContext context) {
    popToRootWhenSignedIn(context, context.select<AuthService, bool>((a) => a.isAuthenticated));
    final canPop = Navigator.of(context).canPop();
    return Scaffold(
      // Capped for the browser: this screen is pushed, so it never passes through
      // the gate in main.dart that caps the others.
      body: webFormPage(SafeArea(
        child: Column(children: [
          AuthTopBar(onBack: canPop ? () => Navigator.of(context).pop() : null),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, AppSpacing.md, 20, AppSpacing.xl),
              child: AutofillGroup(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const AuthHeading(title: 'Claim your \u20b91,100', subtitle: 'Free account. Demo cash in seconds.'),
                  const SizedBox(height: AppSpacing.lg),
                  AuthModeSwitch(signIn: false, onSwitch: _toSignIn),
                  const SizedBox(height: AppSpacing.lg),
                  if (Platform.isIOS) ...[
                    SocialButton.apple(onPressed: _busy ? null : _signInWithApple),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                  SocialButton.google(onPressed: _busy ? null : _signInWithGoogle),
                  const SizedBox(height: AppSpacing.lg),
                  const AuthDivider('or with email'),
                  const SizedBox(height: AppSpacing.lg),
                  AuthField(
                    label: 'Display name (optional)',
                    controller: _nameController,
                    hint: 'Shown on the league board',
                    autofillHints: const [AutofillHints.nickname],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AuthField(
                    label: 'Email',
                    controller: _emailController,
                    hint: 'you@example.com',
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AuthField(
                    label: 'Password',
                    controller: _passwordController,
                    hint: 'At least 8 characters',
                    autofillHints: const [AutofillHints.newPassword],
                    obscured: _obscurePassword,
                    onToggleObscure: () => setState(() => _obscurePassword = !_obscurePassword),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _buildStrengthMeter(),
                  const SizedBox(height: AppSpacing.md),
                  // Referral: a quiet toggle that reveals the field.
                  InkWell(
                    onTap: () => setState(() => _hasReferral = !_hasReferral),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                      child: Row(children: [
                        Icon(_hasReferral ? Icons.remove_circle_outline : Icons.add_circle_outline,
                            size: 18, color: AppColors.goldMid),
                        const SizedBox(width: AppSpacing.sm),
                        Text('I have a referral code',
                            style: AppFonts.sans(size: 13, weight: FontWeight.w600, color: AppColors.goldMid)),
                      ]),
                    ),
                  ),
                  if (_hasReferral) ...[
                    const SizedBox(height: AppSpacing.sm),
                    AuthField(label: 'Referral code', controller: _referralController, hint: 'e.g. TT-XXXXXX'),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  // Governs every button on this screen: each one creates an account.
                  LegalConsentCheckbox(
                    value: _acceptedLegal,
                    showError: _showLegalError,
                    onChanged: (v) => setState(() {
                      _acceptedLegal = v;
                      if (v) _showLegalError = false;
                    }),
                  ),
                  if (_error != null) ...[const SizedBox(height: AppSpacing.sm), AuthError(_error!)],
                  const SizedBox(height: AppSpacing.lg),
                  AuthPrimaryButton(label: 'Create account', busy: _busy, onPressed: _isValid ? _submit : null),
                  const SizedBox(height: AppSpacing.lg),
                  const AuthDisclaimer(),
                  const SizedBox(height: AppSpacing.md),
                  const AuthFooter(),
                ]),
              ),
            ),
          ),
        ]),
      )),
    );
  }

  /// Soft strength meter: only the 8-character minimum blocks sign-up.
  Widget _buildStrengthMeter() {
    final filled = _isLengthValid ? (_strengthScore == 0 ? 1 : _strengthScore) : 0;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        for (var i = 0; i < 4; i++)
          Expanded(
            child: Container(
              height: 4,
              margin: EdgeInsets.only(right: i < 3 ? 4 : 0),
              decoration: BoxDecoration(
                color: i < filled ? _strengthColor : AppColors.birch,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
      ]),
      const SizedBox(height: 6),
      Text(
        _passwordController.text.isEmpty ? 'At least 8 characters' : 'Password strength: $_strengthLabel',
        style: AppFonts.sans(size: 12, color: _isLengthValid ? AppColors.ink3 : AppColors.ink4),
      ),
    ]);
  }
}
