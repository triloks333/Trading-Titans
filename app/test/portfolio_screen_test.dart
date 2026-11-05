// Portfolio: header, segments and the tool cards.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:mobile/core/theme.dart';
import 'package:mobile/models/portfolio.dart';
import 'package:mobile/screens/main/analytics_screen.dart';
import 'package:mobile/screens/main/autopsy_screen.dart';
import 'package:mobile/screens/main/orders_screen.dart';
import 'package:mobile/screens/main/portfolio_screen.dart';
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

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => AuthService()),
      ChangeNotifierProvider.value(value: ThemeService()),
      ChangeNotifierProvider.value(value: AppFlagsService.instance),
      ChangeNotifierProvider.value(value: CurrencyService.instance),
      ChangeNotifierProvider.value(value: PlanService.instance),
    ],
    child: MaterialApp(theme: AppTheme.darkTheme, home: const PortfolioScreen()),
  ));
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

Future<void> _open(WidgetTester tester, Finder f, Type screen) async {
  await tester.scrollUntilVisible(f, 120, scrollable: find.byType(Scrollable).first);
  await tester.tap(f);
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
  expect(find.byType(screen), findsOneWidget);
}

void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await _loadFonts();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(url: 'http://127.0.0.1:9', anonKey: 'portfolio-test-key');
  });

  testWidgets('summary, column heads and segments', (tester) async {
    await _pump(tester);
    for (final t in ['CURRENT VALUE', 'TOTAL P&L', 'Deployed capital', 'Today']) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
    expect(find.text('No holdings yet'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Positions (0)'));
    await tester.pump();
    expect(find.text('No open F&O positions'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Closed (0)'));
    await tester.pump();
    expect(find.text('No closed positions'), findsOneWidget);
  });

  testWidgets('Analytics button opens Analytics', (tester) async {
    await _pump(tester);
    await tester.tap(find.bySemanticsLabel('Analytics'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.byType(AnalyticsScreen), findsOneWidget);
  });

  testWidgets('Trade autopsy card opens Autopsy', (tester) async {
    await _pump(tester);
    await _open(tester, find.text('Trade autopsy'), AutopsyScreen);
  });

  testWidgets('Orders card opens Orders', (tester) async {
    await _pump(tester);
    await _open(tester, find.text('Orders'), OrdersScreen);
  });

  test('LTP day change is against the previous close, in the holding currency', () {
    Holding h({double prev = 17.98, double? nativePrev, String? ccy}) => Holding(
          symbol: 'MGEL', name: 'MGEL', market: ccy == null ? 'stock' : 'us_stock', quantity: 3300, avgPrice: 17.82,
          currentPrice: 18.10, previousClose: prev, invested: 58806, current: 59730, pnl: 924, pnlPct: 1.57,
          dayPnl: 396, dayPnlPct: 0.67, nativeCurrentPrice: ccy == null ? null : 10.0, nativePreviousClose: nativePrev, nativeCurrency: ccy);
    expect(ltpDayChangePct(h()), closeTo(0.667, 0.001));
    expect(ltpDayChangePct(h(prev: 0)), 0);
    expect(ltpDayChangePct(h(nativePrev: 8, ccy: 'USD')), closeTo(25, 0.001), reason: 'US uses the dollar close');
  });
}
