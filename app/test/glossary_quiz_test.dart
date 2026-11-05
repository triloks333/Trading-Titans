// Glossary quiz: answer feedback, segments, skip, pass and award, retry.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:mobile/core/theme.dart';
import 'package:mobile/screens/main/glossary_quiz_screen.dart';
import 'package:mobile/screens/main/glossary_screen.dart';

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

/// Five questions whose right answer is always option A.
final _qs = [
  for (var i = 1; i <= 5; i++)
    QuizQuestion(term: 'Term$i', options: ['right$i', 'wrong$i b', 'wrong$i c', 'wrong$i d'], correctIndex: 0, category: 'Options', explanation: 'means right$i'),
];

Future<void> _pump(WidgetTester tester, {Future<bool> Function()? award}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: AppTheme.darkTheme, home: GlossaryQuizScreen(questions: _qs, award: award)));
  await tester.pump();
}

void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await _loadFonts();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(url: 'http://127.0.0.1:9', anonKey: 'quiz-test-key');
  });

  testWidgets('right and wrong answers explain the term; skip counts as wrong', (tester) async {
    await _pump(tester, award: () async => false);
    expect(find.text('QUESTION 1 OF 5 · OPTIONS'), findsOneWidget);
    expect(find.text('Skip'), findsOneWidget);

    await tester.tap(find.text('right1'));
    await tester.pump();
    expect(find.text('Correct!'), findsOneWidget);
    expect(find.text('Term1: means right1'), findsOneWidget);
    expect(find.text('1/5'), findsOneWidget);

    await tester.tap(find.text('Next question'));
    await tester.pump();
    await tester.tap(find.text('wrong2 b'));
    await tester.pump();
    expect(find.text('Not quite'), findsOneWidget);
    expect(find.text('1/5'), findsOneWidget);

    await tester.tap(find.text('Next question'));
    await tester.pump();
    await tester.tap(find.text('Skip'));
    await tester.pump();
    expect(find.text('QUESTION 4 OF 5 · OPTIONS'), findsOneWidget);
  });

  testWidgets('passing calls the award and shows the reward', (tester) async {
    var awarded = 0;
    await _pump(tester, award: () async {
      awarded++;
      return true;
    });
    for (var i = 1; i <= 5; i++) {
      await tester.tap(find.text('right$i'));
      await tester.pump();
      await tester.tap(find.text(i < 5 ? 'Next question' : 'See result'));
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 500));
    expect(awarded, 1);
    expect(find.text('5 / 5 correct'), findsOneWidget);
    expect(find.textContaining('Glossary Graduate'), findsOneWidget);
  });

  testWidgets('failing offers a retry, no award', (tester) async {
    var awarded = 0;
    await _pump(tester, award: () async {
      awarded++;
      return true;
    });
    for (var i = 1; i <= 5; i++) {
      await tester.tap(find.text('Skip'));
      await tester.pump();
    }
    expect(find.text('0 / 5 correct'), findsOneWidget);
    expect(awarded, 0);
    await tester.tap(find.text('Try again'));
    await tester.pump();
    expect(find.text('QUESTION 1 OF 5 · OPTIONS'), findsOneWidget);
  });

  testWidgets('Open full glossary', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Open full glossary'));
    await tester.pumpAndSettle();
    expect(find.byType(GlossaryScreen), findsOneWidget);
  });
}
