import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme.dart';
import '../../core/money.dart';
import '../../services/auth_service.dart';
import '../../services/churn_telemetry_service.dart';
import '../../services/theme_service.dart';
import '../../widgets/auth_kit.dart';
import '../auth/login_screen.dart';

/// Turns a guest session into a permanent account.
///
/// Nothing is migrated: Supabase attaches the new identity to the same
/// auth.users row, so the portfolio, orders, rewards, streak and wallet history
/// stay exactly where they are. The screen's only jobs are to attach an
/// identity and then call the server-side finaliser.
///
/// With [requiredGate] it is the sign-up step every guest must pass after
/// onboarding (main.dart shows it instead of the app): no back button, and a
/// "Sign in" path for people who already have an account.
class ConvertAccountScreen extends StatefulWidget {
  const ConvertAccountScreen({super.key, this.requiredGate = false});

  final bool requiredGate;

  @override
  State<ConvertAccountScreen> createState() => _ConvertAccountScreenState();
}

class _ConvertAccountScreenState extends State<ConvertAccountScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _linkSent = false;
  bool _busy = false;
  bool _obscurePassword = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.requiredGate) ChurnTelemetryService.instance.recordHomeScreen('convert_account_screen');
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _google() => _run(() async {
        await context.read<AuthService>().convertWithGoogle();
        // The upgrade is finalised by AuthService's auth-state listener when the
        // browser round-trip returns, so there is nothing to await here.
      });

  Future<void> _sendLink() => _run(() async {
        await context
            .read<AuthService>()
            .startEmailConversion(_emailController.text);
        if (mounted) setState(() => _linkSent = true);
      });

  Future<void> _finish() => _run(() async {
        final password = _passwordController.text;
        if (password.length < 6) {
          throw Exception('Please use a password of at least 6 characters.');
        }
        final bonus =
            await context.read<AuthService>().setConversionPassword(password);
        if (!mounted) return;
        if (bonus == null) {
          setState(() => _error =
              'We could not confirm your email yet. Open the link we sent you, '
              'then come back and try again.');
          return;
        }
        _celebrate(bonus);
      });

  void _celebrate(num bonus) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.pureWhite,
        title: Text('You are a permanent Titan',
            style: GoogleFonts.ibmPlexSans(fontWeight: FontWeight.w700)),
        content: Text(
          bonus > 0
              ? 'Your account is locked in and ${Money.wallet(bonus)} demo cash '
                  'has been added. Everything you built as a guest came with you.'
              : 'Your account is locked in. Everything you built as a guest came '
                  'with you, and you can sign back in any time.',
          style: GoogleFonts.ibmPlexSans(fontSize: 14, color: AppColors.ink3),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              // As the gate, the app replaces this screen by itself once the account is permanent.
              if (!widget.requiredGate) Navigator.of(context).pop();
            },
            child: Text('Done',
                style: GoogleFonts.ibmPlexSans(
                    color: AppColors.imperialGold, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final user = auth.user;
    Widget benefit(String text, [String? bold]) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(children: [
            Text('✓', style: AppFonts.sans(size: 14, color: AppColors.bull)),
            const SizedBox(width: 10),
            Expanded(
              child: Text.rich(TextSpan(style: AppFonts.sans(size: 14, color: AppColors.ink), children: [
                TextSpan(text: text),
                if (bold != null) TextSpan(text: bold, style: AppFonts.mono(size: 14, weight: FontWeight.w700, color: AppColors.ink)),
              ])),
            ),
          ]),
        );

    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 10, AppSpacing.lg, 10),
            child: Row(children: [
              if (!widget.requiredGate)
                AuthIconButton(icon: Icons.arrow_back_rounded, label: 'Back', onTap: () => Navigator.of(context).maybePop()),
              const Spacer(),
              ListenableBuilder(
                listenable: ThemeService(),
                builder: (_, _) => AuthIconButton(
                  icon: AppColors.isDark ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
                  label: 'Toggle light or dark theme',
                  onTap: () => ThemeService().setThemeMode(AppColors.isDark ? ThemeMode.light : ThemeMode.dark),
                ),
              ),
            ]),
          ),
          Expanded(
            child: ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 20), children: [
              if (!auth.isGuest) ...[
                Text('Already permanent', style: AppFonts.sans(size: 28, weight: FontWeight.w700, color: AppColors.ink)),
                const SizedBox(height: 6),
                Text('This account is signed in as ${user?.email ?? 'you'} and is safe to sign out of.', style: AppText.body),
              ] else ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: AppColors.titanGoldSoft, borderRadius: BorderRadius.circular(6)),
                    child: Text('GUEST · ${Money.wallet(500, decimals: 0)} → ${Money.wallet(1100, decimals: 0)}',
                        style: AppFonts.mono(size: 12, weight: FontWeight.w600, color: AppColors.titanGold)),
                  ),
                ),
                const SizedBox(height: 12),
                Text(widget.requiredGate ? 'Create your account' : 'Make your account permanent',
                    style: AppFonts.sans(size: 28, weight: FontWeight.w700, color: AppColors.ink, height: 1.15)),
                const SizedBox(height: 6),
                Text(
                    widget.requiredGate
                        ? 'Sign up to save your portfolio and start trading. Everything from your first trade comes with you.'
                        : 'Keep everything you’ve built and unlock the full app.',
                    style: AppFonts.sans(size: 14, color: AppColors.ink3)),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 4),
                  decoration: BoxDecoration(
                    color: AppColors.pureWhite,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(color: AppColors.birch),
                  ),
                  child: Column(children: [
                    benefit('Top up to ', '${Money.wallet(1100, decimals: 0)} demo cash'),
                    benefit('Portfolio and history survive a reinstall'),
                    benefit('Post in Titans Room chat'),
                    benefit('Rank on the Weekly League'),
                  ]),
                ),
                const SizedBox(height: 16),
                SocialButton.google(onPressed: _busy ? null : _google),
                const SizedBox(height: 16),
                const AuthDivider('or with email'),
                const SizedBox(height: 16),
                AuthField(
                  label: 'Email',
                  controller: _emailController,
                  hint: 'you@domain.com',
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                ),
                if (_linkSent) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: AppColors.cream, borderRadius: BorderRadius.circular(AppRadius.md)),
                    child: Text('Link sent. Open it from your inbox, come back here, then set your password.',
                        style: AppFonts.sans(size: 12, color: AppColors.ink3, height: 1.45)),
                  ),
                  const SizedBox(height: 12),
                  AuthField(
                    label: 'Password',
                    controller: _passwordController,
                    hint: 'At least 6 characters',
                    autofillHints: const [AutofillHints.newPassword],
                    obscured: _obscurePassword,
                    onToggleObscure: () => setState(() => _obscurePassword = !_obscurePassword),
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _finish(),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(onPressed: _busy ? null : _sendLink, child: const Text('Resend link')),
                  ),
                ],
                if (_error != null) ...[const SizedBox(height: 12), AuthError(_error!)],
              ],
            ]),
          ),
          if (auth.isGuest)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: AuthPrimaryButton(
                label: _linkSent ? 'Make account permanent' : 'Send confirmation link',
                busy: _busy,
                onPressed: _busy ? null : (_linkSent ? _finish : _sendLink),
              ),
            ),
          if (auth.isGuest && widget.requiredGate)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: TextButton(
                // Signing in replaces the guest session, so the guest's practice trade stays behind.
                onPressed: _busy ? null : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LoginScreen())),
                style: TextButton.styleFrom(foregroundColor: AppColors.ink3, minimumSize: const Size.fromHeight(44)),
                child: const Text('Already have an account? Sign in'),
              ),
            ),
        ]),
      ),
    );
  }
}
