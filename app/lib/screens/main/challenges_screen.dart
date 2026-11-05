import 'package:flutter/material.dart';

import '../../core/money.dart';
import '../../core/theme.dart';
import '../../models/challenge.dart';
import '../../services/supabase_service.dart';
import '../../services/theme_service.dart';
import '../../widgets/auth_kit.dart';
import '../../widgets/error_state.dart';
import '../../widgets/skeleton.dart';
import 'glossary_quiz_screen.dart';

/// "2 of 3", "₹1,240 of ₹2,200", or what is left when there is no measure.
String challengeProgressLabel(Challenge c) {
  if (c.isComplete) return 'Earned ${Money.wallet(c.totalEarned, decimals: 0)}';
  final p = c.progress, t = c.target;
  if (p != null && t != null) {
    return c.isMoneyMeasure
        ? '${Money.wallet(p, decimals: 0)} of ${Money.wallet(t, decimals: 0)}'
        : '${p.round()} of ${t.round()}';
  }
  if (c.repeatLimit == null) return c.isEarned ? 'Won ${c.timesEarned}×' : 'Repeatable';
  if (c.repeatLimit! > 1) return '${c.timesEarned} of ${c.repeatLimit} claimed';
  return 'Not started';
}

typedef ChallengesLoader = Future<(List<Challenge>, Map<String, int>)> Function();

/// Challenges: demo cash and XP for milestones, habits and learning. Conditions
/// are evaluated server-side; this screen asks for a re-check on open and on
/// pull-to-refresh, then shows progress.
class ChallengesScreen extends StatefulWidget {
  const ChallengesScreen({super.key, this.loader});

  /// Replaces the evaluate + fetch round trip (tests).
  final ChallengesLoader? loader;

  @override
  State<ChallengesScreen> createState() => _ChallengesScreenState();
}

class _ChallengesScreenState extends State<ChallengesScreen> {
  final SupabaseService _supabase = SupabaseService();
  bool _loading = true;
  Object? _error;
  List<Challenge> _challenges = [];
  Map<String, int> _stats = const {};
  bool _completedTab = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<(List<Challenge>, Map<String, int>)> _fetch() async {
    // Re-check conditions first so anything earned since the last visit is
    // granted before the list is read.
    await _supabase.evaluateChallenges();
    final r = await Future.wait([_supabase.getMyChallenges(), _supabase.getGamificationStats()]);
    return (r[0] as List<Challenge>, r[1] as Map<String, int>);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final (list, stats) = await (widget.loader ?? _fetch)();
      if (!mounted) return;
      setState(() {
        _challenges = list;
        _stats = stats;
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

  Future<void> _openQuiz() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const GlossaryQuizScreen()));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 10, AppSpacing.lg, 10),
            child: Row(children: [
              AuthIconButton(icon: Icons.arrow_back_rounded, label: 'Back', onTap: () => Navigator.of(context).maybePop()),
              const SizedBox(width: 10),
              Expanded(child: Text('Challenges', style: AppFonts.sans(size: 20, weight: FontWeight.w700, color: AppColors.ink))),
              ListenableBuilder(
                listenable: ThemeService(),
                builder: (_, _) => AuthIconButton(
                  icon: AppColors.isDark ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
                  label: 'Toggle light or dark theme',
                  onTap: () => ThemeService().setThemeMode(AppColors.isDark ? ThemeMode.light : ThemeMode.dark),
                ),
              ),
            ]),
          ),
          Expanded(child: _body()),
        ]),
      ),
    );
  }

  Widget _body() {
    if (_loading) return const ListSkeleton();
    if (_error != null) {
      return ErrorState(message: "We couldn't load your challenges. Check your connection and try again.", onRetry: _load);
    }
    final done = _challenges.where((c) => c.isComplete).toList();
    final open = _challenges.where((c) => !c.isComplete).toList()
      // Closest to finishing first, so the next win is at the top.
      ..sort((a, b) => (b.fraction ?? -1).compareTo(a.fraction ?? -1));
    final quiz = _challenges.where((c) => c.key == 'glossary_graduate').firstOrNull;
    return Column(children: [
      _levelCard(),
      _tabs(open.length, done.length),
      Expanded(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 12, AppSpacing.lg, AppSpacing.lg),
            children: [
              if (!_completedTab) ...[_quizCard(quiz), const SizedBox(height: 10)],
              if ((_completedTab ? done : open).isEmpty)
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: Text(_completedTab ? 'Nothing completed yet. Your first trade earns First Blood.' : 'Every challenge is done. New ones arrive soon.',
                      textAlign: TextAlign.center, style: AppText.body),
                ),
              for (final c in _completedTab ? done : open) ...[_card(c), const SizedBox(height: 10)],
            ],
          ),
        ),
      ),
    ]);
  }

  Widget _levelCard() {
    final xp = _stats['total_xp'] ?? 0;
    final level = TitanLevel.forXp(xp);
    final next = TitanLevel.nextAfter(xp);
    final number = TitanLevel.ladder.indexOf(level) + 1;
    final streak = _stats['login_streak'] ?? 0;
    return Container(
      margin: const EdgeInsets.fromLTRB(AppSpacing.lg, 4, AppSpacing.lg, 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.pureWhite,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.titanGold),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('TITAN LEVEL', style: AppText.sectionLabel.copyWith(color: AppColors.titanGold)),
              Text.rich(TextSpan(children: [
                TextSpan(text: 'Level $number', style: AppFonts.sans(size: 26, weight: FontWeight.w700, color: AppColors.ink)),
                TextSpan(text: ' · ${level.name}', style: AppFonts.sans(size: 15, weight: FontWeight.w500, color: AppColors.ink3)),
              ])),
            ]),
          ),
          Column(children: [
            const TitanCrown(size: 40),
            if (streak > 0) Text('🔥 $streak day${streak == 1 ? '' : 's'}', style: AppFonts.mono(size: 11, color: AppColors.titanGold)),
          ]),
        ]),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: TitanLevel.progressToNext(xp),
            minHeight: 8,
            color: AppColors.titanGold,
            backgroundColor: AppColors.cream,
            semanticsLabel: 'Progress to next Titan level',
          ),
        ),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(child: Text(next == null ? '$xp XP' : '$xp / ${next.minXp} XP', style: AppFonts.mono(size: 12, color: AppColors.ink4))),
          Text(next == null ? 'Max level' : 'Next: ${next.name}', style: AppFonts.mono(size: 12, color: AppColors.ink4)),
        ]),
      ]),
    );
  }

  Widget _tabs(int open, int done) => Container(
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.birch))),
        child: Row(children: [
          for (final (i, label) in ['In progress · $open', 'Completed · $done'].indexed)
            Expanded(
              child: Semantics(
                button: true,
                selected: _completedTab == (i == 1),
                label: label,
                excludeSemantics: true,
                child: InkWell(
                  onTap: () => setState(() => _completedTab = i == 1),
                  child: Container(
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color: _completedTab == (i == 1) ? AppColors.goldMid : Colors.transparent, width: 2)),
                    ),
                    child: Text(label,
                        style: AppFonts.sans(size: 13, weight: FontWeight.w600, color: _completedTab == (i == 1) ? AppColors.ink : AppColors.ink3)),
                  ),
                ),
              ),
            ),
        ]),
      );

  Widget _tag(String text, Color fg, Color bg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: AppCard.badge(bg),
        child: Text(text, style: AppText.badge.copyWith(color: fg)),
      );

  /// The quiz is the one challenge started by hand; it stays as practice once won.
  Widget _quizCard(Challenge? c) {
    final won = c?.isComplete ?? false;
    return Material(
      color: AppColors.goldPale,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md), side: BorderSide(color: AppColors.goldMid)),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: _openQuiz,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Icon(Icons.menu_book_rounded, size: 28, color: AppColors.goldMid),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Glossary quiz', style: AppText.bodyBold),
                Text(
                  won || c == null
                      ? 'Practice round · sharpen your trading words'
                      : 'Pass it once · +${c.xp} XP · +${Money.wallet(c.rewardAmount, decimals: 0)}',
                  style: AppFonts.sans(size: 12, color: AppColors.ink3),
                ),
              ]),
            ),
            _tag('TAKE QUIZ', Colors.white, AppColors.imperialGold),
          ]),
        ),
      ),
    );
  }

  Widget _card(Challenge c) {
    final f = c.fraction;
    final reward = c.rewardAmount > 0 ? '+${Money.wallet(c.rewardAmount, decimals: 0)}' : '+${c.xp} XP';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.pureWhite,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.birch),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(c.title, style: AppText.bodyBold)),
          _tag(reward, AppColors.titanGold, AppColors.titanGoldSoft),
        ]),
        const SizedBox(height: 2),
        Text(c.description, style: AppFonts.sans(size: 12, color: AppColors.ink4)),
        if (f != null) ...[
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: f,
              minHeight: 6,
              color: c.isComplete ? AppColors.bull : AppColors.goldMid,
              backgroundColor: AppColors.cream,
            ),
          ),
        ],
        const SizedBox(height: 4),
        Row(children: [
          Expanded(child: Text(challengeProgressLabel(c), style: AppFonts.mono(size: 12, color: AppColors.ink3))),
          Text('${ChallengeCategory.labelFor(c.category)} · ${c.xp} XP', style: AppFonts.sans(size: 11, color: AppColors.ink4)),
        ]),
      ]),
    );
  }
}
