import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/glossary.dart';
import '../../core/theme.dart';
import '../../services/supabase_service.dart';
import '../../widgets/reward_celebration_dialog.dart';

/// A single multiple-choice question: match a term to its definition.
class QuizQuestion {
  final String term;

  /// Four candidate definitions; exactly one is correct.
  final List<String> options;
  final int correctIndex;

  const QuizQuestion({
    required this.term,
    required this.options,
    required this.correctIndex,
  });
}

/// Builds [count] questions from the shared [Glossary] so the quiz content
/// never diverges from the glossary screen and tooltips.
///
/// Pass a seeded [Random] to make the output deterministic in tests.
List<QuizQuestion> buildGlossaryQuiz({
  int count = 5,
  int optionCount = 4,
  Random? random,
}) {
  final rng = random ?? Random();
  final terms = List.of(Glossary.terms);
  if (terms.length < optionCount) return const [];

  terms.shuffle(rng);
  final chosen = terms.take(count).toList();

  return chosen.map((term) {
    // Distractors are other terms' definitions, so every option is plausible.
    final distractors = Glossary.terms.where((t) => t.term != term.term).toList()
      ..shuffle(rng);
    final options = <String>[
      term.definition,
      ...distractors.take(optionCount - 1).map((t) => t.definition),
    ]..shuffle(rng);
    return QuizQuestion(
      term: term.term,
      options: options,
      correctIndex: options.indexOf(term.definition),
    );
  }).toList();
}

/// Minimum correct answers needed to pass.
const int kGlossaryQuizPassMark = 4;

class GlossaryQuizScreen extends StatefulWidget {
  const GlossaryQuizScreen({super.key});

  @override
  State<GlossaryQuizScreen> createState() => _GlossaryQuizScreenState();
}

class _GlossaryQuizScreenState extends State<GlossaryQuizScreen> {
  late List<QuizQuestion> _questions;
  int _index = 0;
  int _correct = 0;
  int? _selected;
  bool _submitting = false;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _questions = buildGlossaryQuiz();
  }

  void _answer(int option) {
    if (_selected != null) return;
    setState(() {
      _selected = option;
      if (option == _questions[_index].correctIndex) _correct++;
    });
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
    var awarded = false;
    if (passed) {
      awarded = await SupabaseService().awardGlossaryQuiz();
    }
    if (!mounted) return;
    setState(() => _submitting = false);

    if (awarded) {
      // Reuses the existing reward popup so a challenge win looks like every
      // other reward in the app.
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Glossary quiz',
            style: GoogleFonts.ibmPlexSans(fontWeight: FontWeight.w900, color: AppColors.ink)),
        backgroundColor: AppColors.pureWhite,
        foregroundColor: AppColors.ink,
        elevation: 0,
      ),
      body: SafeArea(
        child: _questions.isEmpty
            ? Center(
                child: Text('Quiz unavailable right now.',
                    style: GoogleFonts.ibmPlexSans(color: AppColors.ink4)))
            : _finished
                ? _buildResult()
                : _buildQuestion(),
      ),
    );
  }

  Widget _buildQuestion() {
    final q = _questions[_index];
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: LinearProgressIndicator(
            value: (_index + 1) / _questions.length,
            minHeight: 6,
            backgroundColor: AppColors.cream,
            valueColor: AlwaysStoppedAnimation(AppColors.imperialGold),
            semanticsLabel: 'Question ${_index + 1} of ${_questions.length}',
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text('QUESTION ${_index + 1} OF ${_questions.length}',
            style: GoogleFonts.ibmPlexSans(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.ink4,
                letterSpacing: 0.5)),
        const SizedBox(height: AppSpacing.xs),
        Text('What does "${q.term}" mean?',
            style: GoogleFonts.ibmPlexSans(
                fontSize: 20, fontWeight: FontWeight.w900, color: AppColors.ink)),
        const SizedBox(height: AppSpacing.lg),
        for (var i = 0; i < q.options.length; i++) _buildOption(q, i),
        const SizedBox(height: AppSpacing.md),
        if (_selected != null)
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _next,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.ink,
                foregroundColor: AppColors.pureWhite,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md)),
              ),
              child: Text(
                  _index + 1 < _questions.length ? 'Next question' : 'See result',
                  style: GoogleFonts.ibmPlexSans(fontWeight: FontWeight.bold)),
            ),
          ),
      ],
    );
  }

  Widget _buildOption(QuizQuestion q, int i) {
    final isCorrect = i == q.correctIndex;
    final isPicked = _selected == i;
    final revealed = _selected != null;

    Color border = AppColors.birch;
    Color background = AppColors.pureWhite;
    if (revealed && isCorrect) {
      border = AppColors.bull;
      background = AppColors.bullLight;
    } else if (revealed && isPicked) {
      border = AppColors.bear;
      background = AppColors.bearLight;
    }

    return Semantics(
      button: true,
      selected: isPicked,
      child: GestureDetector(
        onTap: () => _answer(i),
        child: Container(
          margin: const EdgeInsets.only(bottom: AppSpacing.sm),
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: border, width: revealed && (isCorrect || isPicked) ? 2 : 1),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(q.options[i],
                    style: GoogleFonts.ibmPlexSans(
                        fontSize: 13, color: AppColors.ink2, height: 1.4)),
              ),
              if (revealed && isCorrect)
                Icon(Icons.check_circle, size: 18, color: AppColors.bull)
              else if (revealed && isPicked)
                Icon(Icons.cancel, size: 18, color: AppColors.bear),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResult() {
    final passed = _correct >= kGlossaryQuizPassMark;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: passed ? AppColors.bullLight : AppColors.cream,
                shape: BoxShape.circle,
              ),
              child: Icon(passed ? Icons.school_rounded : Icons.replay_rounded,
                  size: 40, color: passed ? AppColors.bull : AppColors.ink4),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('$_correct / ${_questions.length} correct',
                style: GoogleFonts.ibmPlexSans(
                    fontSize: 24, fontWeight: FontWeight.w900, color: AppColors.ink)),
            const SizedBox(height: AppSpacing.xs),
            Text(
              passed
                  ? 'Passed. Your reward is waiting in the wallet.'
                  : 'You need $kGlossaryQuizPassMark correct to pass. Read the glossary and try again.',
              textAlign: TextAlign.center,
              style: GoogleFonts.ibmPlexSans(fontSize: 14, color: AppColors.ink4, height: 1.4),
            ),
            const SizedBox(height: AppSpacing.xl),
            if (_submitting)
              const CircularProgressIndicator()
            else
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: passed
                      ? () => Navigator.of(context).pop()
                      : () => setState(() {
                            _questions = buildGlossaryQuiz();
                            _index = 0;
                            _correct = 0;
                            _selected = null;
                            _finished = false;
                          }),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.imperialGold,
                    foregroundColor: AppColors.pureWhite,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.md)),
                  ),
                  child: Text(passed ? 'Done' : 'Try again',
                      style: GoogleFonts.ibmPlexSans(fontWeight: FontWeight.bold)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
