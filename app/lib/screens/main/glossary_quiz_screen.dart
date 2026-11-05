import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/glossary.dart';
import '../../core/theme.dart';
import '../../services/supabase_service.dart';
import '../../services/theme_service.dart';
import '../../widgets/auth_kit.dart';
import '../../widgets/reward_celebration_dialog.dart';
import 'glossary_screen.dart';

/// A single multiple-choice question: match a term to its definition.
class QuizQuestion {
  final String term;

  /// Four candidate definitions; exactly one is correct.
  final List<String> options;
  final int correctIndex;

  /// Glossary category, the term's definition and its worked example, shown in
  /// the header and the answer explanation.
  final String category;
  final String explanation;
  final String example;

  const QuizQuestion({
    required this.term,
    required this.options,
    required this.correctIndex,
    this.category = 'Basics',
    this.explanation = '',
    this.example = '',
  });
}

/// Builds [count] questions from the shared [Glossary] so the quiz never
/// diverges from the glossary screen and tooltips. Pass a seeded [Random] for
/// deterministic output in tests.
List<QuizQuestion> buildGlossaryQuiz({int count = 5, int optionCount = 4, Random? random}) {
  final rng = random ?? Random();
  final terms = List.of(Glossary.terms);
  if (terms.length < optionCount) return const [];
  terms.shuffle(rng);
  return terms.take(count).map((term) {
    // Distractors are other terms' definitions, so every option is plausible.
    final distractors = Glossary.terms.where((t) => t.term != term.term).toList()..shuffle(rng);
    final options = <String>[term.definition, ...distractors.take(optionCount - 1).map((t) => t.definition)]..shuffle(rng);
    return QuizQuestion(
      term: term.term,
      options: options,
      correctIndex: options.indexOf(term.definition),
      category: term.category,
      explanation: term.definition,
      example: term.example,
    );
  }).toList();
}

/// Minimum correct answers needed to pass.
const int kGlossaryQuizPassMark = 4;

class GlossaryQuizScreen extends StatefulWidget {
  const GlossaryQuizScreen({super.key, this.questions, this.award});

  /// Fixed questions and award call (tests).
  final List<QuizQuestion>? questions;
  final Future<bool> Function()? award;

  @override
  State<GlossaryQuizScreen> createState() => _GlossaryQuizScreenState();
}

class _GlossaryQuizScreenState extends State<GlossaryQuizScreen> {
  late List<QuizQuestion> _questions = widget.questions ?? buildGlossaryQuiz();
  int _index = 0;
  int _correct = 0;
  int? _selected;
  final List<bool?> _results = [];
  bool _submitting = false;
  bool _finished = false;

  void _answer(int option) {
    if (_selected != null) return;
    final right = option == _questions[_index].correctIndex;
    setState(() {
      _selected = option;
      _results.add(right);
      if (right) _correct++;
    });
  }

  /// Skipping counts as a wrong answer and moves on.
  void _skip() {
    if (_selected == null) _results.add(false);
    _next();
  }

  Future<void> _next() async {
    if (_index + 1 < _questions.length) {
      setState(() {
        _index++;
        _selected = null;
      });
      return;
    }
    setState(() {
      _finished = true;
      _submitting = true;
    });
    final passed = _correct >= kGlossaryQuizPassMark;
    final awarded = passed && await (widget.award ?? SupabaseService().awardGlossaryQuiz)();
    if (!mounted) return;
    setState(() => _submitting = false);
    if (awarded) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => RewardCelebrationDialog(
          subtitle: 'Challenge Complete',
          amount: 750,
          message: 'Glossary Graduate unlocked. Claim it from your wallet.',
          onClose: () => Navigator.of(dialogContext).pop(),
        ),
      );
    }
  }

  void _restart() => setState(() {
        _questions = widget.questions ?? buildGlossaryQuiz();
        _index = 0;
        _correct = 0;
        _selected = null;
        _results.clear();
        _finished = false;
      });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 10, AppSpacing.lg, 10),
            child: Row(children: [
              AuthIconButton(icon: Icons.close_rounded, label: 'Close quiz', onTap: () => Navigator.of(context).maybePop()),
              const SizedBox(width: 12),
              Expanded(child: _segments()),
              const SizedBox(width: 12),
              Text('$_correct/${_questions.length}', style: AppFonts.mono(size: 14, weight: FontWeight.w600, color: AppColors.titanGold)),
              const SizedBox(width: 8),
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
          Expanded(
            child: _questions.isEmpty
                ? Center(child: Text('Quiz unavailable right now.', style: AppText.body))
                : _finished
                    ? _result()
                    : _question(),
          ),
        ]),
      ),
    );
  }

  /// One segment per question: green right, red wrong, accent current.
  Widget _segments() => Semantics(
        label: 'Question ${_index + 1} of ${_questions.length}',
        child: Row(children: [
          for (var i = 0; i < _questions.length; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            Expanded(
              child: Container(
                height: 6,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(3),
                  color: i < _results.length
                      ? (_results[i]! ? AppColors.bull : AppColors.bear)
                      : i == _index && !_finished
                          ? AppColors.goldMid
                          : AppColors.cream,
                ),
              ),
            ),
          ],
        ]),
      );

  Widget _question() {
    final q = _questions[_index];
    final answered = _selected != null;
    final right = answered && _selected == q.correctIndex;
    return Column(children: [
      Expanded(
        child: ListView(padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 20, AppSpacing.lg, 0), children: [
          Text('QUESTION ${_index + 1} OF ${_questions.length} · ${q.category.toUpperCase()}', style: AppText.sectionLabel),
          const SizedBox(height: 10),
          Text.rich(
            TextSpan(style: AppFonts.sans(size: 24, weight: FontWeight.w700, color: AppColors.ink, height: 1.25), children: [
              const TextSpan(text: 'What does '),
              TextSpan(text: q.term, style: TextStyle(color: AppColors.goldMid)),
              const TextSpan(text: ' mean?'),
            ]),
          ),
          const SizedBox(height: 14),
          for (var i = 0; i < q.options.length; i++) _option(q, i),
          if (answered)
            Container(
              margin: const EdgeInsets.only(top: 6),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: right ? AppColors.bullLight : AppColors.titanGoldSoft,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(right ? 'Correct!' : 'Not quite',
                    style: AppFonts.sans(size: 14, weight: FontWeight.w700, color: right ? AppColors.bull : AppColors.titanGold)),
                const SizedBox(height: 4),
                Text('${q.term}: ${q.explanation}', style: AppFonts.sans(size: 13, color: AppColors.ink, height: 1.4)),
                if (q.example.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(q.example, style: AppFonts.sans(size: 12, color: AppColors.ink3, height: 1.4)),
                ],
              ]),
            ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 12, AppSpacing.lg, 8),
        child: Column(children: [
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: answered ? _next : _skip,
              child: Text(!answered ? 'Skip' : _index + 1 < _questions.length ? 'Next question' : 'See result'),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const GlossaryScreen())),
            child: Text('Open full glossary', style: AppFonts.sans(size: 13, color: AppColors.ink4)),
          ),
        ]),
      ),
    ]);
  }

  Widget _option(QuizQuestion q, int i) {
    final revealed = _selected != null;
    final isCorrect = i == q.correctIndex, isPicked = _selected == i;
    final good = revealed && isCorrect, bad = revealed && isPicked && !isCorrect;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Semantics(
        button: true,
        selected: isPicked,
        child: Material(
          color: good ? AppColors.bullLight : bad ? AppColors.bearLight : AppColors.pureWhite,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
            side: BorderSide(color: good ? AppColors.bull : bad ? AppColors.bear : AppColors.birch),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.md),
            onTap: () => _answer(i),
            child: Container(
              constraints: const BoxConstraints(minHeight: 56),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(children: [
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: AppColors.cream, borderRadius: BorderRadius.circular(6)),
                  child: Text('ABCD'[i], style: AppFonts.mono(size: 12, weight: FontWeight.w600, color: AppColors.ink3)),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(q.options[i], style: AppFonts.sans(size: 14, weight: FontWeight.w500, color: AppColors.ink, height: 1.35))),
                if (good) Text('✓', style: AppFonts.mono(size: 15, weight: FontWeight.w700, color: AppColors.bull)),
                if (bad) Text('✕', style: AppFonts.mono(size: 15, weight: FontWeight.w700, color: AppColors.bear)),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _result() {
    final passed = _correct >= kGlossaryQuizPassMark;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(color: passed ? AppColors.bullLight : AppColors.cream, shape: BoxShape.circle),
            child: Icon(passed ? Icons.school_rounded : Icons.replay_rounded, size: 40, color: passed ? AppColors.bull : AppColors.ink4),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('$_correct / ${_questions.length} correct', style: AppFonts.sans(size: 24, weight: FontWeight.w700, color: AppColors.ink)),
          const SizedBox(height: AppSpacing.xs),
          Text(
            passed ? 'Passed. Any reward you earned is waiting in your wallet.' : 'You need $kGlossaryQuizPassMark correct to pass. Read the glossary and try again.',
            textAlign: TextAlign.center,
            style: AppText.body,
          ),
          const SizedBox(height: AppSpacing.xl),
          if (_submitting)
            const CircularProgressIndicator()
          else
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: passed ? () => Navigator.of(context).pop() : _restart,
                child: Text(passed ? 'Done' : 'Try again'),
              ),
            ),
        ]),
      ),
    );
  }
}
