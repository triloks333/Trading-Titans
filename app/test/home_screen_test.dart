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

  test('portfolio curve moves each position with its own price, ends at today', () {
    // ₹1,000 total: ₹500 of stock A (long), ₹200 short of B, rest cash.
    final legs = <ChartLeg>[
      (value: 500, sign: 1, prices: [(1, 80.0), (2, 90.0), (3, 100.0)]),
      (value: 200, sign: -1, prices: [(2, 50.0), (3, 40.0)]),
    ];
    // t1: A at 80% => -100; B before its first point uses 50 => short -(200*0.25) = -50.
    // t2: A 90% => -50, B 50 => -50.  t3: both at latest => 0.  Then today's total.
    expect(portfolioCurve(1000, legs), [850, 900, 1000, 1000]);
    expect(portfolioCurve(1000, const []), [1000, 1000], reason: 'cash only is flat');
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

    expect(find.byType(CustomPaint), findsWidgets);
    expect(find.textContaining('1M  +'), findsOneWidget);
    await tester.tap(find.text('1Y'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('1Y  +'), findsOneWidget);
    expect(find.text('TOTAL PORTFOLIO VALUE · DEMO CASH'), findsOneWidget);
  });
}
