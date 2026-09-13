// The call-to-action on a broadcast notification.
//
// These rows are written server-side and then handed to the platform launcher, so
// `ctaLabel` is a trust boundary rather than a formatting helper: it decides both
// whether a button appears and whether a URL is allowed to leave the app. A label
// with no destination is a dead button; a destination with the wrong scheme is a
// way to make the app open something it should not.

import 'package:flutter_test/flutter_test.dart';
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
  });
}
