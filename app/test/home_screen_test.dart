// Home (DashboardScreen): realised-P&L curve and every tap target on the design.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:showcaseview/showcaseview.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:mobile/core/theme.dart';
import 'package:mobile/models/order.dart';
import 'package:mobile/screens/main/analytics_screen.dart';
import 'package:mobile/screens/main/autopsy_screen.dart';
import 'package:mobile/screens/main/chat_screen.dart';
import 'package:mobile/screens/main/dashboard_screen.dart';
import 'package:mobile/screens/main/notifications_screen.dart';
import 'package:mobile/screens/main/orders_screen.dart';
import 'package:mobile/screens/main/watchlist_screen.dart';
import 'package:mobile/screens/main/whatif_screen.dart';
import 'package:mobile/services/app_flags_service.dart';
import 'package:mobile/services/auth_service.dart';
import 'package:mobile/services/currency_service.dart';
import 'package:mobile/services/nav_tab_service.dart';
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

Order _o(double pnl, DateTime at) =>
    Order(id: '$at', symbol: 'X', name: 'X', market: 'stock', side: 'sell', quantity: 1, price: 1, total: 1, realizedPnl: pnl, executedAt: at);

Future<void> _pumpHome(WidgetTester tester) async {
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
    // ignore: deprecated_member_use
    child: MaterialApp(theme: AppTheme.darkTheme, home: ShowCaseWidget(builder: (_) => const DashboardScreen())),
  ));
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

Future<void> _tapAndExpect(WidgetTester tester, Finder target, Type screen) async {
  await tester.scrollUntilVisible(target, 120, scrollable: find.byType(Scrollable).first);
  await tester.tap(target);
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
  expect(find.byType(screen), findsOneWidget);
}

void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await _loadFonts();
    SharedPreferences.setMockInitialValues({'dashboard_tour_seen': true});
    await Supabase.initialize(url: 'http://127.0.0.1:9', anonKey: 'home-test-key');
  });

  test('realised curve sums closing fills inside the range, oldest first', () {
    final now = DateTime(2026, 11, 4, 12);
    final orders = [
      _o(50, now.subtract(const Duration(hours: 2))),
      _o(-20, now.subtract(const Duration(days: 3))),
      _o(100, now.subtract(const Duration(days: 40))),
      _o(0, now.subtract(const Duration(hours: 1))), // an opening buy: no realised P&L
    ];
    expect(realisedCurve(orders, const Duration(days: 1), now: now), [0, 50]);
    expect(realisedCurve(orders, const Duration(days: 7), now: now), [0, -20, 30]);
    expect(realisedCurve(orders, null, now: now), [0, 100, 80, 130]);
  });

  const pushes = <String, Type>{
    'Orders': OrdersScreen,
    'What-If': WhatIfScreen,
    'Autopsy': AutopsyScreen,
    'Analytics': AnalyticsScreen,
    'Titans Room': ChatScreen,
    'See all': WatchlistScreen,
  };
  for (final e in pushes.entries) {
    testWidgets('"${e.key}" opens ${e.value}', (tester) async {
      await _pumpHome(tester);
      await _tapAndExpect(tester, find.text(e.key), e.value);
    });
  }

  testWidgets('header bell opens Notifications', (tester) async {
    await _pumpHome(tester);
    await tester.tap(find.bySemanticsLabel('Notifications'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.byType(NotificationsScreen), findsOneWidget);
  });

  testWidgets('Trade now, Search and Add demo cash switch tabs; ranges select', (tester) async {
    await _pumpHome(tester);
    final requests = <int>[];
    void listen() => requests.add(NavTabService.tabRequest.value);
    NavTabService.tabRequest.addListener(listen);
    addTearDown(() => NavTabService.tabRequest.removeListener(listen));
    await tester.tap(find.text('Trade now'));
    await tester.tap(find.text('Add demo cash'));
    await tester.tap(find.text('Search'));
    expect(requests.where((r) => r >= 0), [NavTabService.trade, NavTabService.wallet, NavTabService.trade]);

    expect(find.text('No closed trades in 1M'), findsOneWidget);
    await tester.tap(find.text('1Y'));
    await tester.pump();
    expect(find.text('No closed trades in 1Y'), findsOneWidget);
    expect(find.text('TOTAL PORTFOLIO VALUE · DEMO CASH'), findsOneWidget);
  });
}
