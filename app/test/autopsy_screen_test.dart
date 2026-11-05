// Trade autopsy: grades, entry price, trade chips, sections and actions.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:mobile/core/theme.dart';
import 'package:mobile/models/order.dart';
import 'package:mobile/screens/main/autopsy_screen.dart';
import 'package:mobile/screens/main/stock_detail_screen.dart';

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

final _data = {
  'summary': 'Analyzed your recent trades: 1 wins and 1 losses.',
  'insights': [
    {'symbol': 'ZOMATO', 'name': 'Zomato', 'market': 'stock', 'pnl': 14.82, 'loss_pct': 11.2, 'type': 'profit',
      'reason': 'Realized profit trading 6 shares.', 'advice': 'Breakouts are your best setup.', 'total_charges': 0.4},
    {'symbol': 'TMPV', 'name': 'Tata Motors', 'market': 'stock', 'pnl': -2.86, 'loss_pct': 5.07, 'type': 'loss',
      'reason': 'Lost on 2 shares.', 'advice': 'Set a stoploss at entry.', 'total_charges': 0.0},
  ],
};

final _orders = [
  Order(id: '1', symbol: 'ZOMATO', name: 'Zomato', market: 'stock', side: 'sell', quantity: 6, price: 246.1, total: 1476.6,
      realizedPnl: 14.82, orderType: 'market', executedAt: DateTime(2026, 11, 1, 10)),
];

void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await _loadFonts();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(url: 'http://127.0.0.1:9', anonKey: 'autopsy-test-key');
  });

  test('grade bands and implied entry price', () {
    expect(autopsyGrade(11.2).grade, 'A+');
    expect(autopsyGrade(3).grade, 'B');
    expect(autopsyGrade(-5.07).grade, 'D');
    expect(autopsyGrade(-3).grade, 'C−');
    // A long closed by a sell at 246.10 for +14.82 over 6 shares entered at 243.63.
    expect(autopsyEntryPrice(_orders.first), closeTo(243.63, 0.001));
    // A short covered by a buy entered above the exit.
    final cover = Order(id: '2', symbol: 'X', name: 'X', market: 'stock', side: 'buy', quantity: 2, price: 100, total: 200, realizedPnl: 10);
    expect(autopsyEntryPrice(cover), 105);
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(theme: AppTheme.darkTheme, home: AutopsyScreen(data: _data, orders: _orders)));
    await tester.pumpAndSettle();
  }

  testWidgets('chips switch trades; grade, what happened and lesson', (tester) async {
    await pump(tester);
    expect(find.text('Trade autopsy'), findsOneWidget);
    expect(find.text('A+'), findsOneWidget);
    expect(find.text('Textbook trade'), findsOneWidget);
    expect(find.textContaining('Entered near'), findsOneWidget);
    expect(find.text('Breakouts are your best setup.'), findsOneWidget);

    await tester.tap(find.text('TMPV'));
    await tester.pump();
    expect(find.text('D'), findsOneWidget);
    expect(find.text('Set a stoploss at entry.'), findsOneWidget);
  });

  testWidgets('Trade again opens the stock; share offers WhatsApp and copy', (tester) async {
    await pump(tester);
    final share = find.text('Share P&L card');
    await tester.scrollUntilVisible(share, 120, scrollable: find.byType(Scrollable).last);
    await tester.tap(share);
    await tester.pumpAndSettle();
    expect(find.text('Share on WhatsApp'), findsOneWidget);
    expect(find.text('Copy text'), findsOneWidget);
    await tester.tapAt(const Offset(195, 40));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Trade again'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.byType(StockDetailScreen), findsOneWidget);
  });
}
