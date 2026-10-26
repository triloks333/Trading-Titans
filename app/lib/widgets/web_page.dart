import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_fonts/google_fonts.dart';

import '../core/app_constants.dart';
import '../core/theme.dart';

/// Lays a single-form page out as a full-bleed split screen in a desktop browser.
///
/// Used by the pages that have no sidebar to fill the window: sign in, register,
/// onboarding, password reset, maintenance and the hard-update gate.
///
/// A form is the one thing that must NOT take the full width — stretched across
/// a monitor the email field becomes a letterbox. But centring it alone leaves a
/// narrow card marooned in an empty window, which reads as a phone app in a
/// browser. So the form keeps its readable width and the other half of the
/// window is given something to do.
///
/// Mobile is untouched: [kIsWeb] is false there and the child is returned as-is.
/// A narrow browser window is also returned as-is, so the phone layout is what a
/// phone-sized window gets.
Widget webFormPage(Widget child) {
  if (!kIsWeb) return child;
  return LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth < AppConstants.webBreakpoint) return child;
      // Scaffold, not a bare Row: this sits directly under MaterialApp, and Text
      // with no Material ancestor is painted with Flutter's yellow "missing
      // default style" underlines.
      return Scaffold(
        backgroundColor: AppColors.parchment,
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Expanded(flex: 5, child: _BrandPanel()),
            Expanded(
              flex: 4,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                      maxWidth: AppConstants.webFormMaxWidth),
                  child: child,
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

/// The half of the sign-in window the form does not need.
///
/// Deliberately says only what is already true and already public — the same
/// three claims as the store listing. No screenshots or testimonials to keep in
/// sync with reality.
class _BrandPanel extends StatelessWidget {
  const _BrandPanel();

  static const _points = [
    ('Real market prices', 'NSE, BSE, US stocks and crypto, live.'),
    ('Virtual money only', 'Start with ₹1,100 in demo cash. Nothing to lose.'),
    ('Earn by playing', 'Complete challenges to unlock more demo capital.'),
  ];

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.ink,
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: 64, vertical: AppSpacing.xxl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // No wordmark here: the form on the right already carries the crown
            // and the name, and repeating them reads as a duplicated header.
            Text(
              'Learn the market\nwithout losing money.',
              style: GoogleFonts.inter(
                fontSize: 38,
                height: 1.15,
                fontWeight: FontWeight.w900,
                color: AppColors.pureWhite,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Trade real prices with virtual cash. Every order, position and '
              'profit behaves exactly as it would with your own money.',
              style: GoogleFonts.inter(
                fontSize: 14,
                height: 1.6,
                color: AppColors.pureWhite.withValues(alpha: 0.66),
              ),
            ),
            const SizedBox(height: AppSpacing.xxl),
            for (final p in _points)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 5),
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: AppColors.imperialGold,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            p.$1,
                            style: GoogleFonts.inter(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.pureWhite,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            p.$2,
                            style: GoogleFonts.inter(
                              fontSize: 12.5,
                              height: 1.45,
                              color:
                                  AppColors.pureWhite.withValues(alpha: 0.55),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
