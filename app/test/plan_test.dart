// The plan badge and the catalogue parsing.
//
// Both are small, and both are the kind of small that matters: the badge decides
// who is publicly shown as a paying customer, and the parser decides what a plan
// costs on screen. A wrong answer in either is visible to every user.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/currency.dart';
import 'package:mobile/core/money.dart';
import 'package:mobile/services/currency_service.dart';
import 'package:mobile/services/plan_service.dart';
import 'package:mobile/widgets/plan_badge.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('PlanBadge', () {
    testWidgets('shows nothing for a free user', (tester) async {
      await tester.pumpWidget(_wrap(const PlanBadge(tier: 'free')));
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('shows nothing for an absent or unknown tier', (tester) async {
      // Guards the leaderboard path in particular: when the tier lookup fails
      // every row arrives as null, and that must render a clean board rather
      // than a row of blank or mislabelled pills.
      await tester.pumpWidget(_wrap(const PlanBadge(tier: null)));
      expect(find.byType(Text), findsNothing);

      await tester.pumpWidget(_wrap(const PlanBadge(tier: 'free_starter')));
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('labels pro and titan distinctly', (tester) async {
      await tester.pumpWidget(_wrap(const PlanBadge(tier: 'pro')));
      expect(find.text('PRO'), findsOneWidget);

      await tester.pumpWidget(_wrap(const PlanBadge(tier: 'titan')));
      expect(find.text('TITAN'), findsOneWidget);
      expect(find.text('PRO'), findsNothing);
    });
  });

  group('PlanOption', () {
    test('parses a subscription row and converts paise to rupees', () {
      final p = PlanOption.fromJson({
        'sku': 'pro_monthly',
        'tier': 'pro',
        'kind': 'subscription',
        'title': 'Pro Monthly',
        'price_paise': 14900,
        'billing_interval': 'monthly',
        'cash_grant': 0,
        'monthly_stipend': 50000,
      });

      expect(p.isSubscription, true);
      // 14900 paise is ₹149, not ₹14,900. Getting this wrong by a factor of 100
      // is the single most expensive mistake available on this screen.
      expect(p.priceRupees, 149.0);
      expect(p.monthlyStipend, 50000);
      expect(p.billingInterval, 'monthly');
    });

    test('parses a one-time top-up row', () {
      final p = PlanOption.fromJson({
        'sku': 'topup_max',
        'tier': 'topup',
        'kind': 'one_time',
        'title': 'Max',
        'price_paise': 99900,
        'billing_interval': null,
        'cash_grant': 1000000,
        'monthly_stipend': 0,
      });

      expect(p.isSubscription, false);
      expect(p.priceRupees, 999.0);
      expect(p.cashGrant, 1000000);
      expect(p.billingInterval, isNull);
    });

    test('survives a row with the numeric columns absent', () {
      // `cash_grant` and `monthly_stipend` are NOT NULL in the table, but a
      // narrowed select would omit them, and a crash on the plans screen is a
      // worse outcome than a zero.
      final p = PlanOption.fromJson({
        'sku': 'x',
        'tier': 'pro',
        'kind': 'subscription',
        'title': 'X',
        'price_paise': 100,
        'billing_interval': 'monthly',
      });

      expect(p.cashGrant, 0);
      expect(p.monthlyStipend, 0);
      expect(p.priceRupees, 1.0);
    });
  });

  group('PlanOption.priceLabel', () {
    // The whole point of these: the price shown has to be the price Razorpay
    // charges. Routing a dollar plan through the FX converter printed $1.69 for a
    // plan billed at $2, because ₹149 at 88/USD is 1.69 — a number that appears
    // nowhere in Razorpay and cannot be honoured.
    PlanOption plan({required int paise, int? cents}) => PlanOption.fromJson({
          'sku': 'x',
          'tier': 'pro',
          'kind': 'subscription',
          'title': 'X',
          'price_paise': paise,
          'price_usd_cents': cents,
          'billing_interval': 'monthly',
        });

    test('shows the dollar price to a dollar-billed account, unconverted', () {
      final p = plan(paise: 14900, cents: 200);
      expect(p.priceLabel(Currency.usd), '\$2');
      expect(p.priceLabel(Currency.inr), '\u20b9149');
    });

    test('keeps cents when there are any, drops them when there are not', () {
      expect(plan(paise: 19900, cents: 249).priceLabel(Currency.usd), '\$2.49');
      expect(plan(paise: 599900, cents: 6400).priceLabel(Currency.usd), '\$64');
    });

    test('falls back to rupees when a SKU has no dollar price', () {
      // create-payment-order refuses to sell such a SKU in USD, so a "\$0" label
      // would advertise something unbuyable.
      final p = plan(paise: 14900, cents: null);
      expect(p.priceLabel(Currency.usd), '\u20b9149');
      // The fallback has to be visible to callers too, or the "approximately"
      // line beside the price would convert from the wrong currency.
      expect(p.chargedIn(Currency.usd), Currency.inr);
      expect(p.chargedMinor(Currency.usd), 14900);
    });

    test('reports the currency and minor amount actually charged', () {
      final p = plan(paise: 14900, cents: 200);
      expect(p.chargedIn(Currency.usd), Currency.usd);
      expect(p.chargedMinor(Currency.usd), 200);
      expect(p.chargedIn(Currency.inr), Currency.inr);
      expect(p.chargedMinor(Currency.inr), 14900);
    });
  });

  group('the approximate line beside a price', () {
    // Nine live accounts are in India (charged in rupees) but read the app in
    // dollars. They need to see a dollar figure without it replacing the rupee
    // one, because Razorpay charges the rupee one.
    final p = PlanOption.fromJson({
      'sku': 'pro_monthly',
      'tier': 'pro',
      'kind': 'subscription',
      'title': 'Pro Monthly',
      'price_paise': 14900,
      'price_usd_cents': 200,
      'billing_interval': 'monthly',
    });

    test('converts the charged amount, not the other currency price point', () {
      Money.serviceForTesting(_Stub(TradingLocation.india, Currency.usd, 88));
      // Charged Rs 149, so the approximation is Rs 149 at today's rate. NOT the
      // \$2 US price point, which is a different product price for a different
      // market and would understate nothing but confuse everything.
      expect(Money.from(p.chargedMinor(Currency.inr) / 100, Currency.inr,
          decimals: 2), '\$1.69');
    });

    test('no rate means no approximation, never a mislabelled one', () {
      // FxConverter returns its input unchanged without a usable rate, so an
      // unguarded call renders Rs 149 as "\$149". The screen checks Money.rate
      // first; this pins the signal it checks.
      Money.serviceForTesting(_Stub(TradingLocation.india, Currency.usd, 0));
      expect(Money.rate, isNull);
      expect(Money.from(149, Currency.inr, decimals: 2), '\$149.00',
          reason: 'the unguarded value really is this wrong');
    });

    tearDown(() =>
        Money.serviceForTesting(_Stub(null, Currency.inr, 88)));
  });

  group('CurrencyService.billingCurrency', () {
    // Residency, not the display preference. Eight live accounts are in India
    // with a dollar display; billing them in dollars because of a cosmetic
    // setting would charge them the wrong price in the wrong currency.
    test('follows location and ignores the display currency', () {
      expect(_Stub(null, Currency.usd, 88).billingCurrency, Currency.inr,
          reason: 'a null location predates the question and means India');
      expect(_Stub(TradingLocation.india, Currency.usd, 88).billingCurrency,
          Currency.inr,
          reason: 'a dollar display must not move billing off rupees');
      expect(
          _Stub(TradingLocation.outsideIndia, Currency.inr, 88).billingCurrency,
          Currency.usd,
          reason: 'residency alone decides, even with a rupee display');
      expect(
          _Stub(TradingLocation.outsideIndia, Currency.usd, 88).billingCurrency,
          Currency.usd);
    });
  });
}

/// Overrides only what these tests read, so nothing touches SharedPreferences or
/// Supabase. Doubles as the service behind [Money], which needs the display
/// currency and the rate.
class _Stub extends CurrencyService {
  _Stub(this._location, this._display, this._rate) : super.forTesting();

  final TradingLocation? _location;
  final Currency _display;
  final double _rate;

  @override
  TradingLocation? get location => _location;

  @override
  Currency get displayCurrency => _display;

  @override
  double get usdInr => _rate;
}
