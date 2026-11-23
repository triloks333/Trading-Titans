import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/expiry_calendar.dart';
import 'package:mobile/services/market_service.dart';

// Expected dates are the real exchange calendar (checked against the Fyers NSE
// contract master in `instruments` on 23 Nov 2026).
void main() {
  String iso(DateTime d) => ExpiryCalendar.isoDate(d);

  test('NSE monthly is the last Tuesday, moved back over holidays', () {
    expect(
      iso(ExpiryCalendar.monthlyExpiry(2026, 10, underlying: 'NIFTY')),
      '2026-10-27',
    );
    // Tue 24 Nov 2026 is Guru Nanak Jayanti.
    expect(
      iso(ExpiryCalendar.monthlyExpiry(2026, 11, underlying: 'RELIANCE')),
      '2026-11-23',
    );
    expect(
      iso(ExpiryCalendar.monthlyExpiry(2026, 12, underlying: 'NIFTY')),
      '2026-12-29',
    );
    // Tue 26 Jan 2027 is Republic Day.
    expect(
      iso(ExpiryCalendar.monthlyExpiry(2027, 1, underlying: 'BANKNIFTY')),
      '2027-01-25',
    );
  });

  test('BSE monthly is the last Thursday', () {
    expect(
      iso(ExpiryCalendar.monthlyExpiry(2026, 11, underlying: 'SENSEX')),
      '2026-11-26',
    );
    expect(
      iso(ExpiryCalendar.monthlyExpiry(2027, 1, underlying: '^BSESN')),
      '2027-01-28',
    );
  });

  test('upcoming monthlies keep today until the 15:30 IST close', () {
    final morning = DateTime.utc(2026, 11, 23, 4, 30); // 10:00 IST
    final evening = DateTime.utc(2026, 11, 23, 10, 30); // 16:00 IST
    expect(ExpiryCalendar.upcomingMonthly('NIFTY', now: morning).map(iso), [
      '2026-11-23',
      '2026-12-29',
      '2027-01-25',
    ]);
    expect(ExpiryCalendar.upcomingMonthly('NIFTY', now: evening).map(iso), [
      '2026-12-29',
      '2027-01-25',
      '2027-02-23',
    ]);
  });

  test('futures symbols parse to the real monthly expiry', () {
    expect(
      MarketService.parseDerivative('NIFTY26NOVFUT')?.expiryDate,
      '2026-11-23',
    );
    expect(
      MarketService.parseDerivative('RELIANCE26DECFUT')?.expiryDate,
      '2026-12-29',
    );
    expect(
      MarketService.parseDerivative('SENSEX26NOVFUT')?.expiryDate,
      '2026-11-26',
    );
  });
}
