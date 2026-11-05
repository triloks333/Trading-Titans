// Weekly League: countdown, gap-to-next-tier, scopes, podium and the pinned bar.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:mobile/core/theme.dart';
import 'package:mobile/screens/main/challenges_screen.dart';
import 'package:mobile/screens/main/compete_screen.dart';

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

Map<String, dynamic> _r(int? rank, String name, double pct, {int trades = 4, bool me = false}) =>
    {'rank': rank, 'user_id': name, 'name': name, 'pnl_pct': pct, 'pnl': pct * 10, 'trades': trades, 'qualified': rank != null, 'is_me': me};

List<Map<String, dynamic>> _board() => [
      for (var i = 1; i <= 30; i++) _r(i, 'player$i', 20 - i * 0.5),
      _r(null, 'me', 0.4, trades: 1, me: true),
    ];

void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await _loadFonts();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(url: 'http://127.0.0.1:9', anonKey: 'league-test-key');
  });

  test('countdown runs to Monday 00:00 IST', () {
    // Thursday 5 Nov 2026, 12:00 IST = 06:30 UTC → Monday 9 Nov 00:00 IST is 3d 12h away.
    final d = leagueTimeLeft(DateTime.utc(2026, 11, 5, 6, 30));
    expect(d, const Duration(days: 3, hours: 12));
    expect(leagueCountdown(d), '3d 12h 00m');
    // Sunday 23:30 IST is 30 minutes from the reset.
    expect(leagueTimeLeft(DateTime.utc(2026, 11, 8, 18, 0)), const Duration(minutes: 30));
  });

  test('gap label names the next tier and the % needed', () {
    final rows = _board();
    expect(leagueGapLabel(rows, rows.last), 'Close 1 more trade to get ranked');
    expect(leagueGapLabel(rows, null), 'Close 2 trades this week to get ranked');
    expect(leagueGapLabel(rows, rows[0]), 'Top of the board');
    // Rank 30 at 5.0% aims for top 25 (rank 25 at 7.5%): +2.50%.
    expect(leagueGapLabel(rows, rows[29]), '+2.50% more to reach top 25');
    // Rank 2 aims for #1.
    expect(leagueGapLabel(rows, rows[1]), '+0.50% more to reach #1');
  });

  testWidgets('podium, prize card, rows, scopes and pinned bar', (tester) async {
    final scopes = <String>[];
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.darkTheme,
      home: CompeteScreen(loader: (s) async {
        scopes.add(s);
        return _board();
      }),
    ));
    await tester.pumpAndSettle();

    expect(scopes, ['week']);
    expect(find.textContaining('Ends in'), findsOneWidget);
    expect(find.text('player1'), findsOneWidget);
    expect(find.textContaining('Top 10 win demo cash'), findsOneWidget);
    expect(find.text('Your position'), findsOneWidget);
    expect(find.text('Close 1 more trade to get ranked'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('All-time'));
    await tester.pumpAndSettle();
    expect(scopes.last, 'all');
    expect(find.textContaining('Top 10 win demo cash'), findsNothing, reason: 'prizes are weekly only');

    await tester.tap(find.bySemanticsLabel('Friends'));
    await tester.pumpAndSettle();
    expect(scopes.last, 'friends');

    await tester.tap(find.bySemanticsLabel('Challenges'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.byType(ChallengesScreen), findsOneWidget);
  });

  testWidgets('friends with nobody ranked explains who counts', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.darkTheme,
      home: CompeteScreen(loader: (s) async => s == 'friends' ? [_r(null, 'me', 0, trades: 0, me: true)] : _board()),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Friends'));
    await tester.pumpAndSettle();
    expect(find.text('No friends ranked yet'), findsOneWidget);
  });
}
