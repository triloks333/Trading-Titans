// Full-coverage tests for the shared F&O pricing model. This is the single
// source of truth used by the portfolio LTP, the order-history LTP, and the
// limit-fill engine — so a regression here would desync all three (the exact
// bug we just fixed).

import 'package:flutter_test/flutter_test.dart';
import 'package:glados/glados.dart' hide test, group, expect;
import 'package:mobile/core/option_pricing.dart';

void main() {
  group('OptionPricing.optionPremium', () {
    test('deep ITM call ~ at least intrinsic value', () {
      final p = OptionPricing.optionPremium(
        optionType: 'CE', spot: 1500, strike: 1000, daysToExpiry: 7);
      expect(p, greaterThanOrEqualTo(500 - 1)); // intrinsic ~500
    });

    test('ITM call near expiry approaches intrinsic', () {
      final p = OptionPricing.optionPremium(
        optionType: 'CE', spot: 1332.7, strike: 1320, daysToExpiry: 7);
      // intrinsic is 12.7; with time value it must be >= intrinsic and reasonable
      expect(p, greaterThanOrEqualTo(12.7));
      expect(p, lessThan(60)); // sanity upper bound for a 7d ATM-ish option
    });

    test('OTM option still has positive time value before expiry', () {
      final call = OptionPricing.optionPremium(
        optionType: 'CE', spot: 1000, strike: 1100, daysToExpiry: 7);
      expect(call, greaterThan(0));
    });

    test('floored at 0.05', () {
      final p = OptionPricing.optionPremium(
        optionType: 'CE', spot: 100, strike: 100000, daysToExpiry: 1);
      expect(p, greaterThanOrEqualTo(0.05));
    });

    test('at expiry (<=0 days) returns intrinsic for CE', () {
      final p = OptionPricing.optionPremium(
        optionType: 'CE', spot: 120, strike: 100, daysToExpiry: 0);
      // tYears floored at 0.0001 so it is ~intrinsic
      expect(p, closeTo(20, 1.0));
    });

    test('PE is worth more than CE when deep OTM call / deep ITM put', () {
      final put = OptionPricing.optionPremium(
        optionType: 'PE', spot: 1000, strike: 1200, daysToExpiry: 7);
      final call = OptionPricing.optionPremium(
        optionType: 'CE', spot: 1000, strike: 1200, daysToExpiry: 7);
      expect(put, greaterThan(call));
    });

    test('guards against zero/negative spot or strike', () {
      expect(OptionPricing.optionPremium(optionType: 'CE', spot: 0, strike: 100, daysToExpiry: 7), 0.05);
      expect(OptionPricing.optionPremium(optionType: 'CE', spot: 100, strike: 0, daysToExpiry: 7), 0.05);
    });

    Glados2<int, int>(
      any.intInRange(500, 2000),
      any.intInRange(500, 2000),
    ).test('premium is always finite, non-negative and >= 0.05', (spot, strike) {
      final p = OptionPricing.optionPremium(
        optionType: 'CE', spot: spot.toDouble(), strike: strike.toDouble(), daysToExpiry: 7);
      expect(p.isFinite, true);
      expect(p, greaterThanOrEqualTo(0.05));
    });

    Glados<int>(any.intInRange(1000, 2000)).test(
        'call premium is monotonic non-decreasing in spot', (strikeInt) {
      final strike = strikeInt.toDouble();
      double prev = -1;
      for (var spot = 800.0; spot <= 2200; spot += 50) {
        final p = OptionPricing.optionPremium(
          optionType: 'CE', spot: spot, strike: strike, daysToExpiry: 7);
        expect(p, greaterThanOrEqualTo(prev - 0.05),
            reason: 'call premium should not fall as spot rises');
        prev = p;
      }
    });
  });

  group('OptionPricing.futurePrice', () {
    test('adds positive cost-of-carry before expiry', () {
      final f = OptionPricing.futurePrice(spot: 1000, daysToExpiry: 30);
      expect(f, greaterThan(1000));
      expect(f, lessThan(1010)); // tiny carry
    });

    test('equals spot at/after expiry', () {
      expect(OptionPricing.futurePrice(spot: 1000, daysToExpiry: 0), 1000);
      expect(OptionPricing.futurePrice(spot: 1000, daysToExpiry: -5), 1000);
    });

    test('returns spot unchanged for non-positive spot', () {
      expect(OptionPricing.futurePrice(spot: 0, daysToExpiry: 30), 0);
    });
  });
}
