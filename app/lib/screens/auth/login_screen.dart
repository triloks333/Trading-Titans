import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme.dart';
import '../../widgets/auth_kit.dart';
import '../../widgets/legal_consent.dart';
import '../../services/auth_service.dart';
import '../../services/analytics_service.dart';
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

  /// Consent for the account-CREATING actions on this screen (Google, Guest).
  bool _acceptedLegal = false;
  bool _showLegalError = false;

  @override
  void initState() {
    super.initState();
    // Funnel step 1: the auth screen was shown.
    AnalyticsService.logOnboardingOpen();
  }

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
      _failWith(e);
    } finally {
      setState(() {
        _busy = false;
      });
    }
  }

  /// Surfaces a sign-in failure.
  ///
  /// Shared by all three sign-in paths, which previously each carried their own
  /// copy of this unwrapping. A ban additionally gets a dialog: it is the one
  /// failure here the user cannot fix by trying again, so it has to say why and
  /// where to appeal rather than sit as a line of red text they may not even read.
  void _failWith(Object e) {
    if (!mounted) return;
    final message = e.toString().replaceFirst('Exception: ', '');
    setState(() {
      _error = message;
    });
    // Kept inline as well as in the dialog, so the reason survives after it is
    // dismissed and is still reachable to a screen reader on the form itself.
    if (message == kBannedAccountMessage) _showBannedDialog(message);
  }

  void _showBannedDialog(String message) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.pureWhite,
        title: Text(
          'Account banned',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.bold,
            color: AppColors.ink,
          ),
        ),
        content: Text(
          message,
          style: TextStyle(fontSize: 14, color: AppColors.ink3, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(
              'Close',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: AppColors.imperialGold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Gate for the two buttons on this screen that can CREATE an account.
  ///
  /// Google sign-in creates one on first use and Guest always does, so both need
  /// consent. Email/password sign-in below is deliberately NOT gated: that user
  /// accepted at signup and their acceptance is already recorded, so re-asking on
  /// every login would be friction with no legal value.
  ///
  /// Returns false and shows the inline error when consent is missing. The buttons
  /// stay enabled rather than being greyed out, so the user is told why instead of
  /// being left tapping a dead control.
  bool _requireLegalConsent() {
    if (_acceptedLegal) return true;
    setState(() {
      _showLegalError = true;
      _error = null;
    });
    return false;
  }

  Future<void> _signInWithGoogle() async {
    if (!_requireLegalConsent()) return;
    setState(() {
      _error = null;
      _busy = true;
    });

    final auth = context.read<AuthService>();
    try {
      await AnalyticsService.logSignupMethodSelected('google');
      await auth.signInWithGoogle();
    } catch (e) {
      _failWith(e);
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
      _error = null;
      _busy = true;
    });

    final auth = context.read<AuthService>();
    try {
      await AnalyticsService.logSignupMethodSelected('apple');
      await auth.signInWithApple();
    } catch (e) {
      _failWith(e);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _continueAsGuest() async {
    if (!_requireLegalConsent()) return;
    setState(() {
      _error = null;
      _busy = true;
    });

    final auth = context.read<AuthService>();
    try {
      await AnalyticsService.logSignupMethodSelected('guest');
      await auth.continueAsGuest();
    } catch (e) {
      _failWith(e);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  void _showForgotPasswordSheet() {
    final emailController = TextEditingController(text: _emailController.text);
    bool resetting = false;
    String? resetError;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
              AppSpacing.xl, 0, AppSpacing.xl, AppSpacing.xl + MediaQuery.of(context).viewInsets.bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Reset password', style: AppFonts.sans(size: 20, weight: FontWeight.w700, color: AppColors.ink)),
            const SizedBox(height: 4),
            Text('Enter your email and we will send you a recovery link.', style: AppText.body),
            const SizedBox(height: AppSpacing.lg),
            AuthField(
              label: 'Email',
              controller: emailController,
              hint: 'you@example.com',
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              textInputAction: TextInputAction.done,
            ),
            if (resetError != null) ...[const SizedBox(height: AppSpacing.sm), AuthError(resetError!)],
            const SizedBox(height: AppSpacing.lg),
            AuthPrimaryButton(
              label: 'Send recovery link',
              busy: resetting,
              onPressed: () async {
                final email = emailController.text.trim();
                if (email.isEmpty) {
                  setSheetState(() => resetError = 'Please enter your email address.');
                  return;
                }
                setSheetState(() {
                  resetting = true;
                  resetError = null;
                });
                try {
                  await context.read<AuthService>().sendPasswordResetEmail(email);
                  if (!context.mounted) return;
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: const Text('Recovery link sent! Please check your email.'), backgroundColor: AppColors.bull),
                  );
                } catch (e) {
                  setSheetState(() {
                    resetError = e.toString().replaceFirst('Exception: ', '');
                    resetting = false;
                  });
                }
              },
            ),
          ]),
        ),
      ),
    );
  }

  /// Sign in and Create account are sibling routes; the switch swaps one for the other.
  void _toRegister() =>
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const RegisterScreen()));

  @override
  Widget build(BuildContext context) {
    popToRootWhenSignedIn(context, context.select<AuthService, bool>((a) => a.isAuthenticated));
    final canPop = Navigator.of(context).canPop();
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          AuthTopBar(onBack: canPop ? () => Navigator.of(context).pop() : null),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, AppSpacing.md, 20, AppSpacing.xl),
              child: AutofillGroup(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const AuthHeading(title: 'Welcome back, Titan', subtitle: 'Your portfolio is where you left it.'),
                  const SizedBox(height: AppSpacing.lg),
                  AuthModeSwitch(signIn: true, onSwitch: _toRegister),
                  const SizedBox(height: AppSpacing.lg),
                  // Google, Apple and Guest can CREATE an account, so they sit under
                  // the consent checkbox. Email sign-in below is not gated: that user
                  // accepted at signup.
                  LegalConsentCheckbox(
                    value: _acceptedLegal,
                    showError: _showLegalError,
                    onChanged: (v) => setState(() {
                      _acceptedLegal = v;
                      if (v) _showLegalError = false;
                    }),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  if (Platform.isIOS) ...[
                    SocialButton.apple(onPressed: _busy ? null : _signInWithApple),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                  SocialButton.google(onPressed: _busy ? null : _signInWithGoogle),
                  const SizedBox(height: AppSpacing.lg),
                  const AuthDivider('or with email'),
                  const SizedBox(height: AppSpacing.lg),
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
                    hint: 'Your password',
                    autofillHints: const [AutofillHints.password],
                    obscured: _obscurePassword,
                    onToggleObscure: () => setState(() => _obscurePassword = !_obscurePassword),
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) {
                      if (!_busy) _submit();
                    },
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(onPressed: _showForgotPasswordSheet, child: const Text('Forgot password?')),
                  ),
                  if (_error != null) ...[AuthError(_error!), const SizedBox(height: AppSpacing.md)],
                  AuthPrimaryButton(label: 'Sign in', busy: _busy, onPressed: _submit),
                  const SizedBox(height: AppSpacing.sm),
                  // Amount disclosed up front: a guest starts at Rs 500, not Rs 1,100.
                  TextButton(
                    onPressed: _busy ? null : _continueAsGuest,
                    style: TextButton.styleFrom(foregroundColor: AppColors.ink3),
                    child: const Text('Explore as guest with \u20b9500'),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  const AuthDisclaimer(),
                  const SizedBox(height: AppSpacing.md),
                  const AuthFooter(),
                ]),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
