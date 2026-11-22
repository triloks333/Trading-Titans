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
  static const double _sigmaStock = 0.24;
  static const double _sigmaIndex = 0.14;

  /// Returns calibrated IV based on whether the underlying is an index or stock.
  static double sigmaFor(String? symbol) {
    if (symbol == null) return _sigmaStock;
    final s = symbol.toUpperCase();
    if (s.contains('NIFTY') || s.contains('SENSEX') || s.contains('BANKEX')) {
      return _sigmaIndex;
    }
    return _sigmaStock;
  }

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
    double sigma,
  ) {
    if (spot <= 0 || strike <= 0) return 0.05;
    final intrinsic = optionType.toUpperCase() == 'CE'
        ? math.max(0.0, spot - strike)
        : math.max(0.0, strike - spot);
    if (tYears <= 0) {
      return math.max(0.05, (intrinsic * 100).round() / 100.0);
    }
    final d1 = (math.log(spot / strike) + (_r + 0.5 * sigma * sigma) * tYears) /
        (sigma * math.sqrt(tYears));
    final d2 = d1 - sigma * math.sqrt(tYears);
    double price;
    if (optionType.toUpperCase() == 'CE') {
      price = spot * _normalCDF(d1) - strike * math.exp(-_r * tYears) * _normalCDF(d2);
    } else {
      price = strike * math.exp(-_r * tYears) * _normalCDF(-d2) - spot * _normalCDF(-d1);
    }
    return math.max(0.05, math.max(intrinsic, (price * 100).round() / 100.0));
  }

  /// Calculates Black-Scholes Delta for option sensitivity to underlying movements.
  static double delta({
    required String optionType,
    required double spot,
    required double strike,
    required double daysToExpiry,
    String? symbol,
    double? sigma,
  }) {
    if (spot <= 0 || strike <= 0) return 0.0;
    if (daysToExpiry <= 0) {
      if (optionType.toUpperCase() == 'CE') {
        return spot > strike ? 1.0 : 0.0;
      } else {
        return spot < strike ? -1.0 : 0.0;
      }
    }
    final tYears = math.max(0.0001, daysToExpiry) / 365.0;
    final sig = sigma ?? sigmaFor(symbol);
    final d1 = (math.log(spot / strike) + (_r + 0.5 * sig * sig) * tYears) /
        (sig * math.sqrt(tYears));
    if (optionType.toUpperCase() == 'CE') {
      return _normalCDF(d1).clamp(0.0, 1.0);
    } else {
      return (_normalCDF(d1) - 1.0).clamp(-1.0, 0.0);
    }
  }

  /// Standard normal density.
  static double _normalPDF(double x) => 0.3989422804014327 * math.exp(-x * x / 2);

  /// Delta, gamma, theta (per calendar day) and vega (per 1 point of IV) for ONE
  /// unit of the option, from the same Black-Scholes inputs as [optionPremium].
  ///
  /// Theta is per day so a user reads "you lose ₹12 a day to time"; vega per 1%
  /// IV so "IV up 1 point adds ₹8". At or past expiry every Greek but delta is 0.
  static Greeks greeks({
    required String optionType,
    required double spot,
    required double strike,
    required double daysToExpiry,
    String? symbol,
    double? sigma,
  }) {
    final isCall = optionType.toUpperCase() == 'CE';
    final d = delta(optionType: optionType, spot: spot, strike: strike, daysToExpiry: daysToExpiry, symbol: symbol, sigma: sigma);
    if (spot <= 0 || strike <= 0 || daysToExpiry <= 0) return Greeks(delta: d, gamma: 0, theta: 0, vega: 0);
    final t = math.max(0.0001, daysToExpiry) / 365.0;
    final sig = sigma ?? sigmaFor(symbol);
    final sqrtT = math.sqrt(t);
    final d1 = (math.log(spot / strike) + (_r + 0.5 * sig * sig) * t) / (sig * sqrtT);
    final d2 = d1 - sig * sqrtT;
    final pdf = _normalPDF(d1);
    final gamma = pdf / (spot * sig * sqrtT);
    final vega = spot * pdf * sqrtT / 100;
    final common = -(spot * pdf * sig) / (2 * sqrtT);
    final carry = _r * strike * math.exp(-_r * t);
    final thetaYear = isCall ? common - carry * _normalCDF(d2) : common + carry * _normalCDF(-d2);
    return Greeks(delta: d, gamma: gamma, theta: thetaYear / 365, vega: vega);
  }

  /// Estimated option premium for the given [spot], [strike] and [optionType]
  /// at [daysToExpiry] days from now.
  static double optionPremium({
    required String optionType,
    required double spot,
    required double strike,
    required double daysToExpiry,
    String? symbol,
    double? sigma,
  }) {
    final tYears = math.max(0.0001, daysToExpiry) / 365.0;
    final sig = sigma ?? sigmaFor(symbol);
    return _blackScholes(optionType, spot, strike, tYears, sig);
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

/// Option sensitivities for one unit. Multiply by signed quantity for a position.
class Greeks {
  final double delta, gamma, theta, vega;
  const Greeks({required this.delta, required this.gamma, required this.theta, required this.vega});

  static const zero = Greeks(delta: 0, gamma: 0, theta: 0, vega: 0);

  Greeks operator +(Greeks o) => Greeks(delta: delta + o.delta, gamma: gamma + o.gamma, theta: theta + o.theta, vega: vega + o.vega);
  Greeks scale(double k) => Greeks(delta: delta * k, gamma: gamma * k, theta: theta * k, vega: vega * k);
}
