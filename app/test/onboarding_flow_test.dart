import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/screens/auth/first_trade_flow.dart';
import 'package:mobile/screens/auth/onboarding_screen.dart';

void main() {
  // Thu 12 Nov 2026, 11:00 IST = 05:30 UTC (NSE open); Sun 8 Nov = closed.
  final nseOpen = DateTime.utc(2026, 11, 12, 5, 30);
  final weekend = DateTime.utc(2026, 11, 8, 5, 30);

  test('first trade is an NSE stock only when NSE is open and picked', () {
    expect(pickFirstTrade(['stock', 'crypto'], at: nseOpen).symbol, 'TATASTEEL');
    expect(pickFirstTrade(['stock', 'crypto'], at: weekend).symbol, 'BTC');
    expect(pickFirstTrade(['us_stock', 'crypto'], at: nseOpen).symbol, 'BTC');
  });

  test('crypto quantity rounds down so cost never exceeds the spend', () {
    final pick = pickFirstTrade(['crypto'], at: weekend);
    final qty = firstTradeQuantity(pick, 7654321.0);
    expect(qty * 7654321.0, lessThanOrEqualTo(200));
    expect(qty, greaterThan(0));
    expect(firstTradeQuantity(pickFirstTrade(['stock'], at: nseOpen), 150), 1);
  });

  test('country guess: IST offset beats an en_US locale', () {
    expect(guessCountryCode(offset: const Duration(hours: 5, minutes: 30), localeCountry: 'US'), 'IN');
    expect(guessCountryCode(offset: const Duration(hours: 1), localeCountry: 'it'), 'IT');
    expect(guessCountryCode(offset: Duration.zero, localeCountry: ''), 'IN');
  });
}
