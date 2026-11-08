import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../core/theme.dart';
import '../services/churn_telemetry_service.dart';
import '../services/theme_service.dart';

/// Shared building blocks for the Titan Terminal auth screens (Welcome, Sign in,
/// Create account), so the three read as one flow and carry one copy of each.

/// Crown mark: the gold three-point crown from the redesign.
class TitanCrown extends StatelessWidget {
  const TitanCrown({super.key, this.size = 36});
  final double size;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: _CrownPainter(AppColors.titanGold));
}

class _CrownPainter extends CustomPainter {
  _CrownPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size s) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = s.width * 0.075
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    double x(double v) => v / 24 * s.width;
    double y(double v) => v / 24 * s.height;
    canvas.drawPath(
        Path()
          ..moveTo(x(4), y(18))
          ..lineTo(x(3), y(7))
          ..lineTo(x(8), y(11))
          ..lineTo(x(12), y(4))
          ..lineTo(x(16), y(11))
          ..lineTo(x(21), y(7))
          ..lineTo(x(20), y(18)),
        p);
    canvas.drawLine(Offset(x(3), y(18)), Offset(x(21), y(18)), p);
  }

  @override
  bool shouldRepaint(_CrownPainter old) => old.color != color;
}

/// Top bar: optional back button on the left, theme toggle on the right.
class AuthTopBar extends StatelessWidget {
  const AuthTopBar({super.key, this.onBack, this.trailing});
  final VoidCallback? onBack;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, 0),
        child: Row(children: [
          if (onBack != null) AuthIconButton(icon: Icons.arrow_back_rounded, label: 'Back', onTap: onBack!),
          const Spacer(),
          ?trailing,
          if (trailing != null) const SizedBox(width: AppSpacing.sm),
          ListenableBuilder(
            listenable: ThemeService(),
            builder: (_, _) => AuthIconButton(
              icon: AppColors.isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
              label: 'Toggle light or dark theme',
onTap: () {
                ChurnTelemetryService.instance.recordButtonTap('global_theme_dark_light_toggle');
                ThemeService().setThemeMode(AppColors.isDark ? ThemeMode.light : ThemeMode.dark);
              },
            ),
          ),
        ]),
      );
}

/// 44dp square icon button with a hairline border, as in the design header.
class AuthIconButton extends StatelessWidget {
  const AuthIconButton({super.key, required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        child: Material(
          color: AppColors.pureWhite,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.md), side: BorderSide(color: AppColors.birch)),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: SizedBox.square(dimension: 44, child: Icon(icon, size: 20, color: AppColors.ink)),
          ),
        ),
      );
}

/// Crown, big title and a muted subtitle.
class AuthHeading extends StatelessWidget {
  const AuthHeading({super.key, required this.title, required this.subtitle});
  final String title, subtitle;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const TitanCrown(),
        const SizedBox(height: AppSpacing.sm),
        Text(title, style: AppFonts.sans(size: 28, weight: FontWeight.w700, color: AppColors.ink, height: 1.15)),
        const SizedBox(height: 4),
        Text(subtitle, style: AppFonts.sans(size: 14, color: AppColors.ink3)),
      ]);
}

/// Sign in / Create account segmented switch. The two modes are separate routes,
/// so selecting the other side calls [onSwitch].
class AuthModeSwitch extends StatelessWidget {
  const AuthModeSwitch({super.key, required this.signIn, required this.onSwitch});
  final bool signIn;
  final VoidCallback onSwitch;

  @override
  Widget build(BuildContext context) {
    Widget seg(String label, bool on) => Expanded(
          child: Semantics(
            button: true,
            selected: on,
            child: GestureDetector(
              onTap: on ? null : onSwitch,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: on ? AppColors.pureWhite : Colors.transparent,
                  borderRadius: BorderRadius.circular(7),
                  border: on ? Border.all(color: AppColors.birch) : null,
                ),
                child: Text(label,
                    style: AppFonts.sans(size: 14, weight: FontWeight.w600, color: on ? AppColors.ink : AppColors.ink3)),
              ),
            ),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: AppColors.cream, borderRadius: BorderRadius.circular(AppRadius.md)),
      child: Row(children: [seg('Sign in', signIn), const SizedBox(width: 4), seg('Create account', !signIn)]),
    );
  }
}

const _googleLogo = '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
<path fill="#4285F4" d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z"/>
<path fill="#34A853" d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z"/>
<path fill="#FBBC05" d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.06H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.94l2.85-2.22-.03-.63z"/>
<path fill="#EA4335" d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.06l3.66 2.84c.87-2.6 3.3-4.52 6.16-4.52z"/>
</svg>''';

/// "Continue with Google" (and Apple on iOS): card-surface outlined buttons.
class SocialButton extends StatelessWidget {
  const SocialButton.google({super.key, required this.onPressed}) : apple = false;
  const SocialButton.apple({super.key, required this.onPressed}) : apple = true;
  final VoidCallback? onPressed;
  final bool apple;

  @override
  Widget build(BuildContext context) => OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          backgroundColor: apple ? (AppColors.isDark ? Colors.white : Colors.black) : AppColors.pureWhite,
          foregroundColor: apple ? (AppColors.isDark ? Colors.black : Colors.white) : AppColors.ink,
          side: BorderSide(color: apple ? Colors.transparent : AppColors.birch),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          apple ? const Icon(Icons.apple, size: 22) : SvgPicture.string(_googleLogo, width: 20, height: 20),
          const SizedBox(width: AppSpacing.sm + 2),
          Flexible(child: Text(apple ? 'Continue with Apple' : 'Continue with Google', overflow: TextOverflow.ellipsis)),
        ]),
      );
}

/// Hairline divider with a centred caption.
class AuthDivider extends StatelessWidget {
  const AuthDivider(this.label, {super.key});
  final String label;

  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(child: Divider(color: AppColors.birch)),
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: Text(label, style: AppFonts.sans(size: 12, color: AppColors.ink4))),
        Expanded(child: Divider(color: AppColors.birch)),
      ]);
}

/// Label above a themed text field; [obscured] + [onToggleObscure] make it a
/// password field with a show/hide control.
class AuthField extends StatelessWidget {
  const AuthField({
    super.key,
    required this.label,
    required this.controller,
    required this.hint,
    this.keyboardType,
    this.autofillHints,
    this.obscured,
    this.onToggleObscure,
    this.onChanged,
    this.textInputAction = TextInputAction.next,
    this.onSubmitted,
  });

  final String label, hint;
  final TextEditingController controller;
  final TextInputType? keyboardType;
  final Iterable<String>? autofillHints;
  final bool? obscured;
  final VoidCallback? onToggleObscure;
  final ValueChanged<String>? onChanged;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: AppFonts.sans(size: 12, weight: FontWeight.w500, color: AppColors.ink3)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          autofillHints: autofillHints,
          obscureText: obscured ?? false,
          onChanged: onChanged,
          textInputAction: textInputAction,
          onSubmitted: onSubmitted,
          style: AppFonts.sans(size: 15, color: AppColors.ink),
          decoration: InputDecoration(
            hintText: hint,
            suffixIcon: obscured == null
                ? null
                : IconButton(
                    tooltip: obscured! ? 'Show password' : 'Hide password',
                    icon: Icon(obscured! ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                        color: AppColors.ink4, size: 20),
                    onPressed: onToggleObscure,
                  ),
          ),
        ),
      ]);
}

/// Full-width 52dp primary action with an inline spinner while [busy].
class AuthPrimaryButton extends StatelessWidget {
  const AuthPrimaryButton({super.key, required this.label, required this.onPressed, this.busy = false});
  final String label;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) => ElevatedButton(
        onPressed: busy ? null : onPressed,
        style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
        child: busy
            ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : Text(label),
      );
}

/// Inline error line in the bear colour.
class AuthError extends StatelessWidget {
  const AuthError(this.message, {super.key});
  final String message;

  @override
  Widget build(BuildContext context) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.error_outline_rounded, size: 16, color: AppColors.bear),
        const SizedBox(width: 6),
        Expanded(child: Text(message, style: AppFonts.sans(size: 13, color: AppColors.bear))),
      ]);
}

/// Footer the design puts at the bottom of every auth screen.
class AuthFooter extends StatelessWidget {
  const AuthFooter({super.key});

  @override
  Widget build(BuildContext context) => Text(
        'Trading Titans is operated by Kashivwealth Management LLP. Virtual trading only. Not investment advice.',
        textAlign: TextAlign.center,
        style: AppFonts.sans(size: 11, color: AppColors.ink4, height: 1.4),
      );
}

/// Auth screens are pushed on top of the Welcome screen. When sign-in finishes,
/// asynchronously in the case of Google and Apple OAuth, the gate in main.dart
/// swaps the root to the home shell, so these pushed routes must get out of the way.
/// Call from build() with the current sign-in state.
void popToRootWhenSignedIn(BuildContext context, bool signedIn) {
  if (!signedIn) return;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (context.mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).popUntil((r) => r.isFirst);
    }
  });
}
