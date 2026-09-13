import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/currency.dart';
import '../core/market_hours.dart';
import 'market_service.dart';
import 'supabase_service.dart';

/// Holds the user's display-currency choice, their preferred markets, and the
/// live USD/INR rate that money formatting depends on.
///
/// Single source of truth for "what currency am I showing?" — [Money] reads this
/// singleton, and widgets watch it so a change in settings repaints the app.
///
/// The rate and the preference are both persisted locally so the first frame
/// after a cold start formats correctly instead of flashing rupees at a user who
/// chose dollars.
class CurrencyService extends ChangeNotifier {
  CurrencyService._internal();
  static final CurrencyService instance = CurrencyService._internal();

  /// For tests only: lets a stub subclass override the getters without touching
  /// SharedPreferences or the network.
  @visibleForTesting
  CurrencyService.forTesting();

  static const _kCurrency = 'display_currency';
  static const _kMarkets = 'preferred_markets';
  static const _kRate = 'usd_inr_rate';
  static const _kOnboarded = 'onboarding_done';
  static const _kLocation = 'trading_location';
  static const _kCountry = 'country_code';
  static const _kState = 'state';

  /// Refetch the rate at most this often. A paper-trading display does not need
  /// tick-level FX.
  static const Duration _rateTtl = Duration(minutes: 30);

  Currency _display = Currency.inr;
  TradingLocation? _location;
  String? _countryCode;
  String? _state;
  List<String> _preferredMarkets = const ['stock', 'crypto'];
  double _usdInr = 0;
  DateTime? _rateFetchedAt;
  bool _onboardingComplete = false;
  bool _loaded = false;

  Currency get displayCurrency => _display;

  /// Null for accounts that predate the question, or before onboarding.
  TradingLocation? get location => _location;

  /// ISO 3166-1 alpha-2, or null for accounts that only answered the older
  /// india/outside_india question. Finer-grained than [location] and never
  /// contradicts it: the server derives one from the other.
  String? get countryCode => _countryCode;

  /// Subdivision within [countryCode], as picked or typed. Null when not set.
  String? get state => _state;
  List<String> get preferredMarkets => List.unmodifiable(_preferredMarkets);
  double get usdInr => _usdInr;
  bool get onboardingComplete => _onboardingComplete;
  bool get isLoaded => _loaded;

  /// True when we have a rate and therefore can convert.
  bool get canConvert => converter.isUsable;

  // Reads the public getter, not the private field, so a test subclass that
  // overrides `usdInr` actually changes what gets converted.
  FxConverter get converter => FxConverter(usdInr: usdInr);

  /// True when showing a currency that needs conversion from stored INR.
  bool get needsConversion => _display != Currency.inr;

  /// The currency the user is actually charged in.
  ///
  /// Residency, not [displayCurrency]. Eight accounts sit in India with a dollar
  /// display; that setting is cosmetic and must not decide what Razorpay charges,
  /// or someone gets billed in dollars because they preferred the look of them.
  /// A null location predates the question and means India.
  ///
  /// Deliberately the same rule as `create-payment-order`, which resolves this
  /// server-side from `profiles.location`. The server is authoritative — this
  /// exists so the price on screen is the price on the invoice, and if the two
  /// rules ever diverge the user is quoted one number and charged another.
  ///
  /// Reads the public [location] getter rather than the field, for the same reason
  /// [converter] reads [usdInr]: a test subclass that overrides the getter has to
  /// actually change the answer.
  Currency get billingCurrency =>
      location == TradingLocation.outsideIndia ? Currency.usd : Currency.inr;

  // ── Load ───────────────────────────────────────────────────────────────────

  /// Restores the cached preference and rate. Call before the first frame so the
  /// UI never renders in the wrong currency.
  Future<void> loadCached() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _display = Currency.fromCode(prefs.getString(_kCurrency));
      _preferredMarkets = prefs.getStringList(_kMarkets) ?? _preferredMarkets;
      _location = TradingLocation.fromCode(prefs.getString(_kLocation));
      _countryCode = prefs.getString(_kCountry);
      _state = prefs.getString(_kState);
      _usdInr = prefs.getDouble(_kRate) ?? 0;
      _onboardingComplete = prefs.getBool(_kOnboarded) ?? false;
      _loaded = true;
      notifyListeners();
    } catch (e) {
      debugPrint('CurrencyService.loadCached failed: $e');
    }
  }

  /// Pulls the authoritative preference from the server and refreshes the rate.
  /// Safe to call on every foreground.
  Future<void> refresh() async {
    await Future.wait([_refreshPreferences(), refreshRate()]);
  }

  Future<void> _refreshPreferences() async {
    try {
      final prefs = await SupabaseService().getUserPreferences();
      if (prefs == null) return;
      _display = Currency.fromCode(prefs['display_currency'] as String?);
      final markets = prefs['preferred_markets'];
      if (markets is List && markets.isNotEmpty) {
        _preferredMarkets = markets.map((e) => '$e').toList();
      }
      _location = TradingLocation.fromCode(prefs['location'] as String?);
      _countryCode = prefs['country_code'] as String?;
      _state = prefs['state'] as String?;
      _onboardingComplete = prefs['onboarding_completed_at'] != null;
      await _persist();
      notifyListeners();
    } catch (e) {
      debugPrint('CurrencyService._refreshPreferences failed: $e');
    }
  }

  /// Fetches USD/INR unless the cached value is still fresh.
  Future<void> refreshRate({bool force = false}) async {
    final age = _rateFetchedAt == null
        ? null
        : DateTime.now().difference(_rateFetchedAt!);
    if (!force && _usdInr > 0 && age != null && age < _rateTtl) return;
    try {
      final rate = await MarketService.fetchUsdInrRate();
      if (rate != null && rate > 0) {
        _usdInr = rate;
        _rateFetchedAt = DateTime.now();
        await _persist();
        notifyListeners();
      }
    } catch (e) {
      debugPrint('CurrencyService.refreshRate failed: $e');
    }
  }

  // ── Mutate ─────────────────────────────────────────────────────────────────

  /// Changes the display currency. Optimistic: the UI repaints immediately and
  /// the server write follows, because this is a presentation setting and a
  /// failed write costs nothing but a stale preference on the next device.
  Future<void> setDisplayCurrency(Currency currency) async {
    if (currency == _display) return;
    _display = currency;
    await _persist();
    notifyListeners();
    // A USD view is useless without a rate, so make sure we have one.
    if (currency == Currency.usd && _usdInr <= 0) {
      await refreshRate(force: true);
    }
    await SupabaseService().saveUserPreferences(displayCurrency: currency.code);
  }

  // There is deliberately no setLocation. Settings sets a country, and residency
  // is derived from it (see [setCountryAndState]); a coarse setter alongside that
  // would let the two contradict each other and bill someone on the wrong
  // continent. Onboarding still records the coarse answer directly via
  // [completeOnboarding], which is safe because a new account has no country yet.

  /// Records the country, and optionally the subdivision within it.
  ///
  /// Moves [location] in the same step, mirroring the derivation the RPC applies:
  /// 'IN' is india, any other country is outside_india. Done locally as well as
  /// server-side because [billingCurrency] reads [location] to put a price on
  /// screen, and leaving it stale until the next refresh would quote a user one
  /// currency and charge them another.
  ///
  /// Pass an empty [state] to clear it; pass null to leave it alone.
  Future<void> setCountryAndState(String countryCode, {String? state}) async {
    final code = countryCode.trim().toUpperCase();
    if (code.length != 2) return;
    _countryCode = code;
    _location =
        code == 'IN' ? TradingLocation.india : TradingLocation.outsideIndia;
    if (state != null) _state = state.trim().isEmpty ? null : state.trim();
    await _persist();
    notifyListeners();
    await SupabaseService().saveUserPreferences(
      countryCode: code,
      // '' clears server-side, which null would not.
      state: state == null ? null : (_state ?? ''),
    );
  }

  Future<void> setPreferredMarkets(List<String> markets) async {
    final cleaned = markets
        .where((m) => const ['stock', 'us_stock', 'crypto'].contains(m))
        .toSet()
        .toList();
    if (cleaned.isEmpty) return;
    _preferredMarkets = cleaned;
    await _persist();
    notifyListeners();
    await SupabaseService().saveUserPreferences(preferredMarkets: cleaned);
  }

  /// Records both answers and marks onboarding done, in one server round trip.
  Future<void> completeOnboarding({
    required Currency currency,
    required List<String> markets,
    TradingLocation? location,
  }) async {
    _display = currency;
    if (location != null) _location = location;
    final cleaned = markets
        .where((m) => const ['stock', 'us_stock', 'crypto'].contains(m))
        .toSet()
        .toList();
    if (cleaned.isNotEmpty) _preferredMarkets = cleaned;
    _onboardingComplete = true;
    await _persist();
    notifyListeners();
    if (currency == Currency.usd && _usdInr <= 0) {
      await refreshRate(force: true);
    }
    await SupabaseService().saveUserPreferences(
      displayCurrency: currency.code,
      preferredMarkets: _preferredMarkets,
      location: _location?.code,
      completeOnboarding: true,
    );
  }

  /// Clears per-user state on sign-out so the next account starts clean.
  Future<void> reset() async {
    _display = Currency.inr;
    _preferredMarkets = const ['stock', 'crypto'];
    _location = null;
    _countryCode = null;
    _state = null;
    _onboardingComplete = false;
    await _persist();
    notifyListeners();
  }

  /// The market tab to open by default: the first preferred market, in the
  /// canonical order, falling back to Indian stocks.
  String get defaultMarket {
    for (final m in MarketTabOrder.canonical) {
      if (_preferredMarkets.contains(m)) return m;
    }
    return 'stock';
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kCurrency, _display.code);
      await prefs.setStringList(_kMarkets, _preferredMarkets);
      await prefs.setBool(_kOnboarded, _onboardingComplete);
      if (_location != null) {
        await prefs.setString(_kLocation, _location!.code);
      } else {
        await prefs.remove(_kLocation);
      }
      if (_countryCode != null) {
        await prefs.setString(_kCountry, _countryCode!);
      } else {
        await prefs.remove(_kCountry);
      }
      if (_state != null) {
        await prefs.setString(_kState, _state!);
      } else {
        await prefs.remove(_kState);
      }
      if (_usdInr > 0) await prefs.setDouble(_kRate, _usdInr);
    } catch (e) {
      debugPrint('CurrencyService._persist failed: $e');
    }
  }
}

/// Canonical market ordering, shared by the nav bar and the default-tab choice.
class MarketTabOrder {
  MarketTabOrder._();
  static const List<String> canonical = ['stock', MarketHours.usStock, 'crypto'];
}
