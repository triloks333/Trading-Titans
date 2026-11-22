import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/option_pricing.dart';
import 'package:mobile/core/strategy.dart';

void main() {
  group('StrategyMath', () {
    test(
      'long straddle: unlimited profit, loss capped at premium, two breakevens',
      () {
        final legs = [
          StrategyLeg(buy: true, type: 'CE', strike: 100, premium: 5),
          StrategyLeg(buy: true, type: 'PE', strike: 100, premium: 5),
        ];
        final s = StrategyMath.stats(legs, 10);
        expect(s.maxProfit, isNull);
        expect(s.maxLoss, closeTo(-100, 1e-9)); // (5+5) * 10
        expect(s.breakevens.length, 2);
        expect(s.breakevens[0], closeTo(90, 1e-9));
        expect(s.breakevens[1], closeTo(110, 1e-9));
        expect(StrategyMath.netPremium(legs, 10), closeTo(-100, 1e-9));
      },
    );

    test('short straddle: unlimited loss', () {
      final legs = [
        StrategyLeg(buy: false, type: 'CE', strike: 100, premium: 5),
        StrategyLeg(buy: false, type: 'PE', strike: 100, premium: 5),
      ];
      final s = StrategyMath.stats(legs, 1);
      expect(s.maxLoss, isNull);
      expect(s.maxProfit, closeTo(10, 1e-9));
      expect(StrategyMath.marginRequired(legs, 1), closeTo(1.5, 1e-9));
    });

    test('bull call spread: both sides capped', () {
      final legs = [
        StrategyLeg(buy: true, type: 'CE', strike: 100, premium: 6),
        StrategyLeg(buy: false, type: 'CE', strike: 110, premium: 2),
      ];
      final s = StrategyMath.stats(legs, 1);
      expect(s.maxProfit, closeTo(6, 1e-9)); // 10 wide - 4 debit
      expect(s.maxLoss, closeTo(-4, 1e-9));
      expect(s.breakevens.single, closeTo(104, 1e-9));
    });

    test('iron condor preset picks strikes around the money', () {
      final strikes = [for (var k = 80.0; k <= 120; k += 5) k];
      final legs = StrategyPreset.ironCondor.build(
        strikes,
        101,
        (t, k) => 1,
        (t, k) => null,
      );
      expect(legs.map((l) => l.strike), [80, 90, 110, 120]);
      final s = StrategyMath.stats(legs, 1);
      expect(s.maxProfit, isNotNull);
      expect(s.maxLoss, isNotNull);
    });

    test('pnl before expiry converges to payoff at expiry', () {
      final legs = [
        StrategyLeg(buy: true, type: 'CE', strike: 100, premium: 3),
      ];
      expect(
        StrategyMath.pnlAt(legs, 120, 0, 1),
        StrategyMath.payoffAtExpiry(legs, 120, 1),
      );
    });
  });

  group('OptionPricing.greeks', () {
    test('call has positive gamma and vega, negative theta', () {
      final g = OptionPricing.greeks(
        optionType: 'CE',
        spot: 100,
        strike: 100,
        daysToExpiry: 30,
      );
      expect(g.delta, inInclusiveRange(0.4, 0.7));
      expect(g.gamma, greaterThan(0));
      expect(g.vega, greaterThan(0));
      expect(g.theta, lessThan(0));
    });

    test('theta roughly matches one day of premium decay', () {
      const args = (spot: 22000.0, strike: 22000.0);
      final today = OptionPricing.optionPremium(
        optionType: 'PE',
        spot: args.spot,
        strike: args.strike,
        daysToExpiry: 10,
        symbol: 'NIFTY',
      );
      final tomorrow = OptionPricing.optionPremium(
        optionType: 'PE',
        spot: args.spot,
        strike: args.strike,
        daysToExpiry: 9,
        symbol: 'NIFTY',
      );
      final g = OptionPricing.greeks(
        optionType: 'PE',
        spot: args.spot,
        strike: args.strike,
        daysToExpiry: 10,
        symbol: 'NIFTY',
      );
      expect(
        g.theta,
        closeTo(tomorrow - today, (tomorrow - today).abs() * 0.15),
      );
    });
  });
}
