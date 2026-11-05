// Orders: status grouping, tabs, date filter and empty states.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:mobile/core/theme.dart';
import 'package:mobile/screens/main/orders_screen.dart';

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
  await tester.pumpWidget(MaterialApp(theme: AppTheme.darkTheme, home: const OrdersScreen()));
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await _loadFonts();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(url: 'http://127.0.0.1:9', anonKey: 'orders-test-key');
  });

  test('statuses group into Open, Executed and Cancelled', () {
    expect(OrdersScreen.tabOf('pending'), 0);
    expect(OrdersScreen.tabOf('executed'), 1);
    expect(OrdersScreen.tabOf('filled'), 1);
    for (final s in ['cancelled', 'rejected', 'failed']) {
      expect(OrdersScreen.tabOf(s), 2, reason: s);
    }
  });

  testWidgets('header, status tabs with counts and the day bar', (tester) async {
    await _pump(tester);
    expect(find.text('Orders'), findsOneWidget);
    for (final t in ['Open · 0', 'Executed · 0', 'Cancelled · 0']) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('No orders today'), findsOneWidget);
  });

  testWidgets('filter opens the date picker', (tester) async {
    await _pump(tester);
    await tester.tap(find.bySemanticsLabel('Filter by date'));
    await tester.pumpAndSettle();
    expect(find.text('Select order date'), findsOneWidget);
  });
}
