// What-If: CAGR and FD maths, live re-runs on every choice, and practise trading.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:mobile/core/theme.dart';
import 'package:mobile/screens/main/stock_detail_screen.dart';
import 'package:mobile/screens/main/whatif_screen.dart';

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

void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await _loadFonts();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(url: 'http://127.0.0.1:9', anonKey: 'whatif-test-key');
  });

  test('CAGR and fixed deposit', () {
    expect(whatIfCagr(10000, 20000, 5), closeTo(14.87, 0.01));
    expect(whatIfCagr(10000, 10000, 3), 0);
    expect(whatIfCagr(0, 100, 3), 0);
    expect(fixedDepositValue(10000, 5), closeTo(14025.52, 0.01));
  });

  testWidgets('every choice re-runs the simulation; result and FD shown', (tester) async {
    final calls = <String>[];
    Future<Map<String, dynamic>?> fake(String s, String m, double a, int y) async {
      calls.add('$s/$m/${a.round()}/$y');
      return {'symbol': s, 'amount_invested': a, 'current_value': a * 2, 'pnl': a, 'units': 1.0, 'purchase_price': 1.0};
    }

    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(theme: AppTheme.darkTheme, home: WhatIfScreen(simulate: fake)));
    await tester.pumpAndSettle();

    expect(calls.last, 'RELIANCE/stock/10000/5');
    expect(find.textContaining('CAGR 14.9%'), findsOneWidget);
    expect(find.textContaining('vs. fixed deposit at 7%'), findsOneWidget);

    await tester.tap(find.text('TCS'));
    await tester.pumpAndSettle();
    expect(calls.last, 'TCS/stock/10000/5');

    await tester.tap(find.text('10Y'));
    await tester.pumpAndSettle();
    expect(calls.last, 'TCS/stock/10000/10');

    await tester.tap(find.text('Crypto'));
    await tester.pumpAndSettle();
    expect(calls.last, 'BTC/crypto/10000/10');

    await tester.enterText(find.byType(TextField), '5000');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(calls.last, 'BTC/crypto/5000/10');

    final practise = find.text('Practise trading BTC');
    await tester.scrollUntilVisible(practise, 120, scrollable: find.byType(Scrollable).first);
    await tester.tap(practise);
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.byType(StockDetailScreen), findsOneWidget);
  });
}
