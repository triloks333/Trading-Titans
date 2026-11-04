import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/theme.dart';

/// The PRO / TITAN pill shown beside a name, on the profile and the leaderboard.
///
/// Renders nothing for the free tier, which is the point. The pill this replaces
/// printed `profiles.plan` verbatim, and since nothing has ever written that
/// column, every one of the 193 accounts on the leaderboard displayed the literal
/// string "free_starter". A badge earns its space only when it distinguishes.
class PlanBadge extends StatelessWidget {
  const PlanBadge({super.key, required this.tier, this.compact = false});

  /// One of `free`, `pro`, `titan`. Anything else is treated as free.
  final String? tier;

  /// Tighter padding, for the leaderboard row where space is short.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final t = tier;
    if (t != 'pro' && t != 'titan') return const SizedBox.shrink();

    final isTitan = t == 'titan';
    final background = isTitan ? AppColors.violetLight : AppColors.goldPale;
    final foreground = isTitan ? AppColors.violet : AppColors.goldDeep;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : AppSpacing.sm,
        vertical: compact ? 2 : 4,
      ),
      decoration: AppCard.badge(background),
      child: Text(
        isTitan ? 'TITAN' : 'PRO',
        style: GoogleFonts.ibmPlexSans(
          fontSize: compact ? 9 : 10,
          fontWeight: FontWeight.w700,
          color: foreground,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
