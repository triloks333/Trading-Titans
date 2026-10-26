import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/theme.dart';
import '../../core/money.dart';
import '../../services/auth_service.dart';

/// Turns a guest session into a permanent account.
///
/// Nothing is migrated: Supabase attaches the new identity to the same
/// auth.users row, so the portfolio, orders, rewards, streak and wallet history
/// stay exactly where they are. The screen's only jobs are to attach an
/// identity and then call the server-side finaliser.
class ConvertAccountScreen extends StatefulWidget {
  const ConvertAccountScreen({super.key});

  @override
  State<ConvertAccountScreen> createState() => _ConvertAccountScreenState();
}

class _ConvertAccountScreenState extends State<ConvertAccountScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _showEmailForm = false;
  bool _linkSent = false;
  bool _busy = false;
  bool _obscurePassword = true;
  String? _error;

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
            style: GoogleFonts.inter(fontWeight: FontWeight.w800)),
        content: Text(
          bonus > 0
              ? 'Your account is locked in and ${Money.wallet(bonus)} demo cash '
                  'has been added. Everything you built as a guest came with you.'
              : 'Your account is locked in. Everything you built as a guest came '
                  'with you, and you can sign back in any time.',
          style: GoogleFonts.inter(fontSize: 14, color: AppColors.ink3),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              Navigator.of(context).pop();
            },
            child: Text('Done',
                style: GoogleFonts.inter(
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

    return Scaffold(
      backgroundColor: AppColors.parchment,
      appBar: AppBar(
        backgroundColor: AppColors.parchment,
        elevation: 0,
        foregroundColor: AppColors.ink,
        title: Text('Make account permanent',
            style: GoogleFonts.inter(
                fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.ink)),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            if (!auth.isGuest)
              _card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Already permanent',
                        style: GoogleFonts.inter(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: AppColors.ink)),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'This account is signed in as ${user?.email ?? 'you'} and is '
                      'safe to sign out of.',
                      style: GoogleFonts.inter(
                          fontSize: 13, color: AppColors.ink3, height: 1.5),
                    ),
                  ],
                ),
              )
            else ...[
              _card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Unlock the full ₹1,100',
                        style: GoogleFonts.inter(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: AppColors.ink)),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Guest accounts start with ₹500. Attach a Google account '
                      'or an email and password and we will top you up to the '
                      'full ₹1,100.',
                      style: GoogleFonts.inter(
                          fontSize: 13, color: AppColors.ink3, height: 1.5),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    _point(Icons.savings_outlined, '₹600 demo cash added once'),
                    _point(Icons.lock_outline,
                        'Your account survives sign-out and reinstalls'),
                    _point(Icons.inventory_2_outlined,
                        'Portfolio, orders, rewards and streak all carry over'),
                    const SizedBox(height: AppSpacing.md),
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                        color: AppColors.cream,
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        border: Border.all(color: AppColors.birch),
                      ),
                      child: Text(
                        'Right now a guest account cannot be recovered. Sign out '
                        'or delete the app and it is gone for good.',
                        style: GoogleFonts.inter(
                            fontSize: 12, color: AppColors.ink3, height: 1.45),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              OutlinedButton(
                onPressed: _busy ? null : _google,
                style: OutlinedButton.styleFrom(
                  backgroundColor: AppColors.pureWhite,
                  side: BorderSide(color: AppColors.birch, width: 1.5),
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SvgPicture.string(_googleMark, width: 20, height: 20),
                    const SizedBox(width: AppSpacing.md),
                    Text('Continue with Google',
                        style: GoogleFonts.inter(
                            color: AppColors.ink, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              if (!_showEmailForm)
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => setState(() => _showEmailForm = true),
                  style: TextButton.styleFrom(
                      minimumSize: const Size.fromHeight(48)),
                  child: Text('Use email and password instead',
                      style: GoogleFonts.inter(
                          color: AppColors.ink3, fontWeight: FontWeight.w600)),
                )
              else
                _card(child: _emailForm()),
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.md),
                Text(_error!,
                    style: GoogleFonts.inter(
                        color: AppColors.bear, fontSize: 13, height: 1.4)),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _emailForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Email and password',
            style: GoogleFonts.inter(
                fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.ink)),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Two steps: we send a link to confirm the address, then you choose a '
          'password.',
          style:
              GoogleFonts.inter(fontSize: 12, color: AppColors.ink4, height: 1.4),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text('Email', style: GoogleFonts.inter(fontSize: 12, color: AppColors.ink3)),
        const SizedBox(height: AppSpacing.xs),
        _field(_emailController, 'you@example.com',
            keyboardType: TextInputType.emailAddress),
        const SizedBox(height: AppSpacing.md),
        ElevatedButton(
          onPressed: _busy ? null : _sendLink,
          style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.imperialGold,
              minimumSize: const Size.fromHeight(52)),
          child: Text(_linkSent ? 'Resend link' : 'Send confirmation link',
              style: GoogleFonts.inter(
                  color: AppColors.pureWhite, fontWeight: FontWeight.w600)),
        ),
        if (_linkSent) ...[
          const SizedBox(height: AppSpacing.lg),
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.cream,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: AppColors.birch),
            ),
            child: Text(
              'Link sent. Open it from your inbox, come back here, then set your '
              'password below.',
              style: GoogleFonts.inter(
                  fontSize: 12, color: AppColors.ink3, height: 1.45),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('New password',
              style: GoogleFonts.inter(fontSize: 12, color: AppColors.ink3)),
          const SizedBox(height: AppSpacing.xs),
          _field(_passwordController, '••••••••', isPassword: true),
          const SizedBox(height: AppSpacing.md),
          ElevatedButton(
            onPressed: _busy ? null : _finish,
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.ink,
                minimumSize: const Size.fromHeight(52)),
            child: Text('Finish upgrade',
                style: GoogleFonts.inter(
                    color: AppColors.pureWhite, fontWeight: FontWeight.w600)),
          ),
        ],
      ],
    );
  }

  Widget _card({required Widget child}) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.xl),
        decoration: BoxDecoration(
          color: AppColors.pureWhite,
          borderRadius: BorderRadius.circular(AppRadius.xl),
          border: Border.all(color: AppColors.birch),
        ),
        child: child,
      );

  Widget _point(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: AppColors.imperialGold),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(text,
                  style: GoogleFonts.inter(
                      fontSize: 13, color: AppColors.ink, height: 1.4)),
            ),
          ],
        ),
      );

  Widget _field(TextEditingController controller, String hint,
      {bool isPassword = false, TextInputType? keyboardType}) {
    return TextField(
      controller: controller,
      obscureText: isPassword && _obscurePassword,
      keyboardType: keyboardType,
      autocorrect: false,
      enableSuggestions: !isPassword,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: AppColors.ink4.withValues(alpha: 0.5)),
        filled: true,
        fillColor: AppColors.cream,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
            borderSide: BorderSide(color: AppColors.birch)),
        contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: 16),
        suffixIcon: isPassword
            ? IconButton(
                icon: Icon(
                    _obscurePassword ? Icons.visibility_off : Icons.visibility,
                    color: AppColors.ink4),
                tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
              )
            : null,
      ),
    );
  }
}

const String _googleMark =
    '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24">
  <path fill="#4285F4" d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z"/>
  <path fill="#34A853" d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z"/>
  <path fill="#FBBC05" d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.06H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.94l2.85-2.22-.03-.63z"/>
  <path fill="#EA4335" d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.06l3.66 2.84c.87-2.6 3.3-4.52 6.16-4.52z"/>
</svg>''';
