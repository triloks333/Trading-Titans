// Commodities: the More sheet that holds them, their session, and fractional sizing.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/market_hours.dart';
import 'package:mobile/widgets/market_nav_bar.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('More sheet', () {
    const bar = MarketNavBar(
      selectedKey: 'stock',
      onSelected: _noop,
      filterToPreferred: true,
      preferredKeys: ['stock', 'us_stock', 'crypto'],
    );

    test('every market not on the bar, plus F&O, sits behind More', () {
      expect(bar.orderedTabs.map((t) => t.key), ['stock', 'us_stock', 'crypto']);
      expect(bar.overflowTabs.map((t) => t.key), ['commodity', 'pakistan_stock', 'italy_stock', 'fo']);
    });

    test('commodity can be one of the three', () {
      const picked = MarketNavBar(
        selectedKey: 'commodity',
        onSelected: _noop,
        filterToPreferred: true,
        preferredKeys: ['stock', 'crypto', 'commodity'],
      );
      expect(picked.orderedTabs.map((t) => t.key), ['stock', 'crypto', 'commodity']);
      expect(picked.overflowTabs.map((t) => t.key), contains('us_stock'));
    });

    testWidgets('tapping More opens the sheet and reports the pick', (tester) async {
      final tapped = <String>[];
      await tester.pumpWidget(_wrap(MarketNavBar(
        selectedKey: 'stock',
        onSelected: tapped.add,
        filterToPreferred: true,
        preferredKeys: const ['stock', 'us_stock', 'crypto'],
      )));

      await tester.tap(find.text('More ▾'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Commodities'));
      await tester.pumpAndSettle();

      expect(tapped, ['commodity']);
    });

    testWidgets('an open overflow market names the More segment', (tester) async {
      await tester.pumpWidget(_wrap(const MarketNavBar(
        selectedKey: 'commodity',
        onSelected: _noop,
        filterToPreferred: true,
        preferredKeys: ['stock', 'us_stock', 'crypto'],
      )));
      expect(find.text('Commodities ▾'), findsOneWidget);
    });
  });

  group('Commodity session (mirrors isCommodityOpen in us_market_test.ts)', () {
    // November 2026 is EST (UTC-5): 18:00 ET = 23:00 UTC.
    DateTime utc(int d, int h, [int m = 0]) => DateTime.utc(2026, 11, d, h, m);
    bool open(DateTime at) => MarketHours.isOpen(MarketHours.commodity, at: at);

    test('Sun 18:00 ET to Fri 17:00 ET with a daily break', () {
      expect(open(utc(8, 22, 59)), isFalse); // Sun 17:59 ET
      expect(open(utc(8, 23)), isTrue); // Sun 18:00 ET opens
      expect(open(utc(9, 15)), isTrue); // Mon 10:00 ET
      expect(open(utc(9, 22, 30)), isFalse); // Mon 17:30 ET, daily break
      expect(open(utc(9, 23)), isTrue); // Mon 18:00 ET
      expect(open(utc(13, 21, 59)), isTrue); // Fri 16:59 ET
      expect(open(utc(13, 22)), isFalse); // Fri 17:00 ET closes
      expect(open(utc(14, 15)), isFalse); // Saturday
    });

    test('closed status names the reopen in IST', () {
      expect(MarketHours.statusText(MarketHours.commodity, at: utc(9, 22, 30)), 'Opens at 4:30 AM IST');
      expect(MarketHours.statusText(MarketHours.commodity, at: utc(14, 15)), 'Weekend Closed');
    });
  });

  test('crypto and commodities trade in fractions, stocks do not', () {
    expect(MarketHours.isFractional('commodity'), isTrue);
    expect(MarketHours.isFractional('crypto'), isTrue);
    expect(MarketHours.isFractional('stock'), isFalse);
    expect(MarketHours.isFractional('us_stock'), isFalse);
  });
}

void _noop(String _) {}
