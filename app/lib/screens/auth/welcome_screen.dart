import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../services/churn_telemetry_service.dart';
import '../../widgets/auth_kit.dart';
import 'login_screen.dart';
import 'register_screen.dart';

/// First screen for signed-out users: two intro slides, then the way in.
/// Sign in and Create account are pushed on top and pop themselves on success.
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  @override
  void initState() {
    super.initState();
    ChurnTelemetryService.instance.recordHomeScreen('welcome_screen');
  }

  final _pages = PageController();
  int _page = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _push(Widget screen) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

  @override
  Widget build(BuildContext context) {
    final last = _page == 1;
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          AuthTopBar(
            trailing: TextButton(
              onPressed: () => _push(const LoginScreen()),
              style: TextButton.styleFrom(foregroundColor: AppColors.ink2),
              child: const Text('Sign in'),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, AppSpacing.sm, 20, 0),
            child: Row(children: [
              const TitanCrown(size: 26),
              const SizedBox(width: AppSpacing.sm),
              Text('Trading Titans', style: AppFonts.sans(size: 16, weight: FontWeight.w700, color: AppColors.ink)),
            ]),
          ),
          Expanded(
            child: PageView(
              controller: _pages,
              onPageChanged: (i) => setState(() => _page = i),
              children: const [_HeroSlide(), _BalanceSlide()],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, AppSpacing.lg),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                for (var i = 0; i < 2; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: i == _page ? 24 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: i == _page ? AppColors.goldMid : AppColors.birch,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
              ]),
              const SizedBox(height: AppSpacing.lg),
              AuthPrimaryButton(
                label: last ? 'Create free account' : 'Continue',
                onPressed: last
                    ? () => _push(const RegisterScreen())
                    : () => _pages.nextPage(duration: const Duration(milliseconds: 280), curve: Curves.easeOutCubic),
              ),
              // Guests start with Rs 500; the consent checkbox lives on Sign in.
              TextButton(
                onPressed: () => _push(const LoginScreen()),
                style: TextButton.styleFrom(foregroundColor: AppColors.ink3, minimumSize: const Size.fromHeight(44)),
                child: const Text('Try as guest with ₹500'),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _HeroSlide extends StatelessWidget {
  const _HeroSlide();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
          AspectRatio(aspectRatio: 350 / 200, child: CustomPaint(painter: _HeroPainter(AppColors.bull, AppColors.bear, AppColors.titanGold))),
          const SizedBox(height: AppSpacing.xl),
          Text('Real markets.\nVirtual stakes.',
              style: AppFonts.sans(size: 34, weight: FontWeight.w700, color: AppColors.ink, height: 1.1, spacing: -0.6)),
          const SizedBox(height: AppSpacing.md),
          Text('Practise stocks, F&O, US equities and crypto with live prices and zero risk.',
              style: AppFonts.sans(size: 16, color: AppColors.ink3, height: 1.45)),
        ]),
      );
}

class _BalanceSlide extends StatelessWidget {
  const _BalanceSlide();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('YOUR STARTING BALANCE', style: AppText.sectionLabel.copyWith(color: AppColors.titanGold)),
          const SizedBox(height: AppSpacing.md),
          Text('₹1,100', style: AppFonts.mono(size: 64, weight: FontWeight.w600, color: AppColors.ink, spacing: -2)),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Demo cash to build a portfolio, compete in the weekly league and earn more through challenges. No card needed.',
            style: AppFonts.sans(size: 16, color: AppColors.ink3, height: 1.45),
          ),
          const SizedBox(height: AppSpacing.lg),
          Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.sm, children: [
            for (final f in const ['Live NSE prices', 'Real brokerage charges', 'Option greeks'])
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: AppCard.badge(AppColors.cream),
                child: Text(f, style: AppFonts.mono(size: 12, color: AppColors.ink2)),
              ),
          ]),
        ]),
      );
}

/// Candles climbing toward a gold crown, drawn in a 350 x 200 design space.
class _HeroPainter extends CustomPainter {
  _HeroPainter(this.up, this.down, this.gold);
  final Color up, down, gold;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 350;
    Offset o(double x, double y) => Offset(x * k, y * k);
    final line = Paint()
      ..color = up
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3 * k
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    const pts = [(20.0, 170.0), (80.0, 150.0), (130.0, 158.0), (190.0, 110.0), (240.0, 120.0), (300.0, 60.0), (330.0, 50.0)];
    canvas.drawPath(
        Path()
          ..moveTo(pts.first.$1 * k, pts.first.$2 * k)
          ..addPolygon([for (final p in pts) o(p.$1, p.$2)], false),
        line);
    const candles = [(70.0, 135.0, 30.0, true), (125.0, 145.0, 22.0, false), (185.0, 95.0, 34.0, true), (235.0, 108.0, 20.0, false), (295.0, 45.0, 36.0, true)];
    for (final (x, y, h, isUp) in candles) {
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x * k, y * k, 12 * k, h * k), Radius.circular(2 * k)),
          Paint()..color = isUp ? up : down);
    }
    canvas.drawPath(
        Path()
          ..moveTo(300 * k, 30 * k)
          ..lineTo(308 * k, 12 * k)
          ..lineTo(318 * k, 24 * k)
          ..lineTo(328 * k, 12 * k)
          ..lineTo(336 * k, 30 * k)
          ..close(),
        Paint()..color = gold);
  }

  @override
  bool shouldRepaint(_HeroPainter old) => old.up != up || old.down != down || old.gold != gold;
}
