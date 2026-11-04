import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../screens/main/subscribe_screen.dart';
import '../services/app_flags_service.dart';
import '../services/plan_service.dart';

/// The Diwali sale banner at the very top of home.
///
/// Shows only while `plan_catalogue` carries sale prices, so it switches itself
/// off when the sale's cron job restores prices, with no release. Same gate as
/// the Subscribe screen: hidden when monetisation is off and on iOS.
///
/// Design: https://claude.ai/artifact/9jb3bo8mmoftKpbtyQZLMA
class DiwaliSaleBanner extends StatefulWidget {
  const DiwaliSaleBanner({super.key});

  @override
  State<DiwaliSaleBanner> createState() => _DiwaliSaleBannerState();
}

class _DiwaliSaleBannerState extends State<DiwaliSaleBanner>
    with SingleTickerProviderStateMixin {
  // Created on first paint of the banner, not eagerly: a hidden banner (no sale
  // running) must not tick. dispose() only touches it if it exists, because
  // creating a ticker during dispose looks up a deactivated ancestor and throws.
  AnimationController? _clockOrNull;
  AnimationController get _clock => _clockOrNull ??= AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 3600),
      )..repeat();

  static const _gold = Color(0xFFFFD86B);
  static const _night = Color(0xFF1B0B2E);
  static const _blush = Color(0xFFF5D9C8);

  @override
  void dispose() {
    _clockOrNull?.dispose();
    super.dispose();
  }

  void _open() {
    HapticFeedback.lightImpact();
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SubscribeScreen(initialTabIndex: 0)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final plans = context.watch<PlanService>();
    final monetized = context.watch<AppFlagsService>().monetizationEnabled;
    if (!plans.saleActive || !monetized || (!kIsWeb && Platform.isIOS)) {
      return const SizedBox.shrink();
    }
    final ends = plans.saleEndsAt;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Semantics(
        button: true,
        label: 'Diwali sale, 50% off every pack. Open plans.',
        child: GestureDetector(
          onTap: _open,
          child: AnimatedBuilder(
            animation: _clock,
            builder: (context, _) {
              final t = _clock.value;
              final glow = (math.sin(t * 2 * math.pi) + 1) / 2;
              return Container(
                constraints: const BoxConstraints(minHeight: 196),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  gradient: const RadialGradient(
                    center: Alignment(0.7, 1.2),
                    radius: 1.4,
                    colors: [Color(0xFF8A2B0E), Color(0xFF4A1030), _night],
                    stops: [0, 0.45, 1],
                  ),
                  border: Border.all(color: _gold.withValues(alpha: 0.55 + 0.35 * glow)),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFF9628).withValues(alpha: 0.25 + 0.2 * glow),
                      blurRadius: 28 + 8 * glow,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(21),
                  child: Stack(
                    children: [
                      Positioned.fill(child: CustomPaint(painter: _SparkPainter(t))),
                      _sheen(t),
                      Positioned(
                        right: 18,
                        bottom: 14,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            CustomPaint(size: const Size(34, 48), painter: _DiyaPainter(t)),
                            const SizedBox(width: 10),
                            CustomPaint(size: const Size(42, 58), painter: _DiyaPainter(t + 0.35)),
                          ],
                        ),
                      ),
                      // Right padding keeps the copy clear of the diyas.
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 18, 96, 16),
                        child: _copy(ends),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _sheen(double t) {
    // Sweeps across in the first 60% of each cycle, then rests.
    final p = (t / 0.6).clamp(0.0, 1.0);
    return Positioned.fill(
      child: IgnorePointer(
        child: FractionalTranslation(
          translation: Offset(-1.6 + 5.8 * Curves.easeInOut.transform(p), 0),
          child: Transform(
            transform: Matrix4.skewX(-0.32),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: 0.22,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [
                    const Color(0xFFFFE6A0).withValues(alpha: 0),
                    const Color(0xFFFFE6A0).withValues(alpha: 0.18),
                    const Color(0xFFFFE6A0).withValues(alpha: 0),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _copy(DateTime? ends) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(color: _gold, borderRadius: BorderRadius.circular(999)),
              child: Text(
                'DIWALI SALE',
                style: GoogleFonts.ibmPlexSans(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                  color: _night,
                ),
              ),
            ),
            if (ends != null) ...[
              const SizedBox(width: 8),
              Text(
                'Ends ${DateFormat('d MMM').format(ends)}',
                style: GoogleFonts.ibmPlexSans(
                    fontSize: 11, fontWeight: FontWeight.w700, color: const Color(0xFFFFE9A8)),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        Text(
          '50% off\nevery pack',
          style: GoogleFonts.ibmPlexSerif(
            fontSize: 32,
            height: 1.02,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Pro, Titan and every top-up.',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.ibmPlexSans(fontSize: 12.5, height: 1.35, color: _blush),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
          decoration: BoxDecoration(color: _gold, borderRadius: BorderRadius.circular(999)),
          child: Text(
            'Claim 50% off',
            style: GoogleFonts.ibmPlexSans(fontSize: 13.5, fontWeight: FontWeight.w800, color: _night),
          ),
        ),
      ],
    );
  }
}

/// A diya: a clay bowl with a flickering two-tone flame. [t] is the cycle
/// position; offsetting it per lamp keeps the flames out of step.
class _DiyaPainter extends CustomPainter {
  final double t;
  _DiyaPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final flicker = 0.86 + 0.14 * ((math.sin(t * 2 * math.pi * 3) + 1) / 2);

    // Flame, scaled from its base so it stretches upward.
    final base = Offset(w / 2, h * 0.62);
    canvas.save();
    canvas.translate(base.dx, base.dy);
    canvas.scale(1, flicker);
    final outer = Path()
      ..moveTo(0, -h * 0.54)
      ..quadraticBezierTo(w * 0.22, -h * 0.25, w * 0.18, -h * 0.08)
      ..arcToPoint(Offset(-w * 0.18, -h * 0.08), radius: Radius.circular(w * 0.18))
      ..quadraticBezierTo(-w * 0.22, -h * 0.25, 0, -h * 0.54)
      ..close();
    canvas.drawPath(outer, Paint()..color = const Color(0xFFFFC14D));
    canvas.drawPath(
      outer,
      Paint()
        ..color = const Color(0xFFFFB020).withValues(alpha: 0.45)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.scale(0.5, 0.55);
    canvas.drawPath(outer, Paint()..color = const Color(0xFFFFF3C4));
    canvas.restore();

    // Bowl.
    final top = h * 0.62;
    final bowl = Path()
      ..moveTo(w * 0.04, top)
      ..lineTo(w * 0.96, top)
      ..quadraticBezierTo(w * 0.9, h * 0.98, w / 2, h * 0.98)
      ..quadraticBezierTo(w * 0.1, h * 0.98, w * 0.04, top)
      ..close();
    canvas.drawPath(bowl, Paint()..color = const Color(0xFFE07A1F));
    canvas.drawLine(
      Offset(w * 0.04, top),
      Offset(w * 0.96, top),
      Paint()
        ..color = const Color(0xFFFFD86B)
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_DiyaPainter old) => old.t != t;
}

/// Twinkling sparks across the top right.
class _SparkPainter extends CustomPainter {
  final double t;
  _SparkPainter(this.t);

  static const _sparks = [
    // x fraction, y px, radius, phase, colour
    (0.77, 28.0, 2.2, 0.0, Color(0xFFFFD86B)),
    (0.86, 62.0, 1.6, 0.25, Color(0xFFFFE9A8)),
    (0.67, 52.0, 1.4, 0.5, Color(0xFFFFB347)),
    (0.90, 20.0, 1.2, 0.75, Colors.white),
    (0.55, 18.0, 1.3, 0.4, Color(0xFFFFD86B)),
    (0.62, 84.0, 1.1, 0.9, Color(0xFFFFE9A8)),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    for (final (x, y, r, phase, colour) in _sparks) {
      final a = (math.sin((t * 1.5 + phase) * 2 * math.pi) + 1) / 2;
      canvas.drawCircle(
        Offset(size.width * x, y),
        r * (0.6 + 0.4 * a),
        Paint()..color = colour.withValues(alpha: 0.15 + 0.85 * a),
      );
    }
  }

  @override
  bool shouldRepaint(_SparkPainter old) => old.t != t;
}
