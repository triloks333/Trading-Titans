import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../core/money.dart';
import '../../core/theme.dart';
import '../../services/supabase_service.dart';
import '../../widgets/auth_kit.dart';
import '../../widgets/error_state.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/upgrade_sheet.dart';

typedef CoachReportLoader = Future<Map<String, dynamic>> Function();

/// The weekly coach report (Pro and Titan).
///
/// Built on the server from fixed rules over the user's own trades (see
/// `coach_report_data` in 20261122100000_coach_paid_league_follow.sql). Paid
/// members get the latest Sunday report; free accounts see this week's stats and
/// the headline of each tip, with the advice itself blurred behind an upgrade.
class CoachReportScreen extends StatefulWidget {
  const CoachReportScreen({super.key, this.loader});

  /// Replaces the `my_coach_report` call (tests).
  final CoachReportLoader? loader;

  @override
  State<CoachReportScreen> createState() => _CoachReportScreenState();
}

class _CoachReportScreenState extends State<CoachReportScreen> {
  late Future<Map<String, dynamic>> _future = _load();

  Future<Map<String, dynamic>> _load() =>
      (widget.loader ?? SupabaseService().getCoachReport)();

  Future<void> _refresh() async {
    final next = _load();
    setState(() {
      _future = next;
    });
    await next;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                10,
                AppSpacing.lg,
                10,
              ),
              child: Row(
                children: [
                  AuthIconButton(
                    icon: Icons.arrow_back_rounded,
                    label: 'Back',
                    onTap: () => Navigator.of(context).maybePop(),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Weekly coach',
                      style: AppFonts.sans(
                        size: 20,
                        weight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: FutureBuilder<Map<String, dynamic>>(
                future: _future,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done)
                    return const ListSkeleton();
                  if (snap.hasError || snap.data == null) {
                    return ErrorState(
                      message:
                          "We couldn't load your report. Check your connection and try again.",
                      onRetry: _refresh,
                    );
                  }
                  final res = snap.data!;
                  final locked = res['locked'] == true;
                  final rep = Map<String, dynamic>.from(
                    (res['report'] as Map?) ?? const {},
                  );
                  final tips = [
                    for (final t in (rep['tips'] as List?) ?? const [])
                      Map<String, dynamic>.from(t as Map),
                  ];
                  return RefreshIndicator(
                    onRefresh: _refresh,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.lg,
                        0,
                        AppSpacing.lg,
                        AppSpacing.xl,
                      ),
                      children: [
                        Text(
                          res['week'] != null
                              ? 'Your report for this week'
                              : 'Your last 7 days',
                          style: AppFonts.sans(size: 13, color: AppColors.ink3),
                        ),
                        const SizedBox(height: 10),
                        _stats(rep),
                        const SizedBox(height: 18),
                        Text('WHAT TO WORK ON', style: AppText.sectionLabel),
                        const SizedBox(height: 8),
                        for (final t in tips) _tip(t, locked),
                        if (locked) ...[
                          const SizedBox(height: 6),
                          const LockedFeatureCard(
                            title: 'Read your full coach report',
                            message:
                                'Pro gets the advice behind every tip, a fresh report every Sunday evening and a push when it\'s ready.',
                            source: 'coach_report',
                          ),
                        ],
                        const SizedBox(height: 14),
                        Text(
                          'Based only on your own practice trades in this app. Educational, not investment advice.',
                          style: AppFonts.sans(size: 11, color: AppColors.ink4),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stats(Map<String, dynamic> r) {
    final pnl = (r['pnl'] as num?)?.toDouble() ?? 0;
    final best = r['best'] as Map?;
    final worst = r['worst'] as Map?;
    Widget cell(String label, String value, {Color? color}) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppFonts.sans(size: 11, color: AppColors.ink3)),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppFonts.mono(
              size: 15,
              weight: FontWeight.w700,
              color: color ?? AppColors.ink,
            ),
          ),
        ],
      ),
    );
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.pureWhite,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.birch),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              cell(
                'Realised P&L',
                Money.signedWallet(pnl, decimals: 0),
                color: pnl >= 0 ? AppColors.bull : AppColors.bear,
              ),
              cell('Win rate', '${r['win_rate'] ?? 0}%'),
              cell('Trades', '${r['orders'] ?? 0}'),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              cell('Days traded', '${r['days'] ?? 0}'),
              cell(
                'Charges',
                Money.wallet(
                  (r['charges'] as num?)?.toDouble() ?? 0,
                  decimals: 0,
                ),
              ),
              cell(
                'F&O P&L',
                Money.signedWallet(
                  (r['fo_pnl'] as num?)?.toDouble() ?? 0,
                  decimals: 0,
                ),
              ),
            ],
          ),
          if (best != null || worst != null) ...[
            const SizedBox(height: 12),
            if (best != null)
              Text(
                'Best: ${best['symbol']} ${Money.signedWallet((best['pnl'] as num).toDouble(), decimals: 0)}',
                style: AppFonts.sans(size: 12.5, color: AppColors.bull),
              ),
            if (worst != null)
              Text(
                'Worst: ${worst['symbol']} ${Money.signedWallet((worst['pnl'] as num).toDouble(), decimals: 0)}',
                style: AppFonts.sans(size: 12.5, color: AppColors.bear),
              ),
          ],
        ],
      ),
    );
  }

  Widget _tip(Map<String, dynamic> t, bool locked) {
    final sev = t['severity'] as String? ?? 'tip';
    final (icon, color) = switch (sev) {
      'warn' => (Icons.warning_amber_rounded, AppColors.bear),
      'good' => (Icons.thumb_up_alt_rounded, AppColors.bull),
      _ => (Icons.lightbulb_outline_rounded, AppColors.goldMid),
    };
    final body = (t['body'] as String?) ?? '';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.pureWhite,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.birch),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t['title'] as String? ?? '', style: AppText.bodyBold),
                const SizedBox(height: 4),
                if (locked)
                  GestureDetector(
                    onTap: () => showUpgradeSheet(
                      context,
                      title: 'Unlock your coach report',
                      message:
                          'See exactly what to change, with your own numbers, every week.',
                      source: 'coach_tip',
                    ),
                    child: ImageFiltered(
                      imageFilter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                      child: Text(
                        'Upgrade to Pro to read the advice for this tip, written from your own trades this week.',
                        style: AppFonts.sans(
                          size: 13,
                          color: AppColors.ink2,
                          height: 1.4,
                        ),
                      ),
                    ),
                  )
                else
                  Text(
                    body,
                    style: AppFonts.sans(
                      size: 13,
                      color: AppColors.ink2,
                      height: 1.4,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
