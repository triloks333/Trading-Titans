// Trade · Markets: movers ranking, market segments and every tap target.

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
import 'package:mobile/screens/main/option_chain_screen.dart';
import 'package:mobile/screens/main/orders_screen.dart';
import 'package:mobile/screens/main/trade_screen.dart';
import 'package:mobile/services/app_flags_service.dart';
import 'package:mobile/services/currency_service.dart';

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

Quote _q(String s, double pct) => Quote(
    symbol: s, yfSymbol: s, name: s, price: 100, previousClose: 100, change: pct, changePct: pct, currency: 'INR', market: 'stock');

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: AppFlagsService.instance),
      ChangeNotifierProvider.value(value: CurrencyService.instance),
    ],
    child: MaterialApp(theme: AppTheme.darkTheme, home: const TradeScreen()),
  ));
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await _loadFonts();
    // Preferences already chosen, so the first-run dialog stays shut.
    SharedPreferences.setMockInitialValues({'market_preferences_configured': true});
    await Supabase.initialize(url: 'http://127.0.0.1:9', anonKey: 'trade-test-key');
  });

  test('gainers rank biggest rise first, losers biggest fall first, flat in neither', () {
    final quotes = [_q('A', 1.2), _q('B', -3.0), _q('C', 4.5), _q('D', 0), _q('E', -0.4)];
    expect(topMovers(quotes, gainers: true).map((q) => q.symbol), ['C', 'A']);
    expect(topMovers(quotes, gainers: false).map((q) => q.symbol), ['B', 'E']);
    expect(topMovers([for (var i = 1; i <= 20; i++) _q('S$i', i.toDouble())], gainers: true).length, 8);
  });

  test('every market has a movers universe and index cards', () {
    for (final m in ['stock', 'us_stock', 'crypto', 'pakistan_stock', 'italy_stock']) {
      expect(kMoverUniverse[m], isNotEmpty, reason: m);
      expect(kMarketIndices[m], isNotEmpty, reason: m);
    }
  });

  testWidgets('India shows index cards, movers with Gainers/Losers and the NIFTY chain card', (tester) async {
    await _pump(tester);
    expect(find.text('NIFTY 50'), findsOneWidget);
    expect(find.text('BANKNIFTY'), findsOneWidget);
    expect(find.text('TOP MOVERS · INDIA'), findsOneWidget);
    final gainers = find.widgetWithText(ChoiceChip, 'Gainers'), losers = find.widgetWithText(ChoiceChip, 'Losers');
    expect(tester.widget<ChoiceChip>(gainers).selected, isTrue);
    await tester.tap(losers);
    await tester.pump();
    expect(tester.widget<ChoiceChip>(losers).selected, isTrue);
    expect(tester.widget<ChoiceChip>(gainers).selected, isFalse);

    final chain = find.text('Option chain · NIFTY');
    await tester.scrollUntilVisible(chain, 120, scrollable: find.byType(Scrollable).last);
    await tester.tap(chain);
    await _settle(tester);
    expect(find.byType(OptionChainScreen), findsOneWidget);
  });

  testWidgets('F&O segment lists option chains and opens one', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('F&O'));
    await tester.pump();
    expect(find.text('OPTION CHAINS · FUTURES'), findsOneWidget);
    expect(find.text('BANKNIFTY'), findsWidgets);
    await tester.tap(find.text('RELIANCE'));
    await _settle(tester);
    expect(find.byType(OptionChainScreen), findsOneWidget);
  });

  testWidgets('order book button opens Orders', (tester) async {
    await _pump(tester);
    await tester.tap(find.bySemanticsLabel('Order book'));
    await _settle(tester);
    expect(find.byType(OrdersScreen), findsOneWidget);
  });
}
