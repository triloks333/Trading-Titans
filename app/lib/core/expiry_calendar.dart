import 'market_hours.dart';

/// Indian F&O expiry calendar: the FALLBACK rule for when the exchange contract
/// list (the `instruments` table, synced daily from the Fyers NSE/BSE masters)
/// has nothing for a symbol. The contract list is the source of truth.
///
/// Rules in force since 1 Sep 2025:
///  * NSE monthly contracts (index and stock, options and futures) expire on the
///    LAST TUESDAY; NIFTY is the only NSE index with weeklies (every Tuesday).
///  * BSE monthly contracts expire on the LAST THURSDAY; SENSEX has weeklies
///    every Thursday.
///  * An expiry that falls on a trading holiday moves to the PREVIOUS trading
///    day (24 Nov 2026 Guru Nanak Jayanti -> Mon 23 Nov 2026).
///
/// The app used to hard-code "last Thursday", wrong for NSE since Sep 2025.
/// Mirror of supabase/functions/_shared/expiry_calendar.ts; keep them in step.
class ExpiryCalendar {
  ExpiryCalendar._();

  /// Exchange holidays on the same date every year, for years whose list is
  /// not loaded yet (e.g. 26 Jan 2027).
  static const _fixedHolidaysMmDd = {
    '01-26',
    '05-01',
    '08-15',
    '10-02',
    '12-25',
  };

  static String isoDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static bool isTradingDay(DateTime day, {Set<String>? holidays}) {
    if (day.weekday == DateTime.saturday || day.weekday == DateTime.sunday) {
      return false;
    }
    final key = isoDate(day);
    if ((holidays ?? MarketHours.indianHolidays).contains(key)) return false;
    return !_fixedHolidaysMmDd.contains(key.substring(5));
  }

  /// [day] itself when it is a trading day, else the closest earlier one.
  static DateTime rollBack(DateTime day, {Set<String>? holidays}) {
    var d = DateTime.utc(day.year, day.month, day.day);
    for (var i = 0; i < 10; i++) {
      if (isTradingDay(d, holidays: holidays)) return d;
      d = d.subtract(const Duration(days: 1));
    }
    return DateTime.utc(day.year, day.month, day.day);
  }

  static String _clean(String underlying) =>
      underlying.toUpperCase().replaceFirst(RegExp(r'^(NSE:|BSE:)'), '');

  static bool isBse(String underlying) {
    final u = _clean(underlying);
    return u == 'SENSEX' || u == 'BANKEX' || u == 'SENSEX50' || u == '^BSESN';
  }

  /// Only NIFTY (NSE, Tuesday) and SENSEX (BSE, Thursday) list weekly options.
  static bool hasWeeklyOptions(String underlying) {
    final u = _clean(underlying);
    return u == 'NIFTY' ||
        u == 'NIFTY50' ||
        u == '^NSEI' ||
        u == 'SENSEX' ||
        u == '^BSESN';
  }

  /// Monthly expiry for [month] (1-12) of [year] on [underlying]'s exchange.
  static DateTime monthlyExpiry(
    int year,
    int month, {
    String underlying = '',
    Set<String>? holidays,
  }) {
    final target = isBse(underlying) ? DateTime.thursday : DateTime.tuesday;
    final last = DateTime.utc(year, month + 1, 0);
    final diff = (last.weekday - target + 7) % 7;
    return rollBack(last.subtract(Duration(days: diff)), holidays: holidays);
  }

  /// IST calendar date of [now], and whether its 15:30 close has passed.
  static (DateTime, bool) _istToday(DateTime now) {
    final ist = now.toUtc().add(const Duration(hours: 5, minutes: 30));
    return (
      DateTime.utc(ist.year, ist.month, ist.day),
      ist.hour * 60 + ist.minute >= 930,
    );
  }

  static bool _isLive(DateTime expiry, DateTime now) {
    final (today, afterClose) = _istToday(now);
    return expiry.isAfter(today) || (expiry == today && !afterClose);
  }

  /// Next [count] monthly expiries that have not expired yet.
  static List<DateTime> upcomingMonthly(
    String underlying, {
    int count = 3,
    DateTime? now,
    Set<String>? holidays,
  }) {
    final at = now ?? DateTime.now();
    final (today, _) = _istToday(at);
    final out = <DateTime>[];
    for (var i = 0; out.length < count && i < 24; i++) {
      final e = monthlyExpiry(
        today.year,
        today.month + i,
        underlying: underlying,
        holidays: holidays,
      );
      if (_isLive(e, at)) out.add(e);
    }
    return out;
  }
}
