import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme.dart';
import '../../core/money.dart';
import '../../models/challenge.dart';
import '../../services/supabase_service.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_state.dart';
import '../../widgets/skeleton.dart';
import 'glossary_quiz_screen.dart';

/// Challenges: earn demo cash and XP for trading milestones, habits and
/// learning. Conditions are evaluated server-side; this screen only displays
/// progress and asks for a re-evaluation on open and on pull-to-refresh.
class ChallengesScreen extends StatefulWidget {
  const ChallengesScreen({super.key});

  @override
  State<ChallengesScreen> createState() => _ChallengesScreenState();
}

class _ChallengesScreenState extends State<ChallengesScreen> {
  final SupabaseService _supabase = SupabaseService();

  bool _loading = true;
  Object? _error;
  List<Challenge> _challenges = [];
  Map<String, int> _stats = const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Ask the server to re-check conditions first, so anything earned since
      // the last visit is already granted by the time we read the list.
      await _supabase.evaluateChallenges();
      final results = await Future.wait([
        _supabase.getMyChallenges(),
        _supabase.getGamificationStats(),
      ]);
      if (!mounted) return;
      setState(() {
        _challenges = results[0] as List<Challenge>;
        _stats = results[1] as Map<String, int>;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Challenges',
            style: GoogleFonts.ibmPlexSans(fontWeight: FontWeight.w700, color: AppColors.ink)),
        backgroundColor: AppColors.pureWhite,
        foregroundColor: AppColors.ink,
        elevation: 0,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const ListSkeleton();
    if (_error != null) {
      return ErrorState(
        message: "We couldn't load your challenges. Check your connection and try again.",
        onRetry: _load,
      );
    }
    if (_challenges.isEmpty) {
      return EmptyState(
        icon: Icons.emoji_events_outlined,
        title: 'No challenges yet',
        message: 'Challenges will appear here once they go live.',
      );
    }

    final grouped = <String, List<Challenge>>{};
    for (final c in _challenges) {
      grouped.putIfAbsent(c.category, () => []).add(c);
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          _buildProgressHeader(),
          const SizedBox(height: AppSpacing.lg),
          for (final category in ChallengeCategory.all)
            if (grouped[category.key] != null) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm, top: AppSpacing.xs),
                child: Text(
                  category.label.toUpperCase(),
                  style: GoogleFonts.ibmPlexSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink4,
                      letterSpacing: 0.6),
                ),
              ),
              ...grouped[category.key]!.map(_buildChallengeCard),
              const SizedBox(height: AppSpacing.md),
            ],
        ],
      ),
    );
  }

  Widget _buildProgressHeader() {
    final xp = _stats['total_xp'] ?? 0;
    final streak = _stats['login_streak'] ?? 0;
    final level = TitanLevel.forXp(xp);
    final next = TitanLevel.nextAfter(xp);
    final progress = TitanLevel.progressToNext(xp);
    final earned = _challenges.fold<double>(0, (sum, c) => sum + c.totalEarned);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      // Titan gold: levels and rewards are the League family of colours.
      decoration: AppCard.primary.copyWith(border: Border.all(color: AppColors.titanGold)),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('TITAN LEVEL',
                      style: AppText.sectionLabel.copyWith(color: AppColors.titanGold)),
                  const SizedBox(height: 2),
                  Text(level.name,
                      style: AppFonts.sans(size: 24, weight: FontWeight.w700, color: AppColors.ink)),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 4),
                decoration: AppCard.badge(AppColors.goldPale),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.local_fire_department_rounded,
                        size: 14, color: AppColors.titanGold),
                    const SizedBox(width: 4),
                    Text('$streak day${streak == 1 ? '' : 's'}',
                        style: GoogleFonts.ibmPlexSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.titanGold)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: AppColors.cream,
              valueColor: AlwaysStoppedAnimation(AppColors.titanGold),
              semanticsLabel: 'Progress to next Titan level',
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('$xp XP',
                  style: GoogleFonts.ibmPlexSans(
                      fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.ink3)),
              Text(
                next == null ? 'Max level' : '${next.minXp - xp} XP to ${next.name}',
                style: GoogleFonts.ibmPlexSans(fontSize: 12, color: AppColors.ink4),
              ),
            ],
          ),
          if (earned > 0) ...[
            const SizedBox(height: AppSpacing.md),
            Divider(color: AppColors.birch, height: 1),
            const SizedBox(height: AppSpacing.md),
            Text('${Money.wallet(earned, decimals: 0)} earned from challenges',
                style: GoogleFonts.ibmPlexMono(fontFeatures: const [FontFeature.tabularFigures()], 
                    fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.bull)),
          ],
        ],
      ),
    );
  }

  Widget _buildChallengeCard(Challenge c) {
    final done = c.isComplete;
    final partial = c.isEarned && !done;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: AppCard.secondary,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: done ? AppColors.bullLight : AppColors.goldPale,
              shape: BoxShape.circle,
            ),
            child: Icon(
              done ? Icons.check_rounded : Icons.emoji_events_outlined,
              size: 20,
              color: done ? AppColors.bull : AppColors.imperialGold,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(c.title,
                    style: GoogleFonts.ibmPlexSans(
                        fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.ink)),
                const SizedBox(height: 2),
                Text(c.description,
                    style: GoogleFonts.ibmPlexSans(
                        fontSize: 12, color: AppColors.ink4, height: 1.35)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(Money.wallet(c.rewardAmount, decimals: 0),
                        style: GoogleFonts.ibmPlexMono(fontFeatures: const [FontFeature.tabularFigures()], 
                            fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.bull)),
                    Text('${c.xp} XP',
                        style: GoogleFonts.ibmPlexSans(fontSize: 11, color: AppColors.ink4)),
                    if (c.repeatLimit != null && c.repeatLimit! > 1)
                      Text('${c.timesEarned}/${c.repeatLimit} claimed',
                          style: GoogleFonts.ibmPlexSans(fontSize: 11, color: AppColors.ink4)),
                    if (partial)
                      Text('In progress',
                          style: GoogleFonts.ibmPlexSans(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppColors.imperialGold)),
                    // The quiz is the one challenge the user starts by hand.
                    if (c.key == 'glossary_graduate' && !done)
                      TextButton(
                        onPressed: () async {
                          await Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) => const GlossaryQuizScreen()));
                          _load();
                        },
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: const Size(0, 32),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text('Take the quiz',
                            style: GoogleFonts.ibmPlexSans(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppColors.imperialGold)),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
