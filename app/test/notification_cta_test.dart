// The call-to-action on a broadcast notification.
//
// These rows are written server-side and then handed to the platform launcher, so
// `ctaLabel` is a trust boundary rather than a formatting helper: it decides both
// whether a button appears and whether a URL is allowed to leave the app. A label
// with no destination is a dead button; a destination with the wrong scheme is a
// way to make the app open something it should not.

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/screens/main/admin_reward_screen.dart';
import 'package:mobile/screens/main/notifications_screen.dart';

void main() {
  group('parseActionData', () {
    test('accepts an already-decoded map', () {
      expect(parseActionData({'cta_label': 'Go'}), {'cta_label': 'Go'});
    });

    test('accepts a JSON string, which is how some rows come back', () {
      expect(parseActionData('{"cta_label":"Go"}'), {'cta_label': 'Go'});
    });

    test('returns null rather than throwing on anything unusable', () {
      expect(parseActionData(null), isNull);
      expect(parseActionData(''), isNull);
      expect(parseActionData('   '), isNull);
      expect(parseActionData('not json at all'), isNull);
      expect(parseActionData('[1,2,3]'), isNull, reason: 'a list is not a map');
      expect(parseActionData(42), isNull);
    });
  });

  group('ctaLabel', () {
    test('shows the button for a known in-app route', () {
      for (final r in ['plans', 'topup', 'subscribe', 'wallet', 'league', 'leaderboard']) {
        expect(ctaLabel({'cta_label': 'Open', 'cta_route': r}), 'Open',
            reason: 'route $r should be accepted');
      }
    });

    test('route matching is case and space insensitive', () {
      expect(ctaLabel({'cta_label': 'Open', 'cta_route': '  Plans '}), 'Open');
      expect(ctaLabel({'cta_label': 'Open', 'cta_route': 'PLANS'}), 'Open');
    });

    test('shows the button for an https url', () {
      expect(
        ctaLabel({
          'cta_label': 'Open',
          'cta_url': 'https://thetradingtitans.com/app/plans',
        }),
        'Open',
      );
    });

    test('no label means no button', () {
      expect(ctaLabel({'cta_route': 'plans'}), isNull);
      expect(ctaLabel({'cta_label': '', 'cta_route': 'plans'}), isNull);
      expect(ctaLabel({'cta_label': '   ', 'cta_route': 'plans'}), isNull);
      expect(ctaLabel(null), isNull);
    });

    test('a label with nowhere to go is refused', () {
      // Otherwise the sheet renders a button that does nothing when tapped.
      expect(ctaLabel({'cta_label': 'Open'}), isNull);
      expect(ctaLabel({'cta_label': 'Open', 'cta_route': ''}), isNull);
    });

    test('an unknown route is refused, so a newer campaign degrades quietly', () {
      // A notification written for a future build naming a route this version
      // does not have must not show a button that leads nowhere.
      expect(ctaLabel({'cta_label': 'Open', 'cta_route': 'greeks_lab'}), isNull);
    });

    test('only https is allowed to leave the app', () {
      for (final bad in [
        'http://thetradingtitans.com/app/plans', // plaintext
        'tel:+911234567890',
        'intent://scan/#Intent;scheme=zxing;end',
        'javascript:alert(1)',
        'file:///etc/passwd',
        'market://details?id=com.kwm.tradingtitans',
        '//thetradingtitans.com',
        'https:/thetradingtitans.com', // one slash short
        'HTTPS://thetradingtitans.com', // scheme is matched case-sensitively
      ]) {
        expect(ctaLabel({'cta_label': 'Open', 'cta_url': bad}), isNull,
            reason: '$bad must not produce a button');
      }
    });

    test('surrounding whitespace is trimmed, not treated as an attack', () {
      // A stray space in a config value is a typo. The URL is still https once
      // trimmed, so it is accepted.
      expect(
        ctaLabel({'cta_label': 'Open', 'cta_url': '  https://thetradingtitans.com/app/plans  '}),
        'Open',
      );
    });

    test('a known route wins even when the url is unusable', () {
      // Older clients fall back to cta_url; newer ones prefer the route. A bad
      // url must not disable a perfectly good in-app destination.
      expect(
        ctaLabel({'cta_label': 'Open', 'cta_route': 'plans', 'cta_url': 'tel:123'}),
        'Open',
      );
    });

    test('trade and notifications are routable', () {
      // Both were missing, which is why an admin who wanted a "Trade" button had
      // to build it on the `plans` destination — and `plans` opens the paywall.
      for (final r in ['trade', 'notifications']) {
        expect(ctaLabel({'cta_label': 'Open', 'cta_route': r}), 'Open',
            reason: 'route $r should be accepted');
      }
    });
  });

  group('instrumentSymbolFor', () {
    test('an order notification with a symbol opens that instrument', () {
      expect(instrumentSymbolFor('order', {'symbol': 'RELIANCE'}), 'RELIANCE');
      expect(
        instrumentSymbolFor('order_pending', {'symbol': 'TCS', 'market': 'stock'}),
        'TCS',
      );
    });

    test('the pending-expiry payload falls back to the sheet', () {
      // THE REGRESSION THIS GUARDS. notify_pending_orders_expiring_soon() writes
      // action_type 'order' with jsonb_build_object('view','orders') and no
      // symbol. The old inline check saw a non-null action_data, took the
      // instrument branch, found no symbol and then did nothing at all — the
      // notification could not be opened. Null here means "show the sheet".
      expect(instrumentSymbolFor('order', {'view': 'orders'}), isNull);
    });

    test('a missing, empty or blank symbol is not an instrument', () {
      expect(instrumentSymbolFor('order', {}), isNull);
      expect(instrumentSymbolFor('order', null), isNull);
      expect(instrumentSymbolFor('order', {'symbol': ''}), isNull);
      expect(instrumentSymbolFor('order', {'symbol': '   '}), isNull);
    });

    test('surrounding whitespace is trimmed off a real symbol', () {
      expect(instrumentSymbolFor('order', {'symbol': '  INFY '}), 'INFY');
    });

    test('a price alert opens its instrument (the user set it, not a campaign)', () {
      expect(instrumentSymbolFor('price_alert', {'symbol': 'RELIANCE', 'market': 'stock'}), 'RELIANCE');
    });

    test('only order and price-alert types open an instrument', () {
      // A broadcast that happens to carry a symbol must still open the sheet,
      // otherwise an admin campaign would silently navigate people away from the
      // message they were trying to read.
      for (final t in ['broadcast', 'custom', 'reward', null, '']) {
        expect(instrumentSymbolFor(t, {'symbol': 'RELIANCE'}), isNull,
            reason: 'action_type $t must not hijack the tap');
      }
    });
  });

  group('push tap payload', () {
    // The push-notification edge function forwards cta_route / cta_url / symbol /
    // market into the FCM `data` map under those exact names, so the tap handler
    // can pass the map straight to the same allow-list the in-app button uses.
    // Nothing enforces that agreement at compile time across the TS/Dart
    // boundary, so it is pinned here.

    test('an FCM data map is already a usable action_data map', () {
      final pushData = parseActionData({
        'type': 'broadcast',
        'cta_route': 'trade',
        'cta_url': 'https://thetradingtitans.com/app',
      });
      expect(pushData, isNotNull);
      expect(kNotificationCtaRoutes, contains(pushData!['cta_route']));
    });

    test('a local-notification payload string decodes to the same map', () {
      // The foreground path stores the FCM data as JSON on the local notification
      // and gets it back as a string when the user taps it.
      expect(
        parseActionData('{"type":"broadcast","cta_route":"wallet"}'),
        {'type': 'broadcast', 'cta_route': 'wallet'},
      );
    });

    test('a push carrying no route still yields something to fall back on', () {
      // Most notifications have no CTA at all. The handler opens the list in that
      // case, so null here must not be an error — just an absent route.
      final pushData = parseActionData({'type': 'order_executed'});
      expect(pushData, isNotNull);
      expect(pushData!['cta_route'], isNull);
    });

    test('every admin destination still routes after the push round trip', () {
      // The in-app button and the tray tap share one allow-list. If they diverge,
      // the button works and the tap silently falls back to the list instead.
      for (final dest in kAdminCtaDestinations.keys
          .where((k) => k.isNotEmpty && !k.startsWith('_'))) {
        final data = parseActionData('{"cta_route":"$dest"}');
        expect(kNotificationCtaRoutes, contains(data!['cta_route']),
            reason: '$dest would not route from a push tap');
      }
    });

    test('a forwarded symbol still identifies an instrument', () {
      expect(instrumentSymbolFor('order', parseActionData({'symbol': 'RELIANCE'})),
          'RELIANCE');
    });
  });

  test('every admin destination is a route the app can actually open', () {
    // The guard for the "Trade button opens the top-up page" bug. The admin
    // dropdown and the client allow-list are two separate lists that must agree;
    // when they do not, the composer offers a destination that renders no button
    // at all, so whoever wrote the campaign reaches for a route that does exist
    // and picks the wrong one.
    final offered = kAdminCtaDestinations.keys
        .where((k) => k.isNotEmpty && !k.startsWith('_'))
        .toSet();
    expect(
      offered.difference(kNotificationCtaRoutes),
      isEmpty,
      reason: 'admin can pick these but the app cannot route them',
    );
  });
}
