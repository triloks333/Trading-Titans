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

  Future<void> refresh() async {
    final client = Supabase.instance.client;

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
  });

  bool get isSubscription => kind == 'subscription';

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
