import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme.dart';
import '../../core/money.dart';
import '../../services/supabase_service.dart';
import '../../services/nav_tab_service.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_state.dart';
import '../../widgets/plan_badge.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/trend_arrow.dart';

/// The letter shown in a row's avatar circle.
///
/// Top-level and pure so it can be tested: names arrive from user input via the
/// `leaderboard` view, so blank, whitespace-only and non-Latin names all reach
/// this, and `name[0]` on an empty string throws — which would take the whole
/// league down rather than one row.
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

/// The weekly league table.
///
/// Built to the same rules as the other primary tabs: no AppBar (Wallet and
/// Profile put their title in the body, and a tab has nothing to navigate back
/// to), `AppCard`/`AppText`/`AppColors` for every surface, `ListSkeleton` while
/// loading, and `EmptyState` when there is nothing to show. Before this it used a
/// bare CircularProgressIndicator, a centred Text for empty, emoji medals and
/// raw TextStyles, which is why it read as a different app.
class CompeteScreen extends StatefulWidget {
  const CompeteScreen({super.key});

  @override
  State<CompeteScreen> createState() => _CompeteScreenState();
}

class _CompeteScreenState extends State<CompeteScreen> {
  final SupabaseService _supabase = SupabaseService();
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  /// Held in a field rather than built inline in the FutureBuilder: an inline
  /// future is recreated on every rebuild, so the list refetched whenever the
  /// theme or a parent changed and flashed the skeleton each time.
  Future<List<Map<String, dynamic>>> _load() async {
    final userId = _supabase.currentUser?.id;
    final rows = await _supabase.getLeaderboard();
    for (final row in rows) {
      row['is_self'] = row['user_id'] == userId;
    }
    return rows;
  }

  Future<void> _refresh() async {
    final next = _load();
    setState(() => _future = next);
    await next;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const _LeagueSkeleton();
            }
            if (snapshot.hasError) {
              return ErrorState(
                message:
                    "We couldn't load the league. Check your connection and try again.",
                onRetry: _refresh,
              );
            }

            final rows = snapshot.data ?? const <Map<String, dynamic>>[];
            final myIndex = rows.indexWhere((r) => r['is_self'] == true);

            return RefreshIndicator(
              onRefresh: _refresh,
              color: AppColors.imperialGold,
              child: rows.isEmpty
                  ? EmptyState(
                      icon: Icons.emoji_events_outlined,
                      title: 'Nobody on the board yet',
                      message:
                          'The league ranks traders by realised profit. Close a '
                          'trade in the green and you will be the first name here.',
                      actionLabel: 'Place a trade',
                      onAction: () => NavTabService.goToTab(NavTabService.trade),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(
                          AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.xl),
                      children: [
                        _header(),
                        const SizedBox(height: AppSpacing.md),
                        if (myIndex >= 0) ...[
                          _myRankCard(rows[myIndex], myIndex),
                          const SizedBox(height: AppSpacing.lg),
                        ],
                        _sectionLabel(
                            rows.length > 3 ? 'TOP THREE' : 'STANDINGS'),
                        const SizedBox(height: AppSpacing.sm),
                        for (var i = 0; i < rows.length && i < 3; i++) ...[
                          _podiumCard(rows[i], i),
                          const SizedBox(height: AppSpacing.sm),
                        ],
                        if (rows.length > 3) ...[
                          const SizedBox(height: AppSpacing.md),
                          _sectionLabel('EVERYONE ELSE'),
                          const SizedBox(height: AppSpacing.sm),
                          for (var i = 3; i < rows.length; i++) ...[
                            _rankRow(rows[i], i),
                            const SizedBox(height: 6),
                          ],
                        ],
                      ],
                    ),
            );
          },
        ),
      ),
    );
  }

  // ── pieces ────────────────────────────────────────────────────────────────

  Widget _header() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Weekly League',
              style: GoogleFonts.ibmPlexSans(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  color: AppColors.ink,
                  letterSpacing: -0.5)),
          const SizedBox(height: 2),
          Text('Ranked by realised profit. Resets every Monday.',
              style: AppText.bodySmall),
        ],
      );

  Widget _sectionLabel(String text) =>
      Text(text, style: AppText.sectionLabel);

  /// Your own standing, given the focal card the other tabs open with.
  Widget _myRankCard(Map<String, dynamic> row, int index) {
    final pnl = _pnl(row);
    final ahead = index;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: AppCard.primary,
      child: Row(
        children: [
          _rankMedal(index, large: true),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('YOUR POSITION', style: AppText.sectionLabel),
                const SizedBox(height: 2),
                Text(
                  standingLabel(ahead),
                  style: GoogleFonts.ibmPlexSans(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                children: [
                  TrendArrow(isPositive: pnl >= 0, size: 18),
                  Text(Money.wallet(pnl.abs()),
                      style: GoogleFonts.ibmPlexSans(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: pnl >= 0 ? AppColors.bull : AppColors.bear,
                          letterSpacing: -0.3)),
                ],
              ),
              Text('realised', style: GoogleFonts.ibmPlexSans(fontSize: 10, color: AppColors.ink5)),
            ],
          ),
        ],
      ),
    );
  }

  /// Top three. Same anatomy as a normal row, just given more room and a tinted
  /// edge — rather than a separate layout, which is how the two drifted apart
  /// before.
  Widget _podiumCard(Map<String, dynamic> row, int index) {
    final isSelf = row['is_self'] == true;
    final pnl = _pnl(row);
    final accent = _podiumColor(index);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: isSelf ? AppColors.goldPale : AppColors.pureWhite,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: accent.withValues(alpha: 0.55), width: 1.4),
        boxShadow: AppShadows.sm,
      ),
      child: Row(
        children: [
          _rankMedal(index),
          const SizedBox(width: AppSpacing.md),
          _avatar(row['name'] as String?, accent),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: _nameBlock(row, isSelf, bold: true)),
          _pnlBlock(pnl, row),
        ],
      ),
    );
  }

  /// Rank 4 and below: shorter, quieter, still the same reading order.
  Widget _rankRow(Map<String, dynamic> row, int index) {
    final isSelf = row['is_self'] == true;
    final pnl = _pnl(row);

    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm + 2),
      decoration: BoxDecoration(
        color: isSelf ? AppColors.goldPale : AppColors.pureWhite,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
            color: isSelf ? AppColors.goldBorder : AppColors.birch),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 26,
            child: Text('${index + 1}',
                textAlign: TextAlign.center,
                style: GoogleFonts.ibmPlexSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink4)),
          ),
          const SizedBox(width: AppSpacing.sm),
          _avatar(row['name'] as String?, AppColors.imperialGold, size: 32),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: _nameBlock(row, isSelf)),
          _pnlBlock(pnl, row, compact: true),
        ],
      ),
    );
  }

  /// Rank 1-3 get a medal; a crown marks the leader. Deliberately Material icons
  /// and theme colours rather than 🥇🥈🥉 — the emoji rendered differently on
  /// every device and matched nothing else in the app.
  Widget _rankMedal(int index, {bool large = false}) {
    final accent = _podiumColor(index);
    final size = large ? 46.0 : 38.0;
    final onPodium = index < 3;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: onPodium ? accent.withValues(alpha: 0.14) : AppColors.cream,
        shape: BoxShape.circle,
        border: Border.all(
            color: onPodium ? accent.withValues(alpha: 0.5) : AppColors.birch),
      ),
      child: index == 0
          ? Icon(Icons.workspace_premium_rounded,
              size: large ? 26 : 22, color: accent)
          : Center(
              child: Text('${index + 1}',
                  style: GoogleFonts.ibmPlexSans(
                      fontSize: large ? 18 : 15,
                      fontWeight: FontWeight.w900,
                      color: onPodium ? accent : AppColors.ink4)),
            ),
    );
  }

  /// Initial-in-a-circle. There are no profile photos on the leaderboard — the
  /// view deliberately exposes only safe columns — so this gives each row a
  /// visual anchor without inventing data.
  Widget _avatar(String? name, Color accent, {double size = 38}) {
    final initial = avatarInitial(name);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(initial,
            style: GoogleFonts.ibmPlexSans(
                fontSize: size * 0.42,
                fontWeight: FontWeight.w800,
                color: accent)),
      ),
    );
  }

  Widget _nameBlock(Map<String, dynamic> row, bool isSelf, {bool bold = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                (row['name'] as String?)?.trim().isNotEmpty == true
                    ? row['name'] as String
                    : 'Anonymous Titan',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.ibmPlexSans(
                    fontSize: bold ? 15 : 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink),
              ),
            ),
            if (isSelf) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: AppCard.badge(AppColors.imperialGold),
                child: Text('YOU',
                    style: AppText.badge.copyWith(
                        fontSize: 9, color: AppColors.pureWhite)),
              ),
            ],
            if (row['tier'] != null && row['tier'] != 'free') ...[
              const SizedBox(width: 6),
              PlanBadge(tier: row['tier'] as String?, compact: true),
            ],
          ],
        ),
      ],
    );
  }

  Widget _pnlBlock(double pnl, Map<String, dynamic> row, {bool compact = false}) {
    final positive = pnl >= 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Row(
          children: [
            TrendArrow(isPositive: positive, size: compact ? 14 : 16),
            Text(Money.wallet(pnl.abs()),
                style: GoogleFonts.ibmPlexSans(
                    fontSize: compact ? 13 : 15,
                    fontWeight: FontWeight.w800,
                    color: positive ? AppColors.bull : AppColors.bear)),
          ],
        ),
        if (!compact)
          Text('realised P&L',
              style: GoogleFonts.ibmPlexSans(fontSize: 10, color: AppColors.ink5)),
      ],
    );
  }

  // ── helpers ───────────────────────────────────────────────────────────────

  double _pnl(Map<String, dynamic> row) =>
      (row['realized_pnl'] as num?)?.toDouble() ?? 0;

  // No _wallet helper: the board ranks on realised P&L and now shows only that.
  // A wallet balance beside a rank invited the comparison it is worst at — it is
  // mostly a function of top-ups and starting cash, not of trading well.

  /// Gold, silver, bronze for the podium; brand blue for everyone else. These are
  /// the only non-theme colours on the screen, and they are here because a medal
  /// that is not metal-coloured stops reading as a medal.
  Color _podiumColor(int index) {
    switch (index) {
      case 0:
        return AppColors.crown;
      case 1:
        return const Color(0xFF8E9AA8);
      case 2:
        return const Color(0xFFB1703C);
      default:
        return AppColors.imperialGold;
    }
  }
}

/// Loading placeholder shaped like the real screen: heading, your-rank card, then
/// rows. A generic spinner told the user nothing about what was arriving.
class _LeagueSkeleton extends StatelessWidget {
  const _LeagueSkeleton();

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.xl),
        children: [
          const SkeletonBox(width: 190, height: 26),
          const SizedBox(height: AppSpacing.sm),
          const SkeletonBox(width: 220, height: 12),
          const SizedBox(height: AppSpacing.lg),
          Container(
            height: 78,
            decoration: BoxDecoration(
              color: AppColors.sand,
              borderRadius: BorderRadius.circular(AppRadius.xl),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          const SkeletonBox(width: 80, height: 10),
          const SizedBox(height: AppSpacing.md),
          for (var i = 0; i < 6; i++)
            Container(
              height: i < 3 ? 64 : 52,
              margin: const EdgeInsets.only(bottom: AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.sand,
                borderRadius: BorderRadius.circular(AppRadius.lg),
              ),
            ),
        ],
      ),
    );
  }
}
