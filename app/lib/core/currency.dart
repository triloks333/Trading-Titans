/// The two currencies the app can present money in.
///
/// Storage is always INR: the wallet ledger, order prices, holdings and P&L are
/// all rupees in the database. This enum only describes what the user sees.
enum Currency {
  inr('INR', '\u20b9'),
  usd('USD', '\u0024');

  const Currency(this.code, this.symbol);

  final String code;
  final String symbol;

  static Currency fromCode(String? code) => switch (code?.toUpperCase()) {
        'USD' => Currency.usd,
        _ => Currency.inr,
      };

  /// Label for the onboarding picker and the settings row.
  String get label => switch (this) {
        Currency.inr => 'Indian Rupee',
        Currency.usd => 'US Dollar',
      };

  String get subtitle => switch (this) {
        Currency.inr => 'Show all prices and balances in \u20b9',
        Currency.usd => 'Show all prices and balances in \u0024',
      };
}

/// Where the user is trading from. Two options only.
///
/// Used to pre-select sensible answers to the currency and market questions
/// during onboarding, and stored for its own sake. It does not restrict access
/// to any market — everyone can trade everything.
enum TradingLocation {
  india('india'),
  outsideIndia('outside_india');

  const TradingLocation(this.code);

  final String code;

  static TradingLocation? fromCode(String? code) => switch (code?.toLowerCase()) {
        'india' => TradingLocation.india,
        'outside_india' => TradingLocation.outsideIndia,
        _ => null,
      };

  String get label => switch (this) {
        TradingLocation.india => 'I\u2019m in India',
        TradingLocation.outsideIndia => 'I\u2019m outside India',
      };

  String get subtitle => switch (this) {
        TradingLocation.india =>
          'Prices in rupees, Indian markets front and centre',
        TradingLocation.outsideIndia =>
          'Prices in dollars, US markets front and centre',
      };

  /// The currency this location suggests. A suggestion only: the next step still
  /// lets the user choose freely.
  Currency get suggestedCurrency =>
      this == TradingLocation.india ? Currency.inr : Currency.usd;

  /// The markets this location suggests pre-ticking.
  List<String> get suggestedMarkets => this == TradingLocation.india
      ? const ['stock', 'crypto']
      : const ['us_stock', 'crypto'];
}

/// Converts between the two currencies at a given USD/INR rate.
///
/// Kept as a plain value type with no I/O so the arithmetic is testable on its
/// own, separately from fetching the rate or reading the user's preference.
class FxConverter {
  const FxConverter({required this.usdInr});

  /// Rupees per US dollar. Must be positive; a non-positive rate makes
  /// conversion a no-op rather than producing zeros or infinities.
  final double usdInr;

  bool get isUsable => usdInr > 0 && usdInr.isFinite;

  /// Converts [value] from [from] into [to].
  double convert(double value, {required Currency from, required Currency to}) {
    if (from == to || !isUsable) return value;
    return switch ((from, to)) {
      (Currency.inr, Currency.usd) => value / usdInr,
      (Currency.usd, Currency.inr) => value * usdInr,
      _ => value,
    };
  }
}
