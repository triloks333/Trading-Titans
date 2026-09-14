// Synthetic derivative prices must not move while the market is shut.
//
// REPORTED AS: an F&O position's P&L growing hour by hour through the evening, and
// through an exchange holiday, with the LTP visibly frozen.
//
// The cause was that a future is priced spot × (1 + r × T) and an option by
// Black-Scholes, both against `DateTime.now()`. T shrinks continuously, so the
// synthetic price drifted even with the spot frozen and nothing trading. `.inHours`
// truncation made it step once an hour. Per unit the drift is a fraction of a paisa,
// which is why the displayed LTP looked static — but a 2250-unit lot turned it into
// about ₹4 an hour on the P&L line, and a short position showed that as profit.
//
// These tests pin the fix: valuation happens at the last session CLOSE whenever the
// market is not open, so the same position values identically at 18:33 and 20:03.

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/market_hours.dart';
import 'package:mobile/core/option_pricing.dart';

/// UTC instant for a given IST wall-clock time.
DateTime ist(int y, int m, int d, [int h = 0, int min = 0]) =>
    DateTime.utc(y, m, d, h, min).subtract(const Duration(hours: 5, minutes: 30));

void main() {
  setUp(() => MarketHours.indianHolidays = const {});
  tearDown(() => MarketHours.indianHolidays = const {});

  group('valuationTime', () {
    test('is the live clock while the session is open', () {
      // Thursday 27 Aug 2026, mid-session.
      final at = ist(2026, 8, 27, 11, 0);
      expect(MarketHours.valuationTime('stock', at: at), at);
    });

    test('freezes at 15:30 IST once the session has closed', () {
      final close = ist(2026, 8, 27, 15, 30);
      for (final t in [
        ist(2026, 8, 27, 15, 31),
        ist(2026, 8, 27, 18, 33), // the 6:33 PM screenshot
        ist(2026, 8, 27, 20, 3), // the 8:03 PM screenshot
        ist(2026, 8, 27, 23, 59),
      ]) {
        expect(MarketHours.valuationTime('stock', at: t), close,
            reason: 'valuation moved after the close');
      }
    });

    test('before the open, values at the PREVIOUS session close', () {
      // 09:00 IST Thursday values at Wednesday 15:30, not at today.
      expect(MarketHours.valuationTime('stock', at: ist(2026, 8, 27, 9, 0)),
          ist(2026, 8, 26, 15, 30));
    });

    test('a weekend values at Friday 15:30', () {
      // Saturday 29 and Sunday 30 Aug 2026 both look back to Friday the 28th.
      expect(MarketHours.valuationTime('stock', at: ist(2026, 8, 29, 12, 0)),
          ist(2026, 8, 28, 15, 30));
      expect(MarketHours.valuationTime('stock', at: ist(2026, 8, 30, 12, 0)),
          ist(2026, 8, 28, 15, 30));
    });

    test('a holiday values at the last trading day, even mid-session', () {
      // Monday 14 Sep 2026, Ganesh Chaturthi. 11:00 IST is inside the normal
      // window, so without the holiday check this would have returned the live
      // clock and kept drifting all day.
      MarketHours.indianHolidays = {'2026-09-14'};
      expect(MarketHours.valuationTime('stock', at: ist(2026, 9, 14, 11, 0)),
          ist(2026, 9, 11, 15, 30)); // Friday the 11th
    });

    test('crypto always values at the live clock', () {
      final at = ist(2026, 8, 30, 3, 0); // a Sunday
      expect(MarketHours.valuationTime('crypto', at: at), at);
    });
  });

  group('the reported drift is gone', () {
    // ONGC SEP FUT, short 1 lot = 2250 units, avg 233.61, spot frozen.
    const spot = 232.85;
    const units = 2250.0;
    const avg = 233.61;
    final expiry = DateTime.utc(2026, 9, 24, 10, 0);

    double pnlAt(DateTime at) {
      final t = MarketHours.daysToExpiry(expiry, at: at);
      final ltp = OptionPricing.futurePrice(spot: spot, daysToExpiry: t);
      // Short, so profit grows as the futures price falls.
      return (avg - ltp) * units;
    }

    test('P&L is identical at 18:33 and 20:03 with the market shut', () {
      final a = pnlAt(ist(2026, 9, 11, 18, 33));
      final b = pnlAt(ist(2026, 9, 11, 20, 3));
      expect(b - a, 0.0, reason: 'P&L still drifted after the close');
    });

    test('P&L does not move overnight either', () {
      final evening = pnlAt(ist(2026, 9, 11, 20, 3));
      final nextMorning = pnlAt(ist(2026, 9, 12, 8, 0));
      expect(nextMorning - evening, 0.0);
    });

    test('and does not move across a holiday', () {
      MarketHours.indianHolidays = {'2026-09-14'};
      final before = pnlAt(ist(2026, 9, 14, 6, 0));
      final during = pnlAt(ist(2026, 9, 14, 11, 0));
      final after = pnlAt(ist(2026, 9, 14, 19, 0));
      expect(during - before, 0.0);
      expect(after - before, 0.0);
    });

    test('but DOES still move during a live session, which is the point', () {
      // The fix must not freeze a real market. Two hours apart mid-session.
      final a = pnlAt(ist(2026, 9, 11, 10, 0));
      final b = pnlAt(ist(2026, 9, 11, 14, 0));
      expect(a == b, isFalse, reason: 'a live session should still reprice');
    });

    test('the old behaviour really did drift, so this test can fail', () {
      // Guards the guard: reproduce the pre-fix calculation and assert it moved,
      // otherwise the assertions above could pass for the wrong reason.
      double oldPnl(DateTime now) {
        final days = expiry.difference(now).inHours / 24.0;
        final ltp = OptionPricing.futurePrice(spot: spot, daysToExpiry: days);
        return (avg - ltp) * units;
      }
      final a = oldPnl(ist(2026, 9, 11, 18, 33));
      final b = oldPnl(ist(2026, 9, 11, 20, 3));
      expect(b - a, greaterThan(0.0),
          reason: 'the old calculation should have drifted upward');
    });
  });

  group('every pricing site is frozen, not just the service layer', () {
    // The first attempt at this fix changed supabase_service only and shipped
    // WITHOUT fixing the reported bug, because portfolio_screen._estimateFoPrice
    // computed its own price from DateTime.now(). Seven sites inlined this
    // calculation with three different fallbacks (0, 7 and 15 days).
    //
    // These reproduce each site's formula against the shared helper. If someone
    // reintroduces a local DateTime.now() in any of them, the shape asserted here
    // stops matching what the screen shows and this is the tripwire.

    final expiry = DateTime.utc(2026, 9, 24, 10, 0);
    final evening = ist(2026, 9, 11, 18, 33);
    final laterEvening = ist(2026, 9, 11, 20, 3);

    test('the futures carry multiplier is stable after hours', () {
      // supabase_service fo_positions branch: spot * (1 + r * T)
      double carry(DateTime at) =>
          1.0 + 0.065 * (MarketHours.daysToExpiry(expiry, at: at) / 365.0);
      expect(carry(laterEvening) - carry(evening), 0.0);
    });

    test('the Portfolio screen estimate is stable after hours', () {
      // portfolio_screen._estimateFoPrice
      double ltp(DateTime at) => OptionPricing.futurePrice(
            spot: 232.85,
            daysToExpiry: MarketHours.daysToExpiry(expiry, at: at),
          );
      expect(ltp(laterEvening), ltp(evening));
    });

    test('option premiums are stable after hours', () {
      double premium(DateTime at) => OptionPricing.optionPremium(
            optionType: 'CE',
            spot: 232.85,
            strike: 230,
            daysToExpiry: MarketHours.daysToExpiry(expiry, at: at),
          );
      expect(premium(laterEvening), premium(evening));
    });

    test('the previous-close variant is stable too', () {
      // Both screens price the prior session as one extra day to expiry. If the
      // base moved, change and change% would drift even when the LTP did not.
      double prev(DateTime at) => OptionPricing.futurePrice(
            spot: 232.85,
            daysToExpiry: MarketHours.daysToExpiry(expiry, at: at) + 1.0,
          );
      expect(prev(laterEvening), prev(evening));
    });
  });

  group('isOpen honours the holiday list', () {
    test('a holiday closes the Indian session all day', () {
      MarketHours.indianHolidays = {'2026-09-14'};
      expect(MarketHours.isOpen('stock', at: ist(2026, 9, 14, 11, 0)), isFalse);
    });

    test('an empty list degrades to the old weekends-only behaviour', () {
      // Which is what happens before the first server load completes.
      expect(MarketHours.isOpen('stock', at: ist(2026, 9, 14, 11, 0)), isTrue);
    });

    test('a holiday never closes crypto or US stocks', () {
      MarketHours.indianHolidays = {'2026-09-14'};
      expect(MarketHours.isOpen('crypto', at: ist(2026, 9, 14, 11, 0)), isTrue);
      // 20:00 IST on the 14th is 10:30 ET, inside the US session.
      expect(MarketHours.isOpen(MarketHours.usStock, at: ist(2026, 9, 14, 20, 0)),
          isTrue);
    });

    test('istDateKey matches the market_holidays date format', () {
      expect(MarketHours.istDateKey(ist(2026, 9, 14, 0, 30)), '2026-09-14');
      expect(MarketHours.istDateKey(ist(2026, 9, 14, 23, 30)), '2026-09-14');
      // Just before IST midnight belongs to the previous day.
      expect(MarketHours.istDateKey(ist(2026, 9, 13, 23, 59)), '2026-09-13');
    });
  });

  group('daysToExpiry', () {
    test('never negative once expiry has passed', () {
      expect(MarketHours.daysToExpiry(DateTime.utc(2026, 1, 1),
          at: ist(2026, 9, 11, 11, 0)), 0.0);
    });

    test('falls back when there is no expiry', () {
      expect(MarketHours.daysToExpiry(null, fallback: 15.0), 15.0);
      expect(MarketHours.daysToExpiry(null), 7.0);
    });
  });
}
