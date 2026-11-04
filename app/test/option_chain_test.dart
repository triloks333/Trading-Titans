// Option chain: delta maths, expiry chips, LTP·OI / Greeks, ITM layout and taps.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:mobile/core/theme.dart';
import 'package:mobile/screens/main/option_chain_screen.dart';
import 'package:mobile/screens/main/option_detail_screen.dart';

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

// A weekly and the monthly expiry of the same month, far enough out never to expire.
final _week = DateTime(2099, 11, 6), _month = DateTime(2099, 11, 27);
String _d(DateTime d) => d.toIso8601String().substring(0, 10);

Map<String, dynamic> _side(double strike, String type, double price) => {
      'symbol': 'NIFTY-$strike-$type',
      'strike_price': strike,
      'option_type': type,
      'expiry_date': _d(_week),
      'price': price,
      'change_pct': 1.0,
      'open_interest': 250000,
      'implied_volatility': 14.0,
    };

Map<String, dynamic> _chain() => {
      'spot_price': 24318.45,
      'change': 149.2,
      'change_pct': 0.62,
      'derivative_type': 'options',
      'expiries': [_d(_week), _d(_month)],
      'chains': [
        {
          'expiry_date': _d(_week),
          'strikes': [
            for (final k in [24200.0, 24250.0, 24300.0, 24350.0, 24400.0])
              {'strike_price': k, 'call': _side(k, 'CE', 120), 'put': _side(k, 'PE', 95)},
          ],
        },
        {'expiry_date': _d(_month), 'strikes': []},
      ],
      'futures': [],
    };

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.darkTheme,
    home: OptionChainScreen(underlyingSymbol: 'NIFTY', spotPrice: 24318.45, data: _chain()),
  ));
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await _loadFonts();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(url: 'http://127.0.0.1:9', anonKey: 'chain-test-key');
  });

  test('delta: ATM call just over 0.5, deep ITM near 1, put = call − 1', () {
    final atm = bsDelta(spot: 100, strike: 100, years: 30 / 365, ivPct: 20, isCall: true);
    expect(atm, inInclusiveRange(0.5, 0.6));
    expect(bsDelta(spot: 150, strike: 100, years: 30 / 365, ivPct: 20, isCall: true), greaterThan(0.99));
    expect(bsDelta(spot: 100, strike: 100, years: 30 / 365, ivPct: 20, isCall: false), closeTo(atm - 1, 1e-9));
  });

  testWidgets('header, expiry chips with W/M tags and the spot divider', (tester) async {
    await _pump(tester);
    expect(find.text('NIFTY option chain'), findsOneWidget);
    expect(find.textContaining('PCR 1.00'), findsOneWidget);
    expect(find.text('W'), findsOneWidget);
    expect(find.text('M'), findsOneWidget);
    expect(find.text('SPOT 24318.45'), findsOneWidget);
    for (final h in ['CALL', 'STRIKE', 'PUT']) {
      expect(find.text(h), findsOneWidget, reason: h);
    }
    expect(find.text('OI'), findsNWidgets(2));
    expect(find.text('2.5L'), findsWidgets, reason: 'OI in lakh');
  });

  testWidgets('Greeks swaps OI for delta', (tester) async {
    await _pump(tester);
    await tester.tap(find.bySemanticsLabel('Greeks'));
    await tester.pump();
    expect(find.text('DELTA'), findsNWidgets(2));
    expect(find.textContaining('Δ '), findsWidgets);
    expect(find.text('2.5L'), findsNothing);
  });

  testWidgets('tapping a call price opens that contract', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('120.00').first);
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    // Its chart is a WebView, which has no platform in tests; the route is what matters.
    while (tester.takeException() != null) {}
    expect(find.byType(OptionDetailScreen), findsOneWidget);
  });

  testWidgets('Futures segment switches the view', (tester) async {
    await _pump(tester);
    await tester.tap(find.bySemanticsLabel('Futures'));
    await tester.pump();
    expect(find.text('NIFTY futures'), findsOneWidget);
  });
}
