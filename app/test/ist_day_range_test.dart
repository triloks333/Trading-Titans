// IST calendar-day keys and the UTC ranges the orders screen filters on.
//
// This is the quiet kind of bug: IST midnight is 18:30 UTC the *previous* day,
// so an off-by-5:30 range still returns plausible-looking orders while filing
// evening trades under the wrong day. Every case below is a real boundary.

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/market_hours.dart';

void main() {
  group('MarketHours.istDate', () {
    test('keys the IST day, not the UTC day, late in the IST evening', () {
      // 19 Aug 20:00 IST is still 19 Aug, though UTC has not reached it yet.
      expect(
        MarketHours.istDate(DateTime.utc(2026, 8, 19, 14, 30)),
        DateTime.utc(2026, 8, 19),
      );
    });

    test('rolls to the next IST day at 18:30 UTC', () {
      expect(
        MarketHours.istDate(DateTime.utc(2026, 8, 19, 18, 29)),
        DateTime.utc(2026, 8, 19),
      );
      // 18:30 UTC == 00:00 IST on the 20th.
      expect(
        MarketHours.istDate(DateTime.utc(2026, 8, 19, 18, 30)),
        DateTime.utc(2026, 8, 20),
      );
    });

    test('a UTC morning instant is still the same IST day', () {
      // 04:30 UTC == 10:00 IST, mid-session.
      expect(
        MarketHours.istDate(DateTime.utc(2026, 8, 19, 4, 30)),
        DateTime.utc(2026, 8, 19),
      );
    });

    test('crosses a month boundary correctly', () {
      // 31 Aug 19:00 UTC == 1 Sep 00:30 IST.
      expect(
        MarketHours.istDate(DateTime.utc(2026, 8, 31, 19)),
        DateTime.utc(2026, 9, 1),
      );
    });
  });

  group('MarketHours.istDayRangeUtc', () {
    test('starts at 18:30 UTC the previous day and spans 24h', () {
      final r = MarketHours.istDayRangeUtc(DateTime.utc(2026, 8, 19));
      expect(r.start, DateTime.utc(2026, 8, 18, 18, 30));
      expect(r.end, DateTime.utc(2026, 8, 19, 18, 30));
      expect(r.end.difference(r.start), const Duration(days: 1));
    });

    test('contains a 09:15 IST market-open fill', () {
      final r = MarketHours.istDayRangeUtc(DateTime.utc(2026, 8, 19));
      final openFill = DateTime.utc(2026, 8, 19, 3, 45); // 09:15 IST
      expect(openFill.isAfter(r.start), isTrue);
      expect(openFill.isBefore(r.end), isTrue);
    });

    test('contains a late-evening crypto fill on the same IST day', () {
      final r = MarketHours.istDayRangeUtc(DateTime.utc(2026, 8, 19));
      final cryptoFill = DateTime.utc(2026, 8, 19, 17, 30); // 23:00 IST
      expect(cryptoFill.isBefore(r.end), isTrue);
    });

    test('excludes a fill that has already rolled into the next IST day', () {
      final r = MarketHours.istDayRangeUtc(DateTime.utc(2026, 8, 19));
      final nextDay = DateTime.utc(2026, 8, 19, 19, 30); // 01:00 IST on the 20th
      expect(nextDay.isBefore(r.end), isFalse);
      // ...and it lands inside the following day's range instead.
      final next = MarketHours.istDayRangeUtc(DateTime.utc(2026, 8, 20));
      expect(nextDay.isAfter(next.start), isTrue);
      expect(nextDay.isBefore(next.end), isTrue);
    });

    test('consecutive days abut exactly, leaving no gap or overlap', () {
      final a = MarketHours.istDayRangeUtc(DateTime.utc(2026, 8, 19));
      final b = MarketHours.istDayRangeUtc(DateTime.utc(2026, 8, 20));
      expect(a.end, b.start);
    });

    test('handles a month boundary', () {
      final r = MarketHours.istDayRangeUtc(DateTime.utc(2026, 9, 1));
      expect(r.start, DateTime.utc(2026, 8, 31, 18, 30));
    });

    test('agrees with istDate for every instant across a day', () {
      // The two must be mutually consistent, or a day can show orders it does
      // not own. Walk 15-minute steps through one IST day plus its edges.
      var t = DateTime.utc(2026, 8, 18, 18, 0);
      final stop = DateTime.utc(2026, 8, 19, 19, 0);
      while (t.isBefore(stop)) {
        final key = MarketHours.istDate(t);
        final r = MarketHours.istDayRangeUtc(key);
        expect(t.isBefore(r.start), isFalse, reason: '$t before its own range');
        expect(t.isBefore(r.end), isTrue, reason: '$t not inside its own range');
        t = t.add(const Duration(minutes: 15));
      }
    });
  });

  _sessionWindowTests();
}

// ── Session window ──────────────────────────────────────────────────────────
//
// The NSE session is 09:15-15:30 IST, but this class closed it at 15:15. The
// window was duplicated in five places (here plus four edge functions) and four
// of them carried the wrong close, so the app showed "Market Open · 9:15 AM -
// 3:30 PM IST" -- from `sessionLabel` right below the bug -- while nothing could
// actually trade for the last quarter hour of every session.
//
// The server-side copies now share supabase/functions/_shared/market_hours.ts.
// This class is the remaining independent copy, so it gets its own guard: these
// cases fail if the close time ever drifts back.
void _sessionWindowTests() {
  group('MarketHours.isOpen — Indian session', () {
    /// 09:15 IST is 03:45 UTC, so build the instant from IST and subtract 5:30.
    DateTime ist(int y, int mo, int d, int h, int mi) =>
        DateTime.utc(y, mo, d, h, mi).subtract(const Duration(hours: 5, minutes: 30));

    test('stays open through the final quarter hour, to 15:30', () {
      // 2026-08-27 is a Thursday. This is the exact window that was dead.
      expect(MarketHours.isOpen('stock', at: ist(2026, 8, 27, 15, 15)), isTrue);
      expect(MarketHours.isOpen('stock', at: ist(2026, 8, 27, 15, 29)), isTrue);
    });

    test('open is inclusive, close is exclusive', () {
      expect(MarketHours.isOpen('stock', at: ist(2026, 8, 27, 9, 14)), isFalse);
      expect(MarketHours.isOpen('stock', at: ist(2026, 8, 27, 9, 15)), isTrue);
      expect(MarketHours.isOpen('stock', at: ist(2026, 8, 27, 15, 30)), isFalse);
    });

    test('closed at weekends', () {
      expect(MarketHours.isOpen('stock', at: ist(2026, 8, 29, 11, 0)), isFalse);
      expect(MarketHours.isOpen('stock', at: ist(2026, 8, 30, 11, 0)), isFalse);
    });

    test('the advertised label matches the window actually enforced', () {
      // These disagreed before: the label said 3:30 PM, isOpen() closed at 3:15.
      expect(MarketHours.sessionLabel('stock'), '9:15 AM - 3:30 PM IST');
      expect(MarketHours.isOpen('stock', at: ist(2026, 8, 27, 15, 29)), isTrue);
    });
  });
}
