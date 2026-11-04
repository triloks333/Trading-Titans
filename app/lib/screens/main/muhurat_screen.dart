import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/market_hours.dart';
import '../../core/theme.dart';
import 'trade_screen.dart';
import 'watchlist_screen.dart';

/// IST wall-clock label for a UTC instant, e.g. "Sun 8 Nov · 6:00 PM IST".
String istLabel(DateTime utc, [String pattern = 'EEE d MMM · h:mm a']) =>
    '${DateFormat(pattern).format(utc.toUtc().add(const Duration(hours: 5, minutes: 30)))} IST';

/// "3d 04h 12m" / "04h 12m 09s": coarse far away, to the second inside a day.
String countdownLabel(Duration d) {
  String two(int n) => n.toString().padLeft(2, '0');
  if (d.isNegative) return '00h 00m 00s';
  return d.inDays > 0
      ? '${d.inDays}d ${two(d.inHours % 24)}h ${two(d.inMinutes % 60)}m'
      : '${two(d.inHours)}h ${two(d.inMinutes % 60)}m ${two(d.inSeconds % 60)}s';
}

/// Diwali Muhurat trading: timing, a live countdown and a way into the market.
/// Everything comes from `market_special_sessions`, so it shows what NSE announced.
class MuhuratScreen extends StatefulWidget {
  const MuhuratScreen({super.key});

  @override
  State<MuhuratScreen> createState() => _MuhuratScreenState();
}

class _MuhuratScreenState extends State<MuhuratScreen> {
  late final Timer _tick = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  bool _whatOpen = true;

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  void _push(Widget page) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now().toUtc();
    final s = MarketHours.nextSpecialSession(now);
    final live = s != null && !now.isBefore(s.start);
    final gold = AppColors.titanGold;

    return Scaffold(
      appBar: AppBar(title: Text('Diwali week', style: AppText.cardTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.xxl),
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.xl),
            decoration: AppCard.primary.copyWith(color: AppColors.titanGoldSoft, border: Border.all(color: gold)),
            child: Column(children: [
              Icon(Icons.local_fire_department_rounded, size: 44, color: gold),
              const SizedBox(height: AppSpacing.sm),
              Text('SAMVAT 2083 BEGINS', style: AppText.sectionLabel.copyWith(color: gold)),
              const SizedBox(height: AppSpacing.xs),
              Text(s?.name ?? 'Muhurat Trading',
                  style: AppFonts.sans(size: 28, weight: FontWeight.w700, color: AppColors.ink)),
              const SizedBox(height: AppSpacing.xs),
              Text(s == null ? 'Timing will appear here once NSE announces it' : '${istLabel(s.start)} – ${istLabel(s.end, 'h:mm a')}',
                  textAlign: TextAlign.center, style: AppText.body),
              if (s != null) ...[
                const SizedBox(height: AppSpacing.lg),
                Text(live ? 'LIVE NOW · ENDS IN' : 'STARTS IN', style: AppText.sectionLabel),
                const SizedBox(height: AppSpacing.xs),
                Text(countdownLabel((live ? s.end : s.start).difference(now)),
                    style: AppFonts.mono(size: 30, weight: FontWeight.w600, color: gold)),
              ],
            ]),
          ),
          const SizedBox(height: AppSpacing.lg),
          _Row(icon: Icons.candlestick_chart_rounded, title: 'Practise your Muhurat trade',
              subtitle: live ? 'The market is open for the Muhurat session' : 'Orders placed now fill when the session opens',
              onTap: () => _push(const TradeScreen())),
          _Row(icon: Icons.star_outline_rounded, title: 'Build your Muhurat watchlist',
              subtitle: 'Line up what you want to trade before the bell', onTap: () => _push(const WatchlistScreen())),
          const SizedBox(height: AppSpacing.sm),
          Container(
            decoration: AppCard.secondary,
            child: ExpansionTile(
              initiallyExpanded: _whatOpen,
              onExpansionChanged: (v) => _whatOpen = v,
              shape: const Border(),
              title: Text('What is Muhurat trading?', style: AppText.bodyBold),
              childrenPadding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
              children: [
                Text('A short, symbolic session NSE and BSE hold on Diwali to mark the start of the new Samvat year. '
                    'Many traders place a small, auspicious first trade. Trades settle like any normal session.',
                    style: AppText.body.copyWith(height: 1.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.title, required this.subtitle, required this.onTap});

  final IconData icon;
  final String title, subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: Material(
          color: AppColors.pureWhite,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg), side: BorderSide(color: AppColors.birch)),
          child: ListTile(
            onTap: onTap,
            leading: Icon(icon, color: AppColors.goldMid),
            title: Text(title, style: AppText.bodyBold),
            subtitle: Text(subtitle, style: AppText.bodySmall),
            trailing: Icon(Icons.chevron_right_rounded, color: AppColors.ink4),
          ),
        ),
      );
}
