import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/currency.dart';

/// The signed-in user's plan, and where to send them to change it.
///
/// The tier comes from the `current_tier()` function, which derives it from the
/// `subscriptions` table. It is deliberately not stored on `profiles`: a stored
/// copy has to be kept in step with the subscription, and when it drifts a paying
/// user loses access or a lapsed one keeps it. Derived cannot drift.
///
/// Follows the same shape as [AppFlagsService] — singleton, `ChangeNotifier`,
/// refreshed on launch and on foreground — so a badge anywhere in the tree is a
/// `context.watch` away, and there is one place that does the fetching.
///
/// Defaults to free and stays free on any error. Failing the other way would hand
/// out paid features to everyone the moment the network hiccuped.
class PlanService extends ChangeNotifier {
  PlanService._internal();
  static final PlanService instance = PlanService._internal();

  /// Where the app hands a purchase off to. Payments happen on the web, so the
  /// app never handles a card.
  ///
  /// Overridable from `app_config.web_checkout_url` because this is baked into
  /// every installed APK — if the domain ever moves, a shipped build with a
  /// hardcoded URL would send users to a dead page with no way to fix it.
  ///
  /// This value has to be right on its own, though, and it was not: it pointed at
  /// trading-titans-web.vercel.app/plans, which started returning 404 the moment
  /// the web app moved under /app. The override could not save it either, because
  /// `app_config` has row level security enabled with no SELECT policy, so a
  /// signed-in client reads zero rows and silently keeps whatever is written here.
  /// Treat the fallback as the real value and the override as a convenience.
  static const String _fallbackCheckoutUrl =
      'https://thetradingtitans.com/app/plans';

  String _tier = 'free';
  String _checkoutUrl = _fallbackCheckoutUrl;
  bool _loaded = false;

  /// One of `free`, `pro`, `titan`.
  String get tier => _tier;
  bool get isPaid => _tier == 'pro' || _tier == 'titan';
  bool get isLoaded => _loaded;
  String get checkoutUrl => _checkoutUrl;

  // ── Plan limits ─────────────────────────────────────────────────────────
  // From `my_plan_usage()`. The server enforces every metered or stored limit
  // (F&O trades, autopsies, alerts, watchlists); the app reads this to show
  // "2 of 3 used" and to lock screens before a user runs into a wall. History and
  // chart ranges are only limited here, in the app.
  //
  // Starts empty, which reads as "no limits". Failing closed on a network blip
  // would lock a paying user out of things they paid for; the server still says
  // no where it matters.
  Map<String, ({int? limit, int used})> _limits = const {};
  bool _limitsEnforced = false;
  bool _trialEligible = false;
  DateTime? _passEndsAt;

  /// The cap for [feature] on this account, or null when unlimited.
  int? limitFor(String feature) => _limitsEnforced ? _limits[feature]?.limit : null;
  int usedFor(String feature) => _limits[feature]?.used ?? 0;

  /// Uses left this period, or null when unlimited.
  int? remaining(String feature) {
    final l = limitFor(feature);
    return l == null ? null : (l - usedFor(feature)).clamp(0, l);
  }

  bool isExhausted(String feature) => remaining(feature) == 0;

  /// True for a signed-in account that has never paid for a plan: offered the ₹1 week.
  bool get trialEligible => _trialEligible;

  /// When the current 7-day pass runs out, or null without one.
  DateTime? get passEndsAt => _passEndsAt;
  bool get isTitan => _tier == 'titan';

  /// Titan-only tools (strategy basket orders, the Greeks risk panel). Open to
  /// everyone while limits are off, matching the server.
  bool get hasTitanTools => !_limitsEnforced || _tier == 'titan';

  /// Pro-or-better tools (coach report, follow traders, paid league).
  bool get hasProTools => !_limitsEnforced || isPaid;

  /// Account history visible in days, or null for all of it.
  int? get historyDays => limitFor(PlanFeature.historyDays);

  /// Longest chart range in days, or null for every range.
  int? get chartDays => limitFor(PlanFeature.chartDays);

  /// Re-reads usage, e.g. after a trade, so counters stay honest.
  Future<void> refreshUsage() async {
    final client = Supabase.instance.client;
    if (client.auth.currentUser == null) {
      _limits = const {};
      _trialEligible = false;
      _passEndsAt = null;
      notifyListeners();
      return;
    }
    try {
      final res = await client.rpc('my_plan_usage');
      if (res is! Map) return;
      final raw = res['limits'];
      final next = <String, ({int? limit, int used})>{};
      if (raw is Map) {
        raw.forEach((k, v) {
          if (v is Map) {
            next['$k'] = (limit: (v['limit'] as num?)?.toInt(), used: (v['used'] as num?)?.toInt() ?? 0);
          }
        });
      }
      _limits = next;
      _limitsEnforced = res['enforced'] == true;
      _trialEligible = res['trial_eligible'] == true;
      _passEndsAt = DateTime.tryParse('${res['pass_ends_at'] ?? ''}')?.toLocal();
      final t = res['tier'];
      if (t is String) _tier = t;
      notifyListeners();
    } catch (e) {
      debugPrint('PlanService: could not read usage: $e');
    }
  }

  bool _saleActive = false;
  DateTime? _saleEndsAt;

  /// True while `plan_catalogue` has sale prices. See
  /// 20261103010000_diwali_sale_half_price.sql.
  bool get saleActive => _saleActive;
  DateTime? get saleEndsAt => _saleEndsAt;

  /// A rupee figure in marketing copy ("from ₹199"), at sale price while a sale
  /// runs. Real prices come from [PlanOption]; this is only for banner text.
  /// shortcut: assumes a 50% sale rounded down, like the migration. Read the
  /// ratio from the catalogue if a sale ever uses another discount.
  String marketingRupees(int full) => '₹${_saleActive ? full ~/ 2 : full}';

  Future<void> refresh() async {
    final client = Supabase.instance.client;

    // Before the signed-out check: the catalogue is public and the sale banner
    // shows to everyone.
    try {
      final row = await client
          .from('plan_catalogue')
          .select('sale_ends_at')
          .eq('is_active', true)
          .not('compare_at_paise', 'is', null)
          .limit(1)
          .maybeSingle();
      final active = row != null;
      final ends = DateTime.tryParse(row?['sale_ends_at'] as String? ?? '')?.toLocal();
      if (active != _saleActive || ends != _saleEndsAt) {
        _saleActive = active;
        _saleEndsAt = ends;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('PlanService: could not read sale state: $e');
    }

    // Signed out: reset, or a badge would linger from the previous account.
    if (client.auth.currentUser == null) {
      if (_tier != 'free') {
        _tier = 'free';
        notifyListeners();
      }
      return;
    }

    try {
      final tier = await client.rpc('current_tier');
      final next = tier is String ? tier : 'free';
      if (next != _tier) {
        _tier = next;
        notifyListeners();
      }
      _loaded = true;
      await refreshUsage();
    } catch (e) {
      // Keep whatever we had. Never fail open.
      debugPrint('PlanService: could not read tier, keeping "$_tier": $e');
    }

    try {
      final rows = await client
          .from('app_config')
          .select('key, value')
          .eq('key', 'web_checkout_url')
          .maybeSingle();
      final url = (rows?['value'] as String?)?.trim();
      // Only accept an https URL. A malformed or http row must not become the
      // destination of a payment handoff.
      if (url != null && url.startsWith('https://') && url != _checkoutUrl) {
        _checkoutUrl = url;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('PlanService: using built-in checkout URL: $e');
    }
  }
}

/// Feature keys shared with `public.plan_limit()` in the database.
abstract final class PlanFeature {
  static const foTrades = 'fo_trades_month';
  static const autopsy = 'autopsy_month';
  static const whatIf = 'whatif_day';
  static const priceAlerts = 'price_alerts';
  static const watchlists = 'watchlists';
  static const watchlistSymbols = 'watchlist_symbols';
  static const historyDays = 'history_days';
  static const chartDays = 'chart_days';
}

/// A request the server refused because the plan's allowance is used up.
///
/// Raised from place-order's `code: plan_limit` reply and from database
/// triggers whose message starts `PLAN_LIMIT:<feature>:<limit>`.
class PlanLimitException implements Exception {
  final String feature;
  final String message;
  final int? limit;
  const PlanLimitException(this.feature, this.message, {this.limit});

  /// Recognises a plan-limit refusal inside any error, or returns null.
  static PlanLimitException? from(Object error) {
    if (error is PlanLimitException) return error;
    final text = error is PostgrestException ? error.message : '$error';
    final m = RegExp(r'PLAN_LIMIT:([a-z_]+):(\d+)').firstMatch(text);
    if (m == null) return null;
    final feature = m.group(1)!;
    final limit = int.tryParse(m.group(2)!);
    return PlanLimitException(feature, defaultMessage(feature, limit), limit: limit);
  }

  static String defaultMessage(String feature, int? limit) => switch (feature) {
        PlanFeature.priceAlerts => 'Free accounts can keep $limit active price alerts. Upgrade to Pro for unlimited alerts.',
        PlanFeature.watchlists => 'Free accounts get $limit watchlist. Upgrade to Pro for as many lists as you like.',
        PlanFeature.watchlistSymbols => 'Free watchlists hold $limit symbols. Upgrade to Pro for unlimited symbols.',
        PlanFeature.foTrades => 'You have used all $limit F&O trades this month. Upgrade for more.',
        PlanFeature.autopsy => 'Free accounts get $limit trade autopsies a month. Upgrade to Pro for unlimited.',
        PlanFeature.whatIf => 'Free accounts get $limit What-If simulation a day. Upgrade to Pro for unlimited.',
        _ => 'This is a Pro feature. Upgrade to unlock it.',
      };

  @override
  String toString() => message;
}

/// One purchasable thing, straight from the `plan_catalogue` table.
///
/// Nothing here is hardcoded in Dart. The previous version of the subscribe
/// screen held its own price list, which then disagreed with the web app and the
/// database — three copies, and the two that were not the database were wrong.
class PlanOption {
  final String sku;
  final String tier;
  final String kind;
  final String title;
  final int pricePaise;

  /// The dollar price in cents, for accounts billed outside India. Null for a SKU
  /// that has no dollar price yet, which is why [priceLabel] falls back rather
  /// than printing `$0`.
  final int? priceUsdCents;

  final String? billingInterval;
  final double cashGrant;
  final double monthlyStipend;

  /// The pre-sale price, set only while a sale is running. Shown struck through
  /// next to [priceLabel]; the charge is always the plain price.
  final int? compareAtPaise;
  final int? compareAtUsdCents;
  final DateTime? saleEndsAt;

  const PlanOption({
    required this.sku,
    required this.tier,
    required this.kind,
    required this.title,
    required this.pricePaise,
    required this.priceUsdCents,
    required this.billingInterval,
    required this.cashGrant,
    required this.monthlyStipend,
    this.compareAtPaise,
    this.compareAtUsdCents,
    this.saleEndsAt,
  });

  bool get isSubscription => kind == 'subscription';

  /// A prepaid 7-day Pro pass (₹1 trial week or ₹29 week), not a running plan.
  bool get isWeekPass => billingInterval == 'weekly';

  bool get onSale => compareAtPaise != null;

  /// The old price, struck through by callers, or null when not on sale.
  String? wasPriceLabel(Currency billing) {
    final minor = chargedIn(billing) == Currency.usd ? compareAtUsdCents : compareAtPaise;
    return minor == null ? null : _formatMinor(minor, chargedIn(billing).symbol);
  }

  /// Rupees, for display. Prices are held in paise so no money is ever a double
  /// in transit; this is the only place it becomes one, and only to be printed.
  double get priceRupees => pricePaise / 100;

  /// The currency this plan will actually be charged in, for an account whose
  /// billing currency is [billing].
  ///
  /// Falls back to rupees when a SKU has no dollar price, matching
  /// `create-payment-order`, which refuses to sell it in that currency rather than
  /// inventing an amount. Callers must route every price figure through this so a
  /// price and its converted equivalent can never disagree about which currency
  /// they are talking about.
  Currency chargedIn(Currency billing) =>
      billing == Currency.usd && priceUsdCents != null
          ? Currency.usd
          : Currency.inr;

  /// The amount charged, in minor units of [chargedIn].
  int chargedMinor(Currency billing) =>
      chargedIn(billing) == Currency.usd ? priceUsdCents! : pricePaise;

  /// The exact amount that will be charged, formatted in [billing].
  ///
  /// Deliberately **not** routed through [Money]. `Money.wallet` converts a stored
  /// rupee figure at the live FX rate, which is right for a wallet balance and
  /// wrong for a price: it printed `$1.69` for a plan Razorpay charges `$2` for,
  /// because ₹149 at 88/USD is 1.69. The rupee and dollar prices are independent
  /// price points, each fixed to match its own Razorpay plan, so each is shown as
  /// itself and never converted.
  ///
  /// A user whose *display* currency differs from this sees the converted
  /// equivalent as a secondary `≈` line, built in the subscribe screen. That is a
  /// separate figure on purpose: this one is the invoice.
  String priceLabel(Currency billing) =>
      _formatMinor(chargedMinor(billing), chargedIn(billing).symbol);

  /// `199` → `₹199`, `249` → `$2.49`, `200` → `$2`. Cents are shown only when
  /// there are any: every rupee price is whole, most dollar ones are not.
  static String _formatMinor(int minor, String symbol) {
    final major = minor / 100;
    final whole = major == major.roundToDouble();
    return '$symbol${major.toStringAsFixed(whole ? 0 : 2)}';
  }

  factory PlanOption.fromJson(Map<String, dynamic> json) => PlanOption(
        sku: json['sku'] as String,
        tier: json['tier'] as String,
        kind: json['kind'] as String,
        title: json['title'] as String,
        pricePaise: (json['price_paise'] as num).toInt(),
        priceUsdCents: (json['price_usd_cents'] as num?)?.toInt(),
        billingInterval: json['billing_interval'] as String?,
        cashGrant: (json['cash_grant'] as num?)?.toDouble() ?? 0,
        monthlyStipend: (json['monthly_stipend'] as num?)?.toDouble() ?? 0,
        compareAtPaise: (json['compare_at_paise'] as num?)?.toInt(),
        compareAtUsdCents: (json['compare_at_usd_cents'] as num?)?.toInt(),
        saleEndsAt: DateTime.tryParse(json['sale_ends_at'] as String? ?? '')?.toLocal(),
      );
}

/// Checkout session returned by `create-payment-order` for native in-app
/// Razorpay Checkout (`razorpay_flutter`) with a hosted fallback URL.
class PaymentSession {
  final String sku;
  final String kind;
  final String keyId;
  final String? orderId;
  final String? subscriptionId;
  final bool isPrepaidOrder;
  final String title;
  final String currency;
  final int amountPaise;
  final String? prefillEmail;
  final String? prefillName;
  final String? prefillContact;
  final String? hostedUrl;

  const PaymentSession({
    required this.sku,
    required this.kind,
    required this.keyId,
    required this.orderId,
    required this.subscriptionId,
    required this.isPrepaidOrder,
    required this.title,
    required this.currency,
    required this.amountPaise,
    required this.prefillEmail,
    required this.prefillName,
    required this.prefillContact,
    required this.hostedUrl,
  });

  factory PaymentSession.fromJson(String sku, Map<String, dynamic> json) {
    final prefill = json['prefill'] is Map
        ? Map<String, dynamic>.from(json['prefill'] as Map)
        : const <String, dynamic>{};
    return PaymentSession(
      sku: sku,
      kind: (json['kind'] as String?) ?? 'one_time',
      keyId: (json['keyId'] as String?) ?? '',
      orderId: json['orderId'] as String?,
      subscriptionId: json['subscriptionId'] as String?,
      isPrepaidOrder: json['isPrepaidOrder'] == true,
      title: (json['title'] as String?) ?? 'Trading Titans',
      currency: (json['currency'] as String?) ?? 'INR',
      amountPaise: (json['amountPaise'] as num?)?.toInt() ?? 0,
      prefillEmail: prefill['email'] as String?,
      prefillName: prefill['name'] as String?,
      prefillContact: prefill['contact'] as String?,
      hostedUrl: (json['url'] as String?)?.trim(),
    );
  }
}
