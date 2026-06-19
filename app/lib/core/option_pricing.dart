import 'dart:math' as math;

/// Single source of truth for estimating F&O prices from the underlying spot.
///
/// The app does not receive live option/future premiums, so every screen
/// (portfolio positions, order history LTP, and the pending-order fill engine)
/// must estimate them the SAME way — otherwise the same contract shows a
/// different price on different screens, and a limit order can fill at a price
/// that doesn't match the displayed LTP. All option pricing now flows through
/// [optionPremium]; all futures pricing through [futurePrice].
class OptionPricing {
  OptionPricing._();

  // Risk-free rate and implied volatility assumptions used across the app.
  static const double _r = 0.065;
  static const double _sigma = 0.25;

  /// Abramowitz-Stegun approximation of the standard normal CDF.
  static double _normalCDF(double x) {
    final t = 1 / (1 + 0.2316419 * x.abs());
    final d = 0.3989422804 * math.exp(-x * x / 2);
    final p = d *
        t *
        (0.31938153 +
            t *
                (-0.356563782 +
                    t * (1.781477937 + t * (-1.821255978 + t * 1.330274429))));
    return x >= 0 ? 1 - p : p;
  }

  /// Black-Scholes option premium. [optionType] is 'CE' or 'PE'. [tYears] is
  /// the time to expiry in years. Returns a value floored at ₹0.05 and rounded
  /// to paise, matching the prior portfolio-screen behaviour exactly.
  static double _blackScholes(
    String optionType,
    double spot,
    double strike,
    double tYears,
  ) {
    if (spot <= 0 || strike <= 0) return 0.05;
    if (tYears <= 0) {
      final intrinsic = optionType == 'CE'
          ? math.max(0.0, spot - strike)
          : math.max(0.0, strike - spot);
      return intrinsic;
    }
    final d1 = (math.log(spot / strike) + (_r + 0.5 * _sigma * _sigma) * tYears) /
        (_sigma * math.sqrt(tYears));
    final d2 = d1 - _sigma * math.sqrt(tYears);
    double price;
    if (optionType == 'CE') {
      price = spot * _normalCDF(d1) - strike * math.exp(-_r * tYears) * _normalCDF(d2);
    } else {
      price = strike * math.exp(-_r * tYears) * _normalCDF(-d2) - spot * _normalCDF(-d1);
    }
    return math.max(0.05, (price * 100).round() / 100.0);
  }

  /// Estimated option premium for the given [spot], [strike] and [optionType]
  /// at [daysToExpiry] days from now.
  static double optionPremium({
    required String optionType,
    required double spot,
    required double strike,
    required double daysToExpiry,
  }) {
    final tYears = math.max(0.0001, daysToExpiry) / 365.0;
    return _blackScholes(optionType, spot, strike, tYears);
  }

  /// Estimated futures price = spot adjusted by the cost-of-carry to expiry.
  static double futurePrice({
    required double spot,
    required double daysToExpiry,
  }) {
    if (spot <= 0) return spot;
    if (daysToExpiry <= 0) return spot;
    return spot * (1.0 + _r * (daysToExpiry / 365.0));
  }
}
