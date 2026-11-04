// Stock detail: header, price, ranges, stats, tool buttons and Buy/Sell.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:mobile/core/theme.dart';
import 'package:mobile/models/quote.dart';
import 'package:mobile/screens/main/fullscreen_chart_screen.dart';
import 'package:mobile/screens/main/option_chain_screen.dart';
import 'package:mobile/screens/main/order_entry_screen.dart';
import 'package:mobile/screens/main/stock_detail_screen.dart';
import 'package:mobile/services/app_flags_service.dart';
import 'package:mobile/services/auth_service.dart';
import 'package:mobile/services/currency_service.dart';
import 'package:mobile/services/plan_service.dart';
import 'package:mobile/services/theme_service.dart';

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

Quote _q({String market = 'stock'}) => Quote(
      symbol: 'RELIANCE', yfSymbol: 'RELIANCE.NS', name: 'Reliance Industries', price: 2948.30,
      previousClose: 2915.65, change: 32.65, changePct: 1.12, currency: 'INR', market: market,
      open: 2918.40, dayHigh: 2956.00, dayLow: 2911.10, volume: 6420000,
    );

Future<void> _pump(WidgetTester tester, {String market = 'stock'}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  // The order ticket reads these, as it does inside the app.
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => AuthService()),
      ChangeNotifierProvider.value(value: ThemeService()),
      ChangeNotifierProvider.value(value: AppFlagsService.instance),
      ChangeNotifierProvider.value(value: CurrencyService.instance),
      ChangeNotifierProvider.value(value: PlanService.instance),
    ],
    child: MaterialApp(
      theme: AppTheme.darkTheme,
      home: StockDetailScreen(symbol: 'RELIANCE', market: market, name: 'Reliance Industries', initialQuote: _q(market: market)),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

Future<void> _tapVisible(WidgetTester tester, Finder f) async {
  await tester.scrollUntilVisible(f, 120, scrollable: find.byType(Scrollable).first);
  await tester.tap(f);
  await _settle(tester);
}

void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await _loadFonts();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(url: 'http://127.0.0.1:9', anonKey: 'stock-test-key');
  });

  test('volume reads compactly', () {
    expect(compactVolume(6420000), '6.42M');
    expect(compactVolume(1200000000), '1.20B');
    expect(compactVolume(84500), '84.5K');
    expect(compactVolume(950), '950');
  });

  testWidgets('header, price, ranges and stats as designed', (tester) async {
    await _pump(tester);
    expect(find.text('RELIANCE'), findsOneWidget);
    expect(find.text('NSE · Reliance Industries'), findsOneWidget);
    expect(find.textContaining('(+1.12%)'), findsOneWidget);
    for (final r in kStockRanges.keys) {
      expect(find.text(r), findsOneWidget, reason: r);
    }
    expect(find.text('Pro chart'), findsOneWidget);
    expect(find.text('Option chain'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('KEY STATS'), 120, scrollable: find.byType(Scrollable).first);
    expect(find.text('Volume'), findsOneWidget);
    expect(find.text('6.42M'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('+ Set alert'), 120, scrollable: find.byType(Scrollable).first);
    expect(find.text('PRICE ALERTS'), findsOneWidget);
  });

  testWidgets('Sell sits left of Buy and each opens its side of the ticket', (tester) async {
    await _pump(tester);
    expect(tester.getCenter(find.text('Sell')).dx, lessThan(tester.getCenter(find.text('Buy')).dx));
    await tester.tap(find.text('Buy'));
    await _settle(tester);
    expect(tester.widget<OrderEntryScreen>(find.byType(OrderEntryScreen)).isBuy, isTrue);
  });

  testWidgets('Option chain opens the chain', (tester) async {
    await _pump(tester);
    await _tapVisible(tester, find.text('Option chain'));
    expect(find.byType(OptionChainScreen), findsOneWidget);
  });

  testWidgets('full-screen chip opens the pro chart', (tester) async {
    await _pump(tester);
    await tester.tap(find.bySemanticsLabel('Open full-screen chart'));
    await _settle(tester);
    // Its TradingView WebView has no platform in tests; the route is what matters.
    tester.takeException();
    expect(find.byType(FullscreenChartScreen), findsOneWidget);
  });

  testWidgets('crypto has no option chain button', (tester) async {
    await _pump(tester, market: 'crypto');
    expect(find.text('Option chain'), findsNothing);
    expect(find.text('Crypto · Reliance Industries'), findsOneWidget);
  });
}
