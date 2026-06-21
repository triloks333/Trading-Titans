// Sanity tests for centralized constants. These don't test behavior so much as
// lock the agreed values so an accidental edit (e.g. fnoMarginPct typo) is
// caught immediately, since these feed money math and polling cadence.

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/app_constants.dart';

void main() {
  group('AppConstants margins', () {
    test('F&O margin is 15% of notional', () {
      expect(AppConstants.fnoMarginPct, 0.15);
    });

    test('equity blocks full notional (no leverage)', () {
      expect(AppConstants.equityMarginPct, 1.0);
    });

    test('margins are within a sane 0..1 range', () {
      expect(AppConstants.fnoMarginPct, greaterThan(0));
      expect(AppConstants.fnoMarginPct, lessThanOrEqualTo(1));
      expect(AppConstants.equityMarginPct, greaterThan(0));
      expect(AppConstants.equityMarginPct, lessThanOrEqualTo(1));
    });
  });

  group('AppConstants auth', () {
    test('guest email domain is the expected sentinel', () {
      expect(AppConstants.guestEmailDomain, '@guest.tradingtitans');
      expect(AppConstants.guestEmailDomain.startsWith('@'), isTrue);
    });
  });

  group('AppConstants durations are positive', () {
    test('cache TTLs', () {
      expect(AppConstants.quoteClientMemoTtl, greaterThan(Duration.zero));
      expect(AppConstants.quoteServerCacheTtl, greaterThan(Duration.zero));
    });

    test('polling intervals', () {
      expect(AppConstants.dashboardPricePoll, greaterThan(Duration.zero));
      expect(AppConstants.portfolioPoll, greaterThan(Duration.zero));
      expect(AppConstants.rewardCheckPoll, greaterThan(Duration.zero));
    });

    test('server cache is fresher-bound than client memo is short', () {
      // client memo should be shorter than the server cache window
      expect(AppConstants.quoteClientMemoTtl,
          lessThan(AppConstants.quoteServerCacheTtl));
    });
  });
}
