// Challenges: progress labels and bars, level card, tabs and the quiz entry.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:mobile/core/money.dart';
import 'package:mobile/core/theme.dart';
import 'package:mobile/models/challenge.dart';
import 'package:mobile/screens/main/challenges_screen.dart';
import 'package:mobile/screens/main/glossary_quiz_screen.dart';

Future<void> _loadFonts() async {
  final sans = File('C:/Windows/Fonts/arial.ttf'), mono = File('C:/Windows/Fonts/consola.ttf');
  if (!sans.existsSync() || !mono.existsSync()) return;
  final variants = ['regular', 'italic', for (final w in [100, 200, 300, 500, 600, 700, 800, 900]) ...['$w', '${w}italic']];
  for (final (family, file) in [('IBMPlexSans', sans), ('IBMPlexMono', mono)]) {
    for (final v in variants) {
      await (FontLoader('${family}_$v')..addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())))).load();
    }
  }
}

Challenge _c(String key, {int earned = 0, int? limit = 1, double? p, double? t, double reward = 500}) => Challenge(
      key: key, title: key, description: 'about $key', category: 'habit', rewardAmount: reward, xp: 50,
      repeatLimit: limit, sortOrder: 0, timesEarned: earned, totalEarned: earned * reward, progress: p, target: t,
    );

final _list = [
  _c('globetrotter', p: 2, t: 3),
  _c('titan_20', p: 1240, t: 2200),
  _c('sniper', limit: 3, earned: 1),
  _c('podium_1', limit: null),
  _c('first_blood', earned: 1, p: 1, t: 1),
  _c('glossary_graduate'),
];

void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await _loadFonts();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(url: 'http://127.0.0.1:9', anonKey: 'challenges-test-key');
  });

  test('progress labels and fractions', () {
    expect(challengeProgressLabel(_list[0]), '2 of 3');
    expect(_list[0].fraction, closeTo(0.667, 0.001));
    expect(challengeProgressLabel(_list[1]), '${Money.wallet(1240, decimals: 0)} of ${Money.wallet(2200, decimals: 0)}');
    expect(challengeProgressLabel(_list[2]), '1 of 3 claimed');
    expect(_list[2].fraction, isNull);
    expect(challengeProgressLabel(_list[3]), 'Repeatable');
    expect(challengeProgressLabel(_list[4]), 'Earned ₹500');
    expect(_list[4].fraction, 1);
    expect(Challenge.fromJson({'key': 'x', 'progress': '2', 'target': 5}).fraction, 0.4);
  });

  testWidgets('level card, tabs, closest-first and the quiz', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.darkTheme,
      home: ChallengesScreen(loader: () async => (_list, {'total_xp': 1920, 'login_streak': 4})),
    ));
    await tester.pumpAndSettle();

    expect(find.text('TITAN LEVEL'), findsOneWidget);
    expect(find.text('1920 / 3500 XP'), findsOneWidget);
    expect(find.text('Next: Veteran'), findsOneWidget);
    expect(find.text('In progress · 5'), findsOneWidget);
    expect(find.text('Completed · 1'), findsOneWidget);
    // Globetrotter (67%) sorts above Titan 20 (56%).
    expect(tester.getTopLeft(find.text('globetrotter')).dy, lessThan(tester.getTopLeft(find.text('titan_20')).dy));

    await tester.tap(find.bySemanticsLabel('Completed · 1'));
    await tester.pump();
    expect(find.text('first_blood'), findsOneWidget);
    expect(find.text('globetrotter'), findsNothing);

    await tester.tap(find.bySemanticsLabel('In progress · 5'));
    await tester.pump();
    await tester.tap(find.text('TAKE QUIZ'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.byType(GlossaryQuizScreen), findsOneWidget);
  });
}
