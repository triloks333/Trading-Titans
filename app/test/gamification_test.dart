// Checks for the gamification layer and the three-market nav bar.
//
// Everything here is pure or widget-level: the challenge conditions themselves
// live in SQL (evaluate_challenges) and are covered by the unique-index
// idempotency guarantee rather than by client tests. What can break silently on
// the client is the level ladder maths, the quiz generator's answer key, and the
// nav bar's collapse/expand rule — so those are what get locked down.

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/glossary.dart';
import 'package:mobile/models/challenge.dart';
import 'package:mobile/screens/main/glossary_quiz_screen.dart';
import 'package:mobile/widgets/market_nav_bar.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

Challenge _challenge({
  String key = 'demo',
  int? repeatLimit = 1,
  int timesEarned = 0,
}) =>
    Challenge(
      key: key,
      title: 'Demo',
      description: 'Demo challenge',
      category: 'performance',
      rewardAmount: 1000,
      xp: 100,
      repeatLimit: repeatLimit,
      sortOrder: 0,
      timesEarned: timesEarned,
      totalEarned: 0,
    );

void main() {
  group('TitanLevel ladder', () {
    test('maps XP onto the highest level reached', () {
      expect(TitanLevel.forXp(0).name, 'Novice');
      expect(TitanLevel.forXp(249).name, 'Novice');
      expect(TitanLevel.forXp(250).name, 'Apprentice');
      expect(TitanLevel.forXp(6000).name, 'Titan');
      expect(TitanLevel.forXp(999999).name, 'Titan');
    });

    test('next level is null only at the top', () {
      expect(TitanLevel.nextAfter(0)?.name, 'Apprentice');
      expect(TitanLevel.nextAfter(5999)?.name, 'Titan');
      expect(TitanLevel.nextAfter(6000), isNull);
    });

    test('progress stays within 0..1 and hits the boundaries exactly', () {
      expect(TitanLevel.progressToNext(0), 0.0);
      expect(TitanLevel.progressToNext(125), closeTo(0.5, 0.001));
      expect(TitanLevel.progressToNext(250), 0.0); // start of the next band
      expect(TitanLevel.progressToNext(6000), 1.0); // max level
      for (final xp in [0, 1, 249, 250, 749, 3499, 5999, 6000, 20000]) {
        final p = TitanLevel.progressToNext(xp);
        expect(p, inInclusiveRange(0.0, 1.0), reason: 'xp=$xp produced $p');
      }
    });
  });

  group('Challenge progress', () {
    test('one-shot is complete after a single grant', () {
      expect(_challenge(timesEarned: 0).isComplete, isFalse);
      expect(_challenge(timesEarned: 1).isComplete, isTrue);
    });

    test('repeatable reports remaining payouts', () {
      final c = _challenge(repeatLimit: 3, timesEarned: 1);
      expect(c.isEarned, isTrue);
      expect(c.isComplete, isFalse);
      expect(c.remaining, 2);
    });

    test('unlimited challenges never complete and have no remaining count', () {
      final c = _challenge(repeatLimit: null, timesEarned: 12);
      expect(c.isComplete, isFalse);
      expect(c.remaining, isNull);
    });

    test('parses the RPC row shape, including numeric strings', () {
      final c = Challenge.fromJson({
        'key': 'titan_20',
        'title': '20% Titan',
        'description': 'Grow your realized profit.',
        'category': 'performance',
        'reward_amount': '5000',
        'xp': 500,
        'repeat_limit': 1,
        'sort_order': 20,
        'times_earned': 1,
        'total_earned': '5000',
        'last_earned_at': '2026-08-05T10:00:00Z',
      });
      expect(c.rewardAmount, 5000);
      expect(c.totalEarned, 5000);
      expect(c.isComplete, isTrue);
      expect(c.lastEarnedAt, isNotNull);
    });
  });

  group('Glossary quiz generator', () {
    test('correctIndex always points at the chosen term definition', () {
      // Seeded so a failure is reproducible rather than flaky.
      for (var seed = 0; seed < 25; seed++) {
        final quiz = buildGlossaryQuiz(random: Random(seed));
        expect(quiz, hasLength(5));
        for (final q in quiz) {
          final term = Glossary.terms.firstWhere((t) => t.term == q.term);
          expect(q.options.length, 4);
          expect(q.options[q.correctIndex], term.definition,
              reason: 'seed=$seed term=${q.term}');
        }
      }
    });

    test('options within a question are distinct, so there is one right answer', () {
      for (var seed = 0; seed < 25; seed++) {
        for (final q in buildGlossaryQuiz(random: Random(seed))) {
          expect(q.options.toSet().length, q.options.length,
              reason: 'duplicate option for ${q.term} at seed=$seed');
        }
      }
    });

    test('asks about distinct terms', () {
      final quiz = buildGlossaryQuiz(random: Random(7));
      expect(quiz.map((q) => q.term).toSet().length, quiz.length);
    });

    test('pass mark cannot exceed the number of questions asked', () {
      expect(kGlossaryQuizPassMark,
          lessThanOrEqualTo(buildGlossaryQuiz(random: Random(1)).length));
    });
  });

  group('MarketNavBar', () {
    testWidgets('shows every market label as an equal segment', (tester) async {
      await tester.pumpWidget(_wrap(MarketNavBar(
        selectedKey: 'stock',
        onSelected: (_) {},
      )));

      for (final label in ['India', 'US Stocks', 'Crypto']) {
        expect(find.text(label), findsOneWidget);
      }
    });

    testWidgets('selection is announced on the chosen segment only', (tester) async {
      await tester.pumpWidget(_wrap(MarketNavBar(
        selectedKey: 'us_stock',
        onSelected: (_) {},
      )));
      await tester.pumpAndSettle();

      expect(tester.getSemantics(find.bySemanticsLabel('US Stocks')), containsSemantics(isSelected: true));
      expect(tester.getSemantics(find.bySemanticsLabel('India')), containsSemantics(isSelected: false));
    });

    testWidgets('reports the tapped market key', (tester) async {
      final tapped = <String>[];
      await tester.pumpWidget(_wrap(MarketNavBar(
        selectedKey: 'stock',
        onSelected: tapped.add,
      )));

      await tester.tap(find.text('Crypto'));
      await tester.tap(find.text('US Stocks'));

      expect(tapped, ['crypto', 'us_stock']);
    });

    testWidgets('coming-soon tabs announce themselves to screen readers',
        (tester) async {
      await tester.pumpWidget(_wrap(MarketNavBar(
        selectedKey: 'stock',
        comingSoonKeys: const {'us_stock'},
        onSelected: (_) {},
      )));

      // The dot is visual only, so the semantic label carries "coming soon".
      expect(
        find.bySemanticsLabel('US Stocks, coming soon'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Crypto'), findsOneWidget);
    });

    testWidgets('fits a 320dp-wide screen with the longest label active',
        (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_wrap(MarketNavBar(
        selectedKey: 'us_stock',
        comingSoonKeys: const {'us_stock'},
        onSelected: (_) {},
      )));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('US Stocks'), findsOneWidget);
    });
  });

  group('MarketTab catalogue', () {
    test('covers all markets with distinct keys', () {
      expect(MarketTab.all.map((t) => t.key).toList(),
          ['stock', 'us_stock', 'crypto', 'commodity', 'pakistan_stock', 'italy_stock']);
      expect(MarketTab.all.map((t) => t.key).toSet().length, 6);
    });

    test('byKey falls back to Indian stocks for an unknown market', () {
      expect(MarketTab.byKey('crypto').key, 'crypto');
      expect(MarketTab.byKey('nonsense').key, 'stock');
    });
  });
}
