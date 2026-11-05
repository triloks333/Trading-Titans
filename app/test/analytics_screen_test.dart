// Analytics: stats over closed trades only, periods, charts and the autopsy link.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:mobile/core/theme.dart';
import 'package:mobile/models/order.dart';
import 'package:mobile/screens/main/analytics_screen.dart';
import 'package:mobile/screens/main/autopsy_screen.dart';

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

final _now = DateTime.now();
Order _o(double pnl, int daysAgo, {String market = 'stock', String? type}) => Order(
      id: '$pnl$daysAgo', symbol: 'X', name: 'X', market: market, side: 'sell', quantity: 1, price: 1, total: 1,
      realizedPnl: pnl, executedAt: _now.subtract(Duration(days: daysAgo, hours: 1)), instrumentType: type,
    );

final _orders = [
  _o(0, 1), // an opening buy: not a trade result
  _o(20, 2),
  _o(-10, 3),
  _o(30, 4, market: 'crypto'),
  _o(-5, 5, type: 'OPTION'),
  _o(100, 60), // outside 1M
];

void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await _loadFonts();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(url: 'http://127.0.0.1:9', anonKey: 'analytics-test-key');
  });

  test('stats count closing trades only and respect the period', () {
    final m = TradeStats.from(_orders, period: const Duration(days: 30), now: _now);
    expect(m.trades, 4);
    expect(m.winRate, 50);
    expect(m.total, 35);
    expect(m.avgWin, 25);
    expect(m.avgLoss, -7.5);
    expect(m.profitFactor, closeTo(50 / 15, 1e-9));
    // Oldest first: -5, +30, -10, +20 → curve 0,-5,25,15,35; worst fall from peak is -10.
    expect(m.curve, [0, -5, 25, 15, 35]);
    expect(m.maxDrawdown, -10);
    expect(m.byMarket, {'F&O': -5, 'Crypto': 30, 'India': 10});
    expect(m.daily().length, 4);

    final all = TradeStats.from(_orders, now: _now);
    expect(all.trades, 5);
    expect(TradeStats.from(const []).profitFactor, 0);
  });

  testWidgets('KPIs, charts, period chips and the autopsy link', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(theme: AppTheme.darkTheme, home: AnalyticsScreen(orders: _orders)));
    await tester.pumpAndSettle();

    for (final t in ['Win rate', 'Profit factor', 'Trades', 'Avg win', 'Avg loss', 'Max drawdown', 'EQUITY CURVE · REALISED', 'P&L BY MARKET']) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
    expect(find.text('50%'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);

    await tester.tap(find.text('All'));
    await tester.pump();
    expect(find.text('5'), findsOneWidget, reason: 'All includes the 60-day-old trade');

    final card = find.text('Your edge is working'); // avg win 25 beats avg loss 7.5
    await tester.scrollUntilVisible(card, 120, scrollable: find.byType(Scrollable).first);
    await tester.tap(card);
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.byType(AutopsyScreen), findsOneWidget);
  });
}
