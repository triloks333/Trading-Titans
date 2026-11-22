import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../services/churn_telemetry_service.dart';
import '../../services/nav_tab_service.dart';
import '../../services/supabase_service.dart';
import '../../services/theme_service.dart';
import '../../widgets/auth_kit.dart';
import '../../widgets/error_state.dart';
import '../../widgets/skeleton.dart';
import 'challenges_screen.dart';
import 'following_screen.dart';
import '../../services/plan_service.dart';
import '../../widgets/trader_sheet.dart';
import '../../widgets/upgrade_sheet.dart';
import '../../services/action_reaction_engine.dart';

/// The letter in a row's avatar. Names are user input, so blank, whitespace-only
/// and multi-code-unit names must not throw (that would blank the whole tab).
String avatarInitial(String? name) {
  final trimmed = (name ?? '').trim();
  if (trimmed.isEmpty) return '?';
  return trimmed.characters.first.toUpperCase();
}

/// How a user's own standing is described, given their zero-based rank.
String standingLabel(int index) {
  if (index <= 0) return 'Top of the board';
  return '$index trader${index == 1 ? '' : 's'} ahead of you';
}

/// Time left until the league resets: Monday 00:00 IST.
Duration leagueTimeLeft([DateTime? now]) {
  final ist = (now ?? DateTime.now()).toUtc().add(const Duration(hours: 5, minutes: 30));
  final monday = DateTime.utc(ist.year, ist.month, ist.day).add(Duration(days: 8 - ist.weekday));
  return monday.difference(ist);
}

/// "2d 14h 08m".
String leagueCountdown(Duration d) =>
    '${d.inDays}d ${(d.inHours % 24).toString().padLeft(2, '0')}h ${(d.inMinutes % 60).toString().padLeft(2, '0')}m';

/// What the caller needs to climb into the next tier of the board.
String leagueGapLabel(List<Map<String, dynamic>> rows, Map<String, dynamic>? me) {
  if (me == null) return 'Close 2 trades this week to get ranked';
  final rank = me['rank'] as int?;
  final trades = (me['trades'] as num?)?.toInt() ?? 0;
  if (rank == null) {
    final need = 2 - trades;
    return need <= 0 ? 'Ranked after your next close' : 'Close $need more trade${need == 1 ? '' : 's'} to get ranked';
  }
  if (rank == 1) return 'Top of the board';
  final target = rank <= 3 ? rank - 1 : rank <= 10 ? 3 : rank <= 25 ? 10 : 25;
  final above = rows.where((r) => r['rank'] == target).firstOrNull;
  if (above == null) return standingLabel(rank - 1);
  final gap = ((above['pnl_pct'] as num?)?.toDouble() ?? 0) - ((me['pnl_pct'] as num?)?.toDouble() ?? 0);
  final where = target <= 3 ? '#$target' : 'top $target';
  return '+${gap.abs().toStringAsFixed(2)}% more to reach $where';
}

typedef LeagueLoader = Future<List<Map<String, dynamic>>> Function(String scope);

/// The Weekly League: realised return %, resets Monday 00:00 IST, top 10 paid.
class CompeteScreen extends StatefulWidget {
  const CompeteScreen({super.key, this.loader});

  /// Replaces the `league_board` call (tests).
  final LeagueLoader? loader;

  @override
  State<CompeteScreen> createState() => _CompeteScreenState();
}

class _CompeteScreenState extends State<CompeteScreen> {
  static const _scopes = {'This week': 'week', 'Pro': 'paid', 'All-time': 'all', 'Friends': 'friends'};
  String _scope = 'week';
  late Future<List<Map<String, dynamic>>> _future = _load();
  late final Timer _tick = Timer.periodic(const Duration(minutes: 1), (_) => setState(() {}));

  Future<List<Map<String, dynamic>>> _load() => (widget.loader ?? SupabaseService().getLeagueBoard)(_scope);

  Future<void> _refresh() async {
    final next = _load();
    // A block body: an arrow would return the Future, which setState rejects.
    setState(() {
      _future = next;
    });
    await next;
  }

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 10, AppSpacing.lg, 10),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Weekly League', style: AppFonts.sans(size: 22, weight: FontWeight.w700, color: AppColors.ink)),
                  Text(
                    _scope == 'all'
                        ? 'All-time · ranked by realised P&L %'
                        : 'Ends in ${leagueCountdown(leagueTimeLeft())} · ranked by realised P&L %',
                    style: AppFonts.mono(size: 12, color: AppColors.ink4),
                  ),
                ]),
              ),
              AuthIconButton(
                icon: Icons.people_alt_outlined,
                label: 'Following',
                onTap: () {
                  ChurnTelemetryService.instance.recordButtonTap('compete_header_following_icon_btn');
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FollowingScreen()));
                },
              ),
              const SizedBox(width: 8),
              AuthIconButton(
                icon: Icons.track_changes_rounded,
                label: 'Challenges',
                onTap: () {
                  ChurnTelemetryService.instance.recordButtonTap('compete_header_challenges_icon_btn');
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ChallengesScreen()));
                },
              ),
              const SizedBox(width: 8),
              ListenableBuilder(
                listenable: ThemeService(),
                builder: (_, _) => AuthIconButton(
                  icon: AppColors.isDark ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
                  label: 'Toggle light or dark theme',
onTap: () {
                    ChurnTelemetryService.instance.recordButtonTap('global_theme_dark_light_toggle');
                    ThemeService().setThemeMode(AppColors.isDark ? ThemeMode.light : ThemeMode.dark);
                  },
                ),
              ),
            ]),
          ),
          Padding(padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, 10), child: _segmented()),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) return const ListSkeleton();
                if (snap.hasError) {
                  return ErrorState(message: "We couldn't load the league. Check your connection and try again.", onRetry: _refresh);
                }
                final rows = snap.data ?? const [];
                final ranked = rows.where((r) => r['rank'] != null).toList();
                final me = rows.where((r) => r['is_me'] == true).firstOrNull;
                return Column(children: [
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: _refresh,
                      child: ListView(physics: const AlwaysScrollableScrollPhysics(), children: [
                        if (_scope == 'paid' && !PlanService.instance.hasProTools)
                          const Padding(
                            padding: EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, 12),
                            child: LockedFeatureCard(
                              title: 'Join the Pro League',
                              message: 'A weekly league for Pro and Titan members only. The top 3 win up to ₹25,000 demo cash and a champion badge every Monday.',
                              source: 'pro_league',
                            ),
                          ),
                        if (ranked.isEmpty)
                          _empty()
                        else ...[
                          _podium(ranked.take(3).toList()),
                          if (_scope == 'paid') _proPrizeCard() else if (_scope != 'all') _prizeCard(),
                          for (final r in ranked.skip(3)) _row(r),
                        ],
                      ]),
                    ),
                  ),
                  _myBar(rows, me),
                ]);
              },
            ),
          ),
        ]),
      ),
    );
  }

  Widget _segmented() => Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: AppColors.cream, borderRadius: BorderRadius.circular(AppRadius.md)),
        child: Row(children: [
          for (final (i, MapEntry(key: label, value: scope)) in _scopes.entries.indexed) ...[
            if (i > 0) const SizedBox(width: 4),
            Expanded(
              child: Semantics(
                button: true,
                selected: _scope == scope,
                label: label,
                excludeSemantics: true,
                child: GestureDetector(
                  onTap: () {
                    final id = const {'week': 'compete_scope_this_week_pill', 'paid': 'compete_scope_pro_pill', 'all': 'compete_scope_all_time_pill', 'friends': 'compete_scope_friends_pill'}[scope];
                    if (id != null) ChurnTelemetryService.instance.recordButtonTap(id);
                    if (_scope == scope) return;
                    _scope = scope;
                    _refresh();
                  },
                  child: Container(
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: _scope == scope ? AppColors.pureWhite : Colors.transparent, borderRadius: BorderRadius.circular(7)),
                    child: Text(label, style: AppFonts.sans(size: 13, weight: FontWeight.w600, color: _scope == scope ? AppColors.ink : AppColors.ink3)),
                  ),
                ),
              ),
            ),
          ],
        ]),
      );

  String _pct(Map<String, dynamic> r) {
    final v = (r['pnl_pct'] as num?)?.toDouble() ?? 0;
    return '${v >= 0 ? '+' : '−'}${v.abs().toStringAsFixed(2)}%';
  }

  Color _tone(Map<String, dynamic> r) => ((r['pnl_pct'] as num?) ?? 0) >= 0 ? AppColors.bull : AppColors.bear;

  Widget _avatar(String? name, {double size = 36, Color? border, Color? fill, Color? fg, String? text}) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: fill ?? AppColors.cream,
          shape: BoxShape.circle,
          border: border == null ? null : Border.all(color: border, width: 2),
        ),
        child: Text(text ?? avatarInitial(name), style: AppFonts.sans(size: size > 40 ? 15 : 13, weight: FontWeight.w600, color: fg ?? AppColors.ink3)),
      );

  Widget _podium(List<Map<String, dynamic>> top) {
    Widget slot(int place) {
      final r = top.length >= place ? top[place - 1] : null;
      final first = place == 1;
      final silver = AppColors.isDark ? const Color(0xFFC9D3E0) : const Color(0xFF5B677A);
      final bronze = AppColors.isDark ? const Color(0xFFD99A6C) : const Color(0xFF8C4B1F);
      final color = first ? AppColors.titanGold : place == 2 ? silver : bronze;
      return Expanded(
        child: GestureDetector(
          onTap: r == null || r['is_me'] == true || r['user_id'] == null ? null : () => showTraderSheet(context, r['user_id'] as String),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (first) Icon(Icons.emoji_events_rounded, color: AppColors.titanGold, size: 20),
          _avatar(r?['name'] as String?, size: first ? 48 : 36, border: first ? AppColors.titanGold : null),
          const SizedBox(height: 6),
          Text(r == null ? '—' : (r['name'] as String? ?? '').trim().isEmpty ? 'Titan' : r['name'] as String,
              maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
              style: AppFonts.sans(size: first ? 13 : 12, weight: first ? FontWeight.w700 : FontWeight.w600, color: AppColors.ink)),
          Text(r == null ? '' : _pct(r), style: AppFonts.mono(size: first ? 13 : 12, color: r == null ? AppColors.ink4 : _tone(r))),
          const SizedBox(height: 6),
          Container(
            height: first ? 96 : place == 2 ? 70 : 54,
            width: double.infinity,
            alignment: Alignment.topCenter,
            padding: const EdgeInsets.only(top: 8),
            decoration: BoxDecoration(
              color: first ? AppColors.titanGoldSoft : AppColors.cream,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
            ),
            child: Text('$place', style: AppFonts.mono(size: 22, weight: FontWeight.w700, color: color)),
          ),
        ]),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.birch))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [slot(2), const SizedBox(width: 8), slot(1), const SizedBox(width: 8), slot(3)]),
    );
  }

  /// Prize amounts as paid by award_weekly_podium() through the challenges table.
  Widget _prizeCard() => Container(
        margin: const EdgeInsets.fromLTRB(AppSpacing.lg, 12, AppSpacing.lg, 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.titanGoldSoft,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.titanGold),
        ),
        child: Row(children: [
          Icon(Icons.card_giftcard_rounded, color: AppColors.titanGold),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(TextSpan(style: AppFonts.sans(size: 13, color: AppColors.ink), children: [
              const TextSpan(text: 'Top 10 win demo cash + a Titan badge: '),
              TextSpan(text: '₹2,500 · ₹1,500 · ₹1,000', style: AppFonts.mono(size: 13, weight: FontWeight.w600, color: AppColors.ink)),
              const TextSpan(text: ' for the podium, '),
              TextSpan(text: '₹500', style: AppFonts.mono(size: 13, weight: FontWeight.w600, color: AppColors.ink)),
              const TextSpan(text: ' for 4th–10th. Paid Monday.'),
            ])),
          ),
        ]),
      );

  Widget _proPrizeCard() => Container(
        margin: const EdgeInsets.fromLTRB(AppSpacing.lg, 12, AppSpacing.lg, 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.violetLight,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.violet),
        ),
        child: Row(children: [
          Icon(Icons.workspace_premium_rounded, color: AppColors.violet),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(TextSpan(style: AppFonts.sans(size: 13, color: AppColors.ink), children: [
              const TextSpan(text: 'Pro and Titan members only. Top 3 win demo cash and a champion badge: '),
              TextSpan(text: '₹25,000 · ₹15,000 · ₹10,000', style: AppFonts.mono(size: 13, weight: FontWeight.w600, color: AppColors.ink)),
              const TextSpan(text: '. Paid Monday. Tap anyone to follow them.'),
            ])),
          ),
        ]),
      );

  Widget _row(Map<String, dynamic> r) => InkWell(
        onTap: r['is_me'] == true || r['user_id'] == null ? null : () => showTraderSheet(context, r['user_id'] as String),
        child: _rowBody(r),
      );

  Widget _rowBody(Map<String, dynamic> r) => Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 10),
        decoration: BoxDecoration(
          color: r['is_me'] == true ? AppColors.goldPale : null,
          border: Border(bottom: BorderSide(color: AppColors.birch)),
        ),
        child: Row(children: [
          SizedBox(width: 24, child: Text('${r['rank']}', textAlign: TextAlign.right, style: AppFonts.mono(size: 13, color: AppColors.ink4))),
          const SizedBox(width: 12),
          _avatar(r['name'] as String?),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text((r['name'] as String? ?? '').trim().isEmpty ? 'Titan' : r['name'] as String,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.bodyBold),
              Text('${r['trades']} trades', style: AppFonts.sans(size: 12, color: AppColors.ink4)),
            ]),
          ),
          Text(_pct(r), style: AppFonts.mono(size: 14, weight: FontWeight.w600, color: _tone(r))),
        ]),
      );

  Widget _empty() => Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(children: [
          Icon(Icons.emoji_events_outlined, size: 44, color: AppColors.ink4),
          const SizedBox(height: AppSpacing.md),
          Text(_scope == 'friends' ? 'No friends ranked yet' : 'Nobody ranked yet', style: AppText.bodyBold),
          const SizedBox(height: 4),
          Text(
            _scope == 'friends'
                ? 'Friends are people you referred or who referred you. Invite someone from Refer & earn.'
                : 'Close 2 trades in profit this week and you could be the first name here.',
            textAlign: TextAlign.center,
            style: AppText.bodySmall,
          ),
          const SizedBox(height: AppSpacing.md),
          OutlinedButton(onPressed: () => NavTabService.goToTab(NavTabService.trade), child: const Text('Place a trade')),
        ]),
      );

  /// Pinned "Your position" bar with the gap to the next tier.
  Widget _myBar(List<Map<String, dynamic>> rows, Map<String, dynamic>? me) {
    final rank = me?['rank'] as int?;
    if (rank != null) ActionReactionEngine.instance.leagueNearMiss(rank, leagueGapLabel(rows, me));
    return _myBarBody(rows, me);
  }

  Widget _myBarBody(List<Map<String, dynamic>> rows, Map<String, dynamic>? me) => Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 12),
        decoration: BoxDecoration(color: AppColors.goldPale, border: Border(top: BorderSide(color: AppColors.goldMid))),
        child: Row(children: [
          SizedBox(
            width: 24,
            child: Text(me?['rank'] == null ? '—' : '${me!['rank']}',
                textAlign: TextAlign.right, style: AppFonts.mono(size: 13, weight: FontWeight.w700, color: AppColors.goldMid)),
          ),
          const SizedBox(width: 12),
          _avatar(null, text: 'You', fill: AppColors.imperialGold, fg: Colors.white),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Your position', style: AppText.bodyBold),
              Text(leagueGapLabel(rows, me), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppFonts.sans(size: 12, color: AppColors.ink4)),
            ]),
          ),
          if (me != null) Text(_pct(me), style: AppFonts.mono(size: 14, weight: FontWeight.w600, color: _tone(me))),
        ]),
      );
}
