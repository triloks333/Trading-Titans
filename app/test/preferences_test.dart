// Checks for the display-currency preference and the preferred-markets ordering.
//
// The gate precedence and the nav-bar ordering are the two things that break
// quietly: a wrong gate either traps a user in onboarding or skips it entirely,
// and a bad ordering can drop a market tab that holds an open position.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/currency.dart';
import 'package:mobile/main.dart';
import 'package:mobile/services/currency_service.dart';
import 'package:mobile/widgets/market_nav_bar.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('selectActiveGate with onboarding', () {
    test('onboarding shows for a signed-in user who has not answered', () {
      expect(
        selectActiveGate(
          isInitializing: false,
          needsMaintenanceMode: false,
          needsHardUpdate: false,
          isAuthenticated: true,
          needsOnboarding: true,
        ),
        ActiveGate.onboarding,
      );
    });

    test('onboarding never shows to a signed-out visitor', () {
      // Otherwise the login screen would be replaced by a form that cannot save.
      expect(
        selectActiveGate(
          isInitializing: false,
          needsMaintenanceMode: false,
          needsHardUpdate: false,
          isAuthenticated: false,
          needsOnboarding: true,
        ),
        ActiveGate.normal,
      );
    });

    test('maintenance and hard update both outrank onboarding', () {
      expect(
        selectActiveGate(
          isInitializing: false,
          needsMaintenanceMode: true,
          needsHardUpdate: false,
          isAuthenticated: true,
          needsOnboarding: true,
        ),
        ActiveGate.maintenance,
      );
      expect(
        selectActiveGate(
          isInitializing: false,
          needsMaintenanceMode: false,
          needsHardUpdate: true,
          isAuthenticated: true,
          needsOnboarding: true,
        ),
        ActiveGate.hardUpdate,
      );
    });

    test('loading still wins over everything', () {
      expect(
        selectActiveGate(
          isInitializing: true,
          needsMaintenanceMode: true,
          needsHardUpdate: true,
          isAuthenticated: true,
          needsOnboarding: true,
        ),
        ActiveGate.loading,
      );
    });

    test('an answered user goes straight to the app', () {
      expect(
        selectActiveGate(
          isInitializing: false,
          needsMaintenanceMode: false,
          needsHardUpdate: false,
          isAuthenticated: true,
          needsOnboarding: false,
        ),
        ActiveGate.normal,
      );
    });

    test('existing three-argument callers still compile and behave', () {
      // The new parameters are optional, so pre-existing gating logic is intact.
      expect(
        selectActiveGate(
          isInitializing: false,
          needsMaintenanceMode: false,
          needsHardUpdate: false,
        ),
        ActiveGate.normal,
      );
    });
  });

  group('MarketNavBar ordering', () {
    test('preferred markets sort to the front, canonical order within groups', () {
      const bar = MarketNavBar(
        selectedKey: 'stock',
        onSelected: _noop,
        preferredKeys: ['crypto'],
      );
      expect(bar.orderedTabs.map((t) => t.key).toList(),
          ['crypto', 'stock', 'us_stock']);
    });

    test('every market stays present, so no position becomes unreachable', () {
      const bar = MarketNavBar(
        selectedKey: 'stock',
        onSelected: _noop,
        preferredKeys: ['us_stock'],
      );
      expect(bar.orderedTabs.length, 3);
      expect(bar.orderedTabs.map((t) => t.key).toSet(),
          {'stock', 'us_stock', 'crypto'});
    });

    test('no preference keeps the canonical order', () {
      const bar = MarketNavBar(selectedKey: 'stock', onSelected: _noop);
      expect(bar.orderedTabs.map((t) => t.key).toList(),
          ['stock', 'us_stock', 'crypto']);
    });

    test('all three preferred is still the canonical order', () {
      const bar = MarketNavBar(
        selectedKey: 'stock',
        onSelected: _noop,
        preferredKeys: ['crypto', 'us_stock', 'stock'],
      );
      expect(bar.orderedTabs.map((t) => t.key).toList(),
          ['stock', 'us_stock', 'crypto']);
    });

    testWidgets('renders in the preferred order', (tester) async {
      await tester.pumpWidget(_wrap(const MarketNavBar(
        selectedKey: 'crypto',
        onSelected: _noop,
        preferredKeys: ['crypto'],
      )));
      await tester.pumpAndSettle();

      // Crypto is selected, so it is the only labelled tab.
      expect(find.text('Crypto'), findsOneWidget);
      // And it sits left of the others.
      final crypto = tester.getTopLeft(find.byIcon(Icons.currency_bitcoin)).dx;
      final india = tester.getTopLeft(find.byIcon(Icons.currency_rupee)).dx;
      expect(crypto, lessThan(india));
    });
  });

  group('MarketTabOrder', () {
    test('canonical order matches the nav bar default', () {
      expect(MarketTabOrder.canonical, ['stock', 'us_stock', 'crypto']);
    });
  });

  group('Currency labels', () {
    test('both options are offered with distinct symbols', () {
      expect(Currency.values.length, 2);
      expect(Currency.values.map((c) => c.symbol).toSet().length, 2);
      expect(Currency.inr.label, 'Indian Rupee');
      expect(Currency.usd.label, 'US Dollar');
    });
  });

  group('TradingLocation', () {
    test('exactly two options, matching the stored codes', () {
      expect(TradingLocation.values.length, 2);
      expect(TradingLocation.values.map((l) => l.code).toList(),
          ['india', 'outside_india']);
    });

    test('parses codes and rejects anything else', () {
      expect(TradingLocation.fromCode('india'), TradingLocation.india);
      expect(TradingLocation.fromCode('INDIA'), TradingLocation.india);
      expect(TradingLocation.fromCode('outside_india'), TradingLocation.outsideIndia);
      // Null rather than a silent default: an unanswered question should read as
      // unanswered, not as "India".
      expect(TradingLocation.fromCode(null), isNull);
      expect(TradingLocation.fromCode('mars'), isNull);
    });

    test('suggests a currency per location', () {
      expect(TradingLocation.india.suggestedCurrency, Currency.inr);
      expect(TradingLocation.outsideIndia.suggestedCurrency, Currency.usd);
    });

    test('suggested markets are valid and non-empty', () {
      for (final l in TradingLocation.values) {
        expect(l.suggestedMarkets, isNotEmpty);
        for (final m in l.suggestedMarkets) {
          expect(MarketTabOrder.canonical, contains(m),
              reason: '\$m is not a known market');
        }
      }
      expect(TradingLocation.india.suggestedMarkets, contains('stock'));
      expect(TradingLocation.outsideIndia.suggestedMarkets, contains('us_stock'));
    });

    test('both options have distinct, non-empty copy', () {
      final labels = TradingLocation.values.map((l) => l.label).toSet();
      expect(labels.length, 2);
      for (final l in TradingLocation.values) {
        expect(l.label, isNotEmpty);
        expect(l.subtitle, isNotEmpty);
      }
    });
  });
}

void _noop(String _) {}
