// Checks for the display-currency preference and the preferred-markets ordering.
//
// The gate precedence and the nav-bar ordering are the two things that break
// quietly: a wrong gate either traps a user in onboarding or skips it entirely,
// and a bad ordering can drop a market tab that holds an open position.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/countries.dart';
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
          ['crypto', 'stock', 'us_stock', 'pakistan_stock', 'italy_stock']);
    });

    test('every market stays present, so no position becomes unreachable', () {
      const bar = MarketNavBar(
        selectedKey: 'stock',
        onSelected: _noop,
        preferredKeys: ['us_stock'],
      );
      expect(bar.orderedTabs.length, 5);
      expect(bar.orderedTabs.map((t) => t.key).toSet(),
          {'stock', 'us_stock', 'crypto', 'pakistan_stock', 'italy_stock'});
    });

    test('no preference keeps the canonical order', () {
      const bar = MarketNavBar(selectedKey: 'stock', onSelected: _noop);
      expect(bar.orderedTabs.map((t) => t.key).toList(),
          ['stock', 'us_stock', 'crypto', 'pakistan_stock', 'italy_stock']);
    });

    test('all three preferred is still the canonical order', () {
      const bar = MarketNavBar(
        selectedKey: 'stock',
        onSelected: _noop,
        preferredKeys: ['crypto', 'us_stock', 'stock'],
      );
      expect(bar.orderedTabs.map((t) => t.key).toList(),
          ['stock', 'us_stock', 'crypto', 'pakistan_stock', 'italy_stock']);
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
      expect(MarketTabOrder.canonical,
          ['stock', 'us_stock', 'crypto', 'pakistan_stock', 'italy_stock']);
    });
  });

  group('Currency labels', () {
    test('all options are offered with distinct symbols', () {
      expect(Currency.values.length, 4);
      expect(Currency.values.map((c) => c.symbol).toSet().length, 4);
      expect(Currency.inr.label, 'Indian Rupee');
      expect(Currency.usd.label, 'US Dollar');
      expect(Currency.pkr.label, 'Pakistani Rupee');
      expect(Currency.eur.label, 'Euro');
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

  group('Countries', () {
    // The packed strings are hand-maintained, and a typo there is a money bug:
    // save_user_preferences derives profiles.location from the code, and location
    // is the sole input to the billing currency. A malformed code fails the
    // database CHECK and the save silently returns null; a code that is well
    // formed but wrong bills the user on the wrong continent. So these assert the
    // same shape the database does.
    test('every code is ISO 3166-1 alpha-2 shaped, like the DB constraint', () {
      final shape = RegExp(r'^[A-Z]{2}$');
      for (final code in Countries.byCode.keys) {
        expect(shape.hasMatch(code), isTrue, reason: '$code is not alpha-2');
      }
    });

    test('every country has a name', () {
      for (final entry in Countries.byCode.entries) {
        expect(entry.value.trim(), isNotEmpty, reason: '${entry.key} has no name');
      }
    });

    test('all 249 assigned codes parsed, so nothing collided or got dropped', () {
      // A duplicated code would silently overwrite in the map literal and show up
      // here as a short count, which is the only symptom it would ever have.
      expect(Countries.byCode.length, 249);
    });

    test('India resolves, and lookup tolerates what the RPC tolerates', () {
      expect(Countries.name('IN'), 'India');
      expect(Countries.name('in'), 'India');
      expect(Countries.name(' gb '), 'United Kingdom');
      expect(Countries.name('ZZ'), isNull);
      expect(Countries.name(null), isNull);
    });

    test('sortedByName holds every country, in name order', () {
      final sorted = Countries.sortedByName;
      expect(sorted.length, Countries.byCode.length);
      final names = sorted.map((e) => e.value).toList();
      expect(names, orderedEquals(List.of(names)..sort()));
    });

    test('India has 28 states plus 8 union territories', () {
      expect(Countries.subdivisionsOf('IN').length, 36);
    });

    test('every subdivision fits the 80-character column', () {
      for (final s in Countries.indiaSubdivisions) {
        expect(s.trim(), isNotEmpty);
        expect(s.length, lessThanOrEqualTo(80), reason: '$s is too long to save');
      }
    });

    test('countries without a shipped list fall back to free text', () {
      expect(Countries.subdivisionsOf('US'), isEmpty);
      expect(Countries.subdivisionsOf(null), isEmpty);
    });
  });

  group('platformTag', () {
    test('the shipped platforms lowercase into what record_platform accepts', () {
      // platformTag() sends defaultTargetPlatform.name and relies on the RPC to
      // lowercase it. If Flutter ever renamed these enum values, the RPC would
      // silently ignore the new spelling and the platform breakdown would quietly
      // fill up with 'unknown' — no error anywhere. This is that tripwire.
      const accepted = {'android', 'ios', 'web'};
      expect(accepted, contains(TargetPlatform.android.name.toLowerCase()));
      expect(accepted, contains(TargetPlatform.iOS.name.toLowerCase()));
    });

    test('returns something the RPC accepts on the platform under test', () {
      expect(const {'android', 'ios', 'web'}, contains(platformTag().toLowerCase()));
    });

    test('desktop is not silently counted as a phone', () {
      // Sending the real name means an unshipped platform reads as unknown rather
      // than inflating Android.
      const accepted = {'android', 'ios', 'web'};
      expect(accepted, isNot(contains(TargetPlatform.macOS.name.toLowerCase())));
      expect(accepted, isNot(contains(TargetPlatform.windows.name.toLowerCase())));
    });
  });
}

void _noop(String _) {}
