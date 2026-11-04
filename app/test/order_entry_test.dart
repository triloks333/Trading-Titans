// Order ticket: side toggle, order types, quantity stepper and the exit lock.

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
import 'package:mobile/screens/main/order_entry_screen.dart';
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

Quote _reliance() => Quote(
      symbol: 'RELIANCE', yfSymbol: 'RELIANCE.NS', name: 'Reliance Industries', price: 2948.30,
      previousClose: 2915.65, change: 32.65, changePct: 1.12, currency: 'INR', market: 'stock',
    );

Future<void> _pump(WidgetTester tester, {bool isBuy = true, bool exit = false}) async {
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
    child: MaterialApp(
      theme: AppTheme.darkTheme,
      home: OrderEntryScreen(quote: _reliance(), isBuy: isBuy, isExitOrder: exit, prefilledQuantity: exit ? 5 : null),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await _loadFonts();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(url: 'http://127.0.0.1:9', anonKey: 'order-test-key');
  });

  void selected(WidgetTester t, String label, bool on) =>
      expect(t.getSemantics(find.bySemanticsLabel(label)), containsSemantics(isSelected: on), reason: label);

  testWidgets('Buy/Sell toggle switches side', (tester) async {
    await _pump(tester);
    selected(tester, 'Buy', true);
    await tester.tap(find.bySemanticsLabel('Sell'));
    await tester.pump();
    selected(tester, 'Sell', true);
    selected(tester, 'Buy', false);
    // No signed-in wallet in tests, so the ticket asks for a top-up instead of a swipe.
    expect(find.text('Insufficient balance'), findsOneWidget);
  });

  testWidgets('order types: Market greys the price, SL adds a trigger field', (tester) async {
    await _pump(tester);
    for (final t in ['Market', 'Limit', 'SL', 'SL-M']) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
    expect(find.text('At market'), findsOneWidget, reason: 'opens on Market');
    expect(find.text('Stoploss trigger'), findsNothing);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 300));
    await tester.pump();

    await tester.tap(find.text('Limit'));
    await tester.pump();
    expect(find.text('At market'), findsNothing);

    await tester.tap(find.text('SL'));
    await tester.pump();
    expect(find.text('Stoploss trigger'), findsOneWidget);

    await tester.tap(find.text('SL-M'));
    await tester.pump();
    expect(find.text('Stoploss trigger'), findsOneWidget);
    expect(find.text('At market'), findsOneWidget);
  });

  testWidgets('+ steps the quantity by one share', (tester) async {
    await _pump(tester);
    await tester.scrollUntilVisible(find.text('Quantity'), 100, scrollable: find.byType(Scrollable).first);
    final qty = find.byType(TextField).first;
    expect(tester.widget<TextField>(qty).controller!.text, '1');
    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pump();
    expect(tester.widget<TextField>(qty).controller!.text, '2');
  });

  testWidgets('Delivery/Intraday and validity chips are present', (tester) async {
    await _pump(tester);
    for (final t in ['Delivery', 'Intraday', 'Day', 'IOC', 'Minutes']) {
      expect(find.text(t), findsWidgets, reason: t);
    }
  });

  testWidgets('an exit keeps its side: the toggle does nothing', (tester) async {
    await _pump(tester, isBuy: false, exit: true);
    expect(find.text('Swipe to sell'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Buy'));
    await tester.pump();
    expect(find.text('Swipe to sell'), findsOneWidget);
    expect(find.textContaining('Closing existing position'), findsOneWidget);
  });
}
