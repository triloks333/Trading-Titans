// Watchlists: header, list chips and the add-instrument path.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:mobile/core/theme.dart';
import 'package:mobile/screens/main/watchlist_screen.dart';
import 'package:mobile/services/nav_tab_service.dart';

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

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  // Pushed over a root page, as Home and Profile open it.
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.darkTheme,
    home: Builder(
      builder: (c) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => Navigator.of(c).push(MaterialPageRoute(builder: (_) => const WatchlistScreen())),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await _loadFonts();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(url: 'http://127.0.0.1:9', anonKey: 'watchlist-test-key');
  });

  testWidgets('header, column heads, New list and Add instrument', (tester) async {
    await _pump(tester);
    expect(find.text('Watchlists'), findsOneWidget);
    for (final h in ['INSTRUMENT', '5D', 'LTP · CHG']) {
      expect(find.text(h), findsOneWidget, reason: h);
    }

    await tester.tap(find.text('New list'));
    await tester.pumpAndSettle();
    expect(find.text('New watchlist'), findsOneWidget, reason: 'New list opens the create sheet');
    await tester.tapAt(const Offset(195, 40)); // dismiss the sheet
    await tester.pumpAndSettle();

    final requests = <int>[];
    void listen() => requests.add(NavTabService.tabRequest.value);
    NavTabService.tabRequest.addListener(listen);
    addTearDown(() => NavTabService.tabRequest.removeListener(listen));
    await tester.tap(find.text('Add instrument'));
    await tester.pumpAndSettle();
    expect(requests.where((r) => r >= 0), [NavTabService.trade]);
    expect(find.byType(WatchlistScreen), findsNothing, reason: 'returns to the tabs');
  });

  testWidgets('back closes the screen', (tester) async {
    await _pump(tester);
    await tester.tap(find.bySemanticsLabel('Back'));
    await tester.pumpAndSettle();
    expect(find.byType(WatchlistScreen), findsNothing);
  });
}
