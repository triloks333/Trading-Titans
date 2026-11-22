import 'dart:math' as math;

import 'option_pricing.dart';

/// One option leg of a multi-leg strategy. Quantities are in lots.
class StrategyLeg {
  bool buy;
  String type; // 'CE' or 'PE'
  double strike;
  int lots;

  /// Premium per unit at entry: the chain's price when the leg was picked.
  double premium;

  /// The chain's contract symbol, needed to place the order.
  String? symbol;

  StrategyLeg({
    required this.buy,
    required this.type,
    required this.strike,
    required this.premium,
    this.lots = 1,
    this.symbol,
  });

  int get sign => buy ? 1 : -1;
  bool get isCall => type == 'CE';

  double intrinsic(double spot) =>
      isCall ? math.max(0, spot - strike) : math.max(0, strike - spot);

  StrategyLeg copy() => StrategyLeg(
    buy: buy,
    type: type,
    strike: strike,
    premium: premium,
    lots: lots,
    symbol: symbol,
  );
}

/// Payoff, risk and margin for a set of legs on one underlying and expiry.
///
/// Pure maths, no Flutter, so it is unit-tested directly. Premiums and Greeks come
/// from [OptionPricing], the same model every other screen uses, which is also why
/// every figure is labelled an estimate in the UI.
class StrategyMath {
  StrategyMath._();

  /// P&L in rupees at expiry if the underlying settles at [spot].
  static double payoffAtExpiry(
    List<StrategyLeg> legs,
    double spot,
    int lotSize,
  ) {
    var total = 0.0;
    for (final l in legs) {
      total += l.sign * (l.intrinsic(spot) - l.premium) * l.lots * lotSize;
    }
    return total;
  }

  /// Estimated P&L before expiry: each leg re-priced at [spot] with [daysLeft] to go.
  static double pnlAt(
    List<StrategyLeg> legs,
    double spot,
    double daysLeft,
    int lotSize, {
    String? symbol,
  }) {
    if (daysLeft <= 0) return payoffAtExpiry(legs, spot, lotSize);
    var total = 0.0;
    for (final l in legs) {
      final value = OptionPricing.optionPremium(
        optionType: l.type,
        spot: spot,
        strike: l.strike,
        daysToExpiry: daysLeft,
        symbol: symbol,
      );
      total += l.sign * (value - l.premium) * l.lots * lotSize;
    }
    return total;
  }

  /// Premium received (positive) or paid (negative) to open every leg.
  static double netPremium(List<StrategyLeg> legs, int lotSize) =>
      legs.fold(0.0, (s, l) => s - l.sign * l.premium * l.lots * lotSize);

  /// Cash the order engine will block: a bought option costs its full premium, a
  /// sold one blocks 15% of its notional premium (mirrors place-order).
  static double marginRequired(List<StrategyLeg> legs, int lotSize) =>
      legs.fold(
        0.0,
        (s, l) => s + (l.buy ? 1.0 : 0.15) * l.premium * l.lots * lotSize,
      );

  static Greeks greeks(
    List<StrategyLeg> legs,
    double spot,
    double daysLeft,
    int lotSize, {
    String? symbol,
  }) {
    var g = Greeks.zero;
    for (final l in legs) {
      final one = OptionPricing.greeks(
        optionType: l.type,
        spot: spot,
        strike: l.strike,
        daysToExpiry: daysLeft,
        symbol: symbol,
      );
      g = g + one.scale(l.sign * l.lots * lotSize.toDouble());
    }
    return g;
  }

  /// Max profit, max loss (null = unlimited) and breakevens at expiry.
  ///
  /// The expiry payoff is piecewise linear with kinks only at strikes, so checking
  /// the strikes, zero, and the slope past the highest strike is exact.
  static StrategyStats stats(List<StrategyLeg> legs, int lotSize) {
    if (legs.isEmpty)
      return const StrategyStats(maxProfit: 0, maxLoss: 0, breakevens: []);
    final strikes = {for (final l in legs) l.strike}.toList()..sort();
    final xs = [0.0, ...strikes];
    final ys = [for (final x in xs) payoffAtExpiry(legs, x, lotSize)];

    // Slope beyond the top strike: only calls still move the payoff.
    final slope = legs.fold(
      0.0,
      (s, l) => s + (l.isCall ? l.sign * l.lots * lotSize : 0),
    );

    double? maxProfit = ys.reduce(math.max);
    double? maxLoss = ys.reduce(math.min);
    if (slope > 1e-9) maxProfit = null;
    if (slope < -1e-9) maxLoss = null;

    final breakevens = <double>[];
    for (var i = 0; i < xs.length - 1; i++) {
      final a = ys[i], b = ys[i + 1];
      if (a == 0) breakevens.add(xs[i]);
      if ((a < 0 && b > 0) || (a > 0 && b < 0)) {
        breakevens.add(xs[i] + (xs[i + 1] - xs[i]) * (-a) / (b - a));
      }
    }
    final last = ys.last;
    if (last == 0 && !breakevens.contains(xs.last)) breakevens.add(xs.last);
    if (slope.abs() > 1e-9 && last != 0 && (last < 0) == (slope > 0)) {
      breakevens.add(xs.last - last / slope);
    }
    return StrategyStats(
      maxProfit: maxProfit == null ? null : math.max(0, maxProfit),
      maxLoss: maxLoss == null ? null : math.min(0, maxLoss),
      breakevens: breakevens.where((b) => b > 0).toList(),
    );
  }
}

class StrategyStats {
  /// Best case at expiry in rupees; null when unlimited.
  final double? maxProfit;

  /// Worst case at expiry in rupees (zero or negative); null when unlimited.
  final double? maxLoss;
  final List<double> breakevens;
  const StrategyStats({
    required this.maxProfit,
    required this.maxLoss,
    required this.breakevens,
  });
}

/// Ready-made strategies, built from the chain's own strikes around the money.
enum StrategyPreset {
  longStraddle('Long straddle', 'Big move either way'),
  shortStraddle('Short straddle', 'Price stays put'),
  longStrangle('Long strangle', 'Big move, cheaper'),
  bullCallSpread('Bull call spread', 'Mildly bullish'),
  bearPutSpread('Bear put spread', 'Mildly bearish'),
  ironCondor('Iron condor', 'Range-bound, capped risk');

  final String label;
  final String view;
  const StrategyPreset(this.label, this.view);

  /// Legs for this preset. [strikes] sorted ascending; [premium] looks up a price.
  List<StrategyLeg> build(
    List<double> strikes,
    double spot,
    double Function(String type, double strike) premium,
    String? Function(String type, double strike) symbol,
  ) {
    if (strikes.isEmpty) return [];
    var atm = 0;
    for (var i = 0; i < strikes.length; i++) {
      if ((strikes[i] - spot).abs() < (strikes[atm] - spot).abs()) atm = i;
    }
    double at(int offset) =>
        strikes[(atm + offset).clamp(0, strikes.length - 1)];
    StrategyLeg leg(bool buy, String type, double k) => StrategyLeg(
      buy: buy,
      type: type,
      strike: k,
      premium: premium(type, k),
      symbol: symbol(type, k),
    );
    return switch (this) {
      longStraddle => [leg(true, 'CE', at(0)), leg(true, 'PE', at(0))],
      shortStraddle => [leg(false, 'CE', at(0)), leg(false, 'PE', at(0))],
      longStrangle => [leg(true, 'CE', at(1)), leg(true, 'PE', at(-1))],
      bullCallSpread => [leg(true, 'CE', at(0)), leg(false, 'CE', at(2))],
      bearPutSpread => [leg(true, 'PE', at(0)), leg(false, 'PE', at(-2))],
      ironCondor => [
        leg(true, 'PE', at(-4)),
        leg(false, 'PE', at(-2)),
        leg(false, 'CE', at(2)),
        leg(true, 'CE', at(4)),
      ],
    };
  }
}

/// Calendar days from now to an expiry date (`YYYY-MM-DD`, settling 15:30 IST).
double daysToExpiry(String? expiry, {DateTime? now}) {
  if (expiry == null) return 0;
  final d = DateTime.tryParse(expiry);
  if (d == null) return 0;
  final settle = DateTime.utc(d.year, d.month, d.day, 10, 0); // 15:30 IST
  final n = (now ?? DateTime.now()).toUtc();
  return math.max(0, settle.difference(n).inMinutes / (60 * 24));
}
