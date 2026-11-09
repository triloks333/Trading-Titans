import 'package:flutter/foundation.dart';
import '../services/currency_service.dart';
import 'currency.dart';
import 'market_hours.dart';

/// Money formatting for the whole app.
///
/// Two ideas keep this honest:
///
/// 1. **Storage is always INR.** Wallet balances, order prices, holdings and P&L
///    are rupees in the database. Nothing here ever writes a converted value.
/// 2. **Callers declare the source currency, not the output.** A wallet figure
///    is `Money.wallet(x)`; an instrument price is `Money.instrument(x, market:)`
///    and its source is inferred from the market. Money then converts into
///    whichever currency the user picked and formats it.
///
/// The user's choice and the live rate come from [CurrencyService], so changing
/// the setting repaints every screen without any call site knowing about it.
class Money {
  Money._();

  static const String rupee = '\u20b9';
  static const String dollar = '\u0024';

  /// Overridable for tests, so formatting can be checked without a live rate.
  static CurrencyService _svc = CurrencyService.instance;

  /// Swaps the backing service. Tests only.
  @visibleForTesting
  static void serviceForTesting(CurrencyService service) => _svc = service;

  static Currency get display => _svc.displayCurrency;

  /// The currency an instrument's own prices arrive in.
  ///
  /// US equities arrive in USD, Pakistan stocks in PKR, Italy stocks in EUR;
  /// Indian equities, F&O and crypto arrive in INR.
  static Currency sourceFor(String? market) => switch (market) {
        MarketHours.usStock || MarketHours.commodity => Currency.usd,
        MarketHours.pakistanStock => Currency.pkr,
        MarketHours.italyStock => Currency.eur,
        _ => Currency.inr,
      };

  /// Symbol currently being displayed. Independent of market, because the user's
  /// choice governs the whole app.
  static String get symbol => display.symbol;

  /// Converts [value] from [from] into the display currency.
  static double toDisplay(num value, {required Currency from}) =>
      _svc.converter.convert(value.toDouble(), from: from, to: display);

  static String _fmt(num value, int decimals) =>
      '${display.symbol}${value.toStringAsFixed(decimals)}';

  // ── Public formatting ──────────────────────────────────────────────────────

  /// A wallet, portfolio, charge or P&L figure. Source is always INR.
  static String wallet(num value, {int decimals = 0}) =>
      _fmt(toDisplay(value, from: Currency.inr), decimals);

  /// Same as [wallet] with an explicit sign, for P&L.
  static String signedWallet(num value, {int decimals = 2}) {
    final converted = toDisplay(value, from: Currency.inr);
    final sign = converted >= 0 ? '+' : '-';
    return '$sign${display.symbol}${converted.abs().toStringAsFixed(decimals)}';
  }

  /// An instrument price, whose source currency follows [market].
  static String instrument(num value, {String? market, int decimals = 2}) =>
      _fmt(toDisplay(value, from: sourceFor(market)), decimals);

  /// Same as [instrument] with an explicit sign.
  static String signedInstrument(num value, {String? market, int decimals = 2}) {
    final converted = toDisplay(value, from: sourceFor(market));
    final sign = converted >= 0 ? '+' : '-';
    return '$sign${display.symbol}${converted.abs().toStringAsFixed(decimals)}';
  }

  /// A value already known to be in a specific currency.
  static String from(num value, Currency source, {int decimals = 2}) =>
      _fmt(toDisplay(value, from: source), decimals);

  /// Bare number in the display currency, no symbol — for text fields and
  /// prefixed inputs where the symbol is rendered separately.
  static String bare(num value, {required Currency from, int decimals = 2}) =>
      toDisplay(value, from: from).toStringAsFixed(decimals);

  /// Converts a number the **user typed** back into the instrument's own
  /// currency, which is what order maths runs in.
  ///
  /// The inverse of [instrument]. Critical for limit prices and "amount to
  /// invest": a figure entered as dollars must not be handed to the engine as
  /// rupees, or the order is out by the exchange rate.
  static double fromDisplay(num typed, {String? market}) => _svc.converter
      .convert(typed.toDouble(), from: display, to: sourceFor(market));

  /// Converts a typed figure into rupees, for comparing against the wallet.
  static double typedToInr(num typed) =>
      _svc.converter.convert(typed.toDouble(), from: display, to: Currency.inr);

  /// Quantity precision: crypto trades in fractions, equities in whole units.
  static String quantity(num value, {String? market}) =>
      MarketHours.isFractional(market) ? value.toStringAsFixed(4) : value.toStringAsFixed(0);

  /// True when the display currency differs from the stored one, so screens can
  /// show a "converted at" note where the real charge matters.
  static bool get isConverted => display != Currency.inr;

  /// The rate currently used for conversion, or null when none is known.
  static double? get rate => _svc.usdInr > 0 ? _svc.usdInr : null;

  /// A short note explaining the conversion, for order confirmation screens.
  /// Returns null when nothing is being converted.
  static String? conversionNote({String? market}) {
    final src = sourceFor(market);
    final target = display;

    // If instrument source is non-INR, show instrument conversion to INR
    if (src != Currency.inr) {
      final rate = _svc.converter.inrRateFor(src);
      return '(1 ${src.symbol.trim()} = $rupee${rate.toStringAsFixed(2)})';
    }

    // If user's display currency is non-INR, explain user currency to INR
    if (target != Currency.inr) {
      final rate = _svc.converter.inrRateFor(target);
      if (market == null) {
        return 'Converted at 1 ${target.symbol.trim()} = $rupee${rate.toStringAsFixed(2)}';
      }
      return '(1 ${target.symbol.trim()} = $rupee${rate.toStringAsFixed(2)})';
    }

    return null;
  }

  /// The rupee amount that will actually move in the wallet, for a figure whose
  /// source currency follows [market].
  static double inrValueOf(num value, {String? market}) => _svc.converter
      .convert(value.toDouble(), from: sourceFor(market), to: Currency.inr);

  /// True when the number on screen is not the rupee amount that will leave the
  /// wallet — either because the user is viewing dollars, or because the
  /// instrument is priced in dollars, or both.
  static bool differsFromWallet(String? market) =>
      display != Currency.inr || sourceFor(market) != Currency.inr;

  /// Always-rupee rendering, for the "this is what you will actually be charged"
  /// line. Deliberately ignores the display preference.
  static String walletChargeInr(num inrValue, {int decimals = 2}) =>
      '$rupee${inrValue.toStringAsFixed(decimals)}';
}
