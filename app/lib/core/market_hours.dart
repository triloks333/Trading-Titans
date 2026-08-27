/// Trading session windows for each market the app supports.
///
/// India: 09:15-15:30 IST, Mon-Fri.
/// US:    09:30-16:00 US Eastern, Mon-Fri, which lands overnight in India and
///        shifts by an hour when US daylight saving flips.
/// Crypto: always open.
class MarketHours {
  /// Market key used for US equities on `orders.market` / `holdings.market`.
  static const String usStock = 'us_stock';

  static DateTime _ist([DateTime? at]) =>
      (at ?? DateTime.now()).toUtc().add(const Duration(hours: 5, minutes: 30));

  // ── US Eastern ─────────────────────────────────────────────────────────────

  /// UTC instant of the `n`th `weekday` of a month, at `utcHour`.
  static DateTime _nthWeekdayUtc(int year, int month, int weekday, int n, int utcHour) {
    final first = DateTime.utc(year, month, 1, utcHour);
    // DateTime.weekday is 1=Mon..7=Sun; callers pass 7 for Sunday.
    final offset = (weekday - first.weekday + 7) % 7;
    return DateTime.utc(year, month, 1 + offset + (n - 1) * 7, utcHour);
  }

  /// True when US Eastern is on daylight saving (EDT, UTC-4).
  ///
  /// Rule since 2007: 02:00 local on the second Sunday of March (07:00 UTC,
  /// still EST) through 02:00 local on the first Sunday of November (06:00 UTC,
  /// still EDT).
  static bool isUsDst([DateTime? at]) {
    final utc = (at ?? DateTime.now()).toUtc();
    final start = _nthWeekdayUtc(utc.year, 3, DateTime.sunday, 2, 7);
    final end = _nthWeekdayUtc(utc.year, 11, DateTime.sunday, 1, 6);
    return !utc.isBefore(start) && utc.isBefore(end);
  }

  /// US Eastern wall-clock time, as a DateTime whose fields read as ET.
  static DateTime usEastern([DateTime? at]) {
    final utc = (at ?? DateTime.now()).toUtc();
    return utc.subtract(Duration(hours: isUsDst(utc) ? 4 : 5));
  }

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Whether the given market is currently accepting fills.
  ///
  /// ponytail: weekends only, no exchange holiday calendar for either market.
  /// On Diwali or Thanksgiving this reports open and a market order fills at the
  /// last published price. Upgrade path: a `market_holidays` table checked here
  /// and in the matching edge-function helpers.
  static bool isOpen(String market, {DateTime? at}) {
    if (market == 'crypto') return true;

    if (market == usStock) {
      final et = usEastern(at);
      if (et.weekday == DateTime.saturday || et.weekday == DateTime.sunday) return false;
      final minutes = et.hour * 60 + et.minute;
      return minutes >= 9 * 60 + 30 && minutes < 16 * 60;
    }

    final now = _ist(at);
    if (now.weekday == DateTime.saturday || now.weekday == DateTime.sunday) return false;
    final minutes = now.hour * 60 + now.minute;
    // 555 = 09:15, 930 = 15:30. This read `< 915` (15:15) and so closed the
    // session a quarter of an hour early, disagreeing with both `sessionLabel`
    // below and the market-status endpoint, which have always said 3:30 PM.
    // The server-side copies are fixed in _shared/market_hours.ts.
    return minutes >= 555 && minutes < 930;
  }

  static String statusText(String market, {DateTime? at}) {
    if (market == 'crypto') return '24/7 Market';
    if (isOpen(market, at: at)) return 'Market Open';

    if (market == usStock) {
      final et = usEastern(at);
      if (et.weekday == DateTime.saturday || et.weekday == DateTime.sunday) {
        return 'Weekend Closed';
      }
      return 'Opens at ${_usOpenIst(at)} IST';
    }

    final now = _ist(at);
    if (now.weekday == DateTime.saturday || now.weekday == DateTime.sunday) {
      return 'Weekend Closed';
    }
    return 'Opens at 9:15 AM IST';
  }

  static String nextOpen(String market, {DateTime? at}) {
    if (market == 'crypto' || isOpen(market, at: at)) return '';

    if (market == usStock) {
      final et = usEastern(at);
      final open = _usOpenIst(at);
      if (et.weekday == DateTime.saturday || et.weekday == DateTime.sunday) {
        return 'Opens Monday $open IST';
      }
      return 'Opens at $open IST';
    }

    final now = _ist(at);
    if (now.weekday == DateTime.saturday || now.weekday == DateTime.sunday) {
      return 'Opens Monday 9:15 AM IST';
    }
    return 'Opens at 9:15 AM IST';
  }

  /// The US open expressed in IST: 7:00 PM under EDT, 8:00 PM under EST.
  static String _usOpenIst([DateTime? at]) => isUsDst(at) ? '7:00 PM' : '8:00 PM';

  // ── IST calendar days ──────────────────────────────────────────────────────

  /// The IST calendar day containing [at] (default now), as a UTC-midnight
  /// `DateTime` used purely as a date key.
  ///
  /// IST is the app's canonical day even for US stocks and crypto: the wallet is
  /// a single INR balance, and the backend already books day-scoped things
  /// (`green_day`, login streaks) `AT TIME ZONE 'Asia/Kolkata'`. Keying off the
  /// device timezone instead would let a phone abroad disagree with the server
  /// about which day a fill belongs to.
  static DateTime istDate([DateTime? at]) {
    final ist = _ist(at);
    return DateTime.utc(ist.year, ist.month, ist.day);
  }

  /// Half-open UTC range `[start, end)` spanning the IST calendar day [date].
  ///
  /// [date] is a key from [istDate]; only its year/month/day are read. Suitable
  /// for filtering a UTC `created_at` column: IST midnight is 18:30 UTC the
  /// previous day, so the range is offset, not aligned to a UTC day.
  static ({DateTime start, DateTime end}) istDayRangeUtc(DateTime date) {
    final start = DateTime.utc(date.year, date.month, date.day)
        .subtract(const Duration(hours: 5, minutes: 30));
    return (start: start, end: start.add(const Duration(days: 1)));
  }

  /// Session window label for a market, for headers and tooltips.
  static String sessionLabel(String market, {DateTime? at}) {
    if (market == 'crypto') return '24/7';
    if (market == usStock) {
      return isUsDst(at) ? '7:00 PM - 1:30 AM IST' : '8:00 PM - 2:30 AM IST';
    }
    return '9:15 AM - 3:30 PM IST';
  }
}
