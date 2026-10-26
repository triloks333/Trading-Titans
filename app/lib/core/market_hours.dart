/// Trading session windows for each market the app supports.
///
/// India: 09:15-15:30 IST, Mon-Fri.
/// US:    09:30-16:00 US Eastern, Mon-Fri, which lands overnight in India and
///        shifts by an hour when US daylight saving flips.
/// Crypto: always open.
class MarketHours {
  /// Market key used for Indian equities / F&O on `orders.market`.
  static const String stock = 'stock';

  /// Market key used for US equities on `orders.market` / `holdings.market`.
  static const String usStock = 'us_stock';

  /// Market key used for Pakistan Stock Exchange (PSX).
  static const String pakistanStock = 'pakistan_stock';

  /// Market key used for Borsa Italiana (Milan).
  static const String italyStock = 'italy_stock';

  /// Market key used for Cryptocurrencies.
  static const String crypto = 'crypto';

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

  // ── Exchange holidays ──────────────────────────────────────────────────────

  /// IST calendar days (YYYY-MM-DD) on which NSE and BSE do not trade.
  ///
  /// Loaded from the `market_holidays` table on each foreground, so a holiday can
  /// be added server-side with no app release. Empty until that first load
  /// completes, which degrades to the old weekends-only behaviour rather than
  /// guessing a calendar.
  ///
  /// Built-in known exchange holidays for 2026 as a guaranteed baseline
  /// before the first server load finishes or during offline launches.
  static const Set<String> defaultIndianHolidays = {
    '2026-01-26', // Republic Day
    '2026-03-03', // Holi
    '2026-03-26', // Shri Ram Navami
    '2026-03-31', // Shri Mahavir Jayanti
    '2026-04-03', // Good Friday
    '2026-04-14', // Dr. Ambedkar Jayanti
    '2026-05-01', // Maharashtra Day
    '2026-05-28', // Bakri Id
    '2026-06-26', // Muharram
    '2026-09-14', // Ganesh Chaturthi
    '2026-10-02', // Mahatma Gandhi Jayanti
    '2026-10-20', // Dussehra (Vijayadashami)
    '2026-11-10', // Diwali-Balipratipada
    '2026-11-24', // Guru Nanak Jayanti
    '2026-12-25', // Christmas
  };

  /// Indian equities and F&O only. Crypto never closes and US equities have their
  /// own window, so nothing here can shut either of them.
  static Set<String> indianHolidays = Set<String>.from(defaultIndianHolidays);

  /// The IST calendar day of [at] as a YYYY-MM-DD key, matching the
  /// `market_holidays.holiday_date` column.
  static String istDateKey([DateTime? at]) {
    final ist = _ist(at);
    final m = ist.month.toString().padLeft(2, '0');
    final d = ist.day.toString().padLeft(2, '0');
    return '${ist.year}-$m-$d';
  }

  static bool isIndianHoliday([DateTime? at]) =>
      indianHolidays.contains(istDateKey(at));

  /// Whether the given market is currently accepting fills.
  static bool isOpen(String market, {DateTime? at}) {
    if (market == 'crypto') return true;

    if (market == usStock) {
      final et = usEastern(at);
      if (et.weekday == DateTime.saturday || et.weekday == DateTime.sunday) return false;
      final minutes = et.hour * 60 + et.minute;
      return minutes >= 9 * 60 + 30 && minutes < 16 * 60;
    }

    if (market == pakistanStock) {
      // PKT is UTC+5
      final pkt = (at ?? DateTime.now()).toUtc().add(const Duration(hours: 5));
      if (pkt.weekday == DateTime.saturday || pkt.weekday == DateTime.sunday) return false;
      final minutes = pkt.hour * 60 + pkt.minute;
      return minutes >= 555 && minutes < 930; // 09:15 - 15:30 PKT
    }

    if (market == italyStock) {
      // CET is UTC+1 (or UTC+2 DST)
      final cet = (at ?? DateTime.now()).toUtc().add(Duration(hours: isUsDst(at) ? 2 : 1));
      if (cet.weekday == DateTime.saturday || cet.weekday == DateTime.sunday) return false;
      final minutes = cet.hour * 60 + cet.minute;
      return minutes >= 540 && minutes < 1050; // 09:00 - 17:30 CET
    }

    final now = _ist(at);
    if (now.weekday == DateTime.saturday || now.weekday == DateTime.sunday) return false;
    if (isIndianHoliday(at)) return false;
    final minutes = now.hour * 60 + now.minute;
    return minutes >= 555 && minutes < 930;
  }

  /// The instant a market's prices should be valued at.
  ///
  /// Now while the session is open; the most recent session CLOSE once it is not.
  ///
  /// THE BUG THIS FIXES. Derivative prices in this app are synthetic — a future is
  /// spot plus cost of carry, an option is Black-Scholes — and both depend on time
  /// to expiry. Valuing them against a live clock meant every F&O position's P&L
  /// kept moving overnight, at weekends and on exchange holidays, with no trade and
  /// no price change behind it. `.inHours` truncation made it step once an hour, so
  /// a short 2250-unit ONGC lot gained about ₹4 every hour while the market was
  /// shut. The LTP looked frozen because the per-unit drift is a fraction of a
  /// paisa; multiplied by the lot size it became rupees on the P&L line.
  ///
  /// Crypto genuinely trades around the clock, so this is always now for it.
  static DateTime valuationTime(String market, {DateTime? at}) {
    final now = at ?? DateTime.now();
    if (market == 'crypto' || isOpen(market, at: now)) return now;
    return market == usStock ? _lastUsClose(now) : _lastIndianClose(now);
  }

  /// 15:30 IST on the most recent Indian trading day at or before [now].
  static DateTime _lastIndianClose(DateTime now) {
    final ist = _ist(now);
    // Start from today's close, then step back a day at a time until the day both
    // is a weekday and is not a holiday. Bounded at 10 days so a mis-seeded
    // holiday list can never spin.
    var day = DateTime.utc(ist.year, ist.month, ist.day, 15, 30);
    if (ist.isBefore(day)) day = day.subtract(const Duration(days: 1));
    for (var i = 0; i < 10; i++) {
      final asUtc = day.subtract(const Duration(hours: 5, minutes: 30));
      final isWeekend =
          day.weekday == DateTime.saturday || day.weekday == DateTime.sunday;
      if (!isWeekend && !isIndianHoliday(asUtc)) return asUtc;
      day = day.subtract(const Duration(days: 1));
    }
    return day.subtract(const Duration(hours: 5, minutes: 30));
  }

  /// 16:00 US Eastern on the most recent US trading day at or before [now].
  static DateTime _lastUsClose(DateTime now) {
    final et = usEastern(now);
    var day = DateTime.utc(et.year, et.month, et.day, 16);
    if (et.isBefore(day)) day = day.subtract(const Duration(days: 1));
    for (var i = 0; i < 10; i++) {
      if (day.weekday != DateTime.saturday && day.weekday != DateTime.sunday) {
        // usEastern() shifts UTC -> ET, so invert it to get back to UTC.
        return day.add(Duration(hours: isUsDst(now) ? 4 : 5));
      }
      day = day.subtract(const Duration(days: 1));
    }
    return day;
  }

  /// Days from [market]'s valuation time until [expiry], for the synthetic
  /// derivative pricers. Never negative.
  ///
  /// One helper because this calculation was inlined in SEVEN places across the
  /// service layer, the Portfolio screen and the option-chain builder, with three
  /// different fallbacks for a missing expiry (0, 7 and 15 days). Fixing only the
  /// service layer left the Portfolio tab still drifting, because that screen
  /// computed its own price — which is exactly how the first attempt at this fix
  /// shipped without fixing the reported bug.
  static double daysToExpiry(
    DateTime? expiry, {
    String market = 'stock',
    double fallback = 7.0,
    DateTime? at,
  }) {
    if (expiry == null) return fallback;
    DateTime targetExpiry = expiry;
    if (expiry.hour == 0 && expiry.minute == 0) {
      if (market == usStock) {
        final isDst = isUsDst(expiry);
        targetExpiry = DateTime.utc(expiry.year, expiry.month, expiry.day, isDst ? 20 : 21, 0);
      } else {
        // Indian close is 15:30 IST = 10:00 UTC
        targetExpiry = DateTime.utc(expiry.year, expiry.month, expiry.day, 10, 0);
      }
    }
    final from = valuationTime(market, at: at);
    final days = targetExpiry.difference(from).inMinutes / 1440.0;
    return days <= 0 ? 0.0 : days;
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

    if (market == pakistanStock) {
      final pkt = (at ?? DateTime.now()).toUtc().add(const Duration(hours: 5));
      if (pkt.weekday == DateTime.saturday || pkt.weekday == DateTime.sunday) {
        return 'Weekend Closed';
      }
      return 'Opens at 9:15 AM PKT';
    }

    if (market == italyStock) {
      final cet = (at ?? DateTime.now()).toUtc().add(Duration(hours: isUsDst(at) ? 2 : 1));
      if (cet.weekday == DateTime.saturday || cet.weekday == DateTime.sunday) {
        return 'Weekend Closed';
      }
      return 'Opens at 9:00 AM CET';
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

    if (market == pakistanStock) {
      return 'Opens at 9:15 AM PKT';
    }

    if (market == italyStock) {
      return 'Opens at 9:00 AM CET';
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
