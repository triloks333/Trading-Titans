import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme.dart';
import '../../core/currency.dart';
import '../../core/money.dart';
import '../../services/auth_service.dart';
import '../../services/app_flags_service.dart';
import '../../services/currency_service.dart';
import '../../services/plan_service.dart';
import '../../services/supabase_service.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_state.dart';
import '../../widgets/plan_badge.dart';

/// Plans and top-ups, as the app shows them.
///
/// Two things are worth knowing before changing anything here.
///
/// **The app takes no payments.** Tapping a plan asks the server to open a
/// checkout, then opens the page it returns. Nothing in this file, and nothing
/// anywhere in the APK, handles a card, a price or an entitlement. That keeps card
/// data out of the app entirely and means a compromised client cannot grant itself
/// anything — access is granted only by the `razorpay-webhook` edge function after
/// it verifies a signature from Razorpay.
///
/// This used to open the web app's plans page, which meant signing in a second
/// time before you could buy anything. It now goes to a login-free checkout page
/// (`web/public/pay.html`); see `SupabaseService.startHostedCheckout`.
///
/// **No price is written down in Dart.** Everything on screen comes from the
/// `plan_catalogue` table. The version of this screen that this replaced held its
/// own hardcoded list of Play Console products at ₹199/₹599/₹999, which had
/// already drifted from both the database and the web app. One copy, in the
/// database, is the whole point.
///
/// **Prices are shown in the billing currency, not the display currency.** Both
/// are read from the same profile, but they answer different questions: the
/// display preference is cosmetic, residency decides who Razorpay charges in
/// what. See `PlanOption.priceLabel`.
class SubscribeScreen extends StatefulWidget {
  const SubscribeScreen({super.key});

  @override
  State<SubscribeScreen> createState() => _SubscribeScreenState();
}

class _SubscribeScreenState extends State<SubscribeScreen> {
  late Future<List<PlanOption>> _plans;

  /// The SKU whose checkout is being opened, so its button can show a spinner and
  /// every other one can be disabled. Opening a checkout is now a server round
  /// trip, and two taps would create two orders.
  String? _busySku;

  @override
  void initState() {
    super.initState();
    _plans = SupabaseService().getPlanCatalogue();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final plan = context.watch<PlanService>();
    // Watched, not read: the price on every card depends on it, and it arrives
    // from the server a moment after the first frame.
    final billing = context.watch<CurrencyService>().billingCurrency;
    final wallet = auth.user?.walletBalance ?? 0;

    // Defence in depth: the entry points are already hidden when monetization
    // is off, but a stale route or a deep link must not reach the paywall.
    if (!context.watch<AppFlagsService>().monetizationEnabled) {
      return Scaffold(
        appBar: _bar(),
        body: EmptyState(
          icon: Icons.volunteer_activism_rounded,
          title: 'Everything is free',
          message:
              'Trading Titans is completely free right now — there is nothing to buy. '
              'Earn extra demo cash by completing challenges instead.',
        ),
      );
    }

    return Scaffold(
      appBar: _bar(),
      body: FutureBuilder<List<PlanOption>>(
        future: _plans,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return ErrorState(
              message: "We couldn't load the plans. Check your connection and try again.",
              onRetry: () => setState(() {
                _plans = SupabaseService().getPlanCatalogue();
              }),
            );
          }

          final all = snapshot.data ?? const <PlanOption>[];
          // Monthly only in the app. Showing all four subscriptions plus three
          // top-ups made a seven-card wall that nobody reads, and the annual/
          // monthly choice needs a side-by-side comparison to make sense — which
          // is what the website's toggle gives it. Annual is still sold, just not
          // from here.
          final subscriptions = all
              .where((p) => p.isSubscription && p.billingInterval == 'monthly')
              .toList();
          final hasAnnual = all
              .any((p) => p.isSubscription && p.billingInterval == 'annual');
          final topups = all.where((p) => !p.isSubscription).toList();

          return ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Current balance',
                            style: GoogleFonts.inter(color: AppColors.ink4, fontSize: 13)),
                        const SizedBox(height: AppSpacing.xs),
                        Text(Money.wallet(wallet),
                            style: GoogleFonts.inter(
                                fontSize: 28, fontWeight: FontWeight.bold, color: AppColors.ink)),
                      ],
                    ),
                  ),
                  if (plan.isPaid) PlanBadge(tier: plan.tier),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),

              // Shown only when the display preference and the billing currency
              // disagree, which is nine live accounts: in India, so charged in
              // rupees, but reading the app in dollars. Every price below then
              // carries an `≈` line in their currency, and this says which of the
              // two numbers is the real one.
              if (billing != Money.display) ...[
                Text(
                  'Charges are in ${billing.label}s.'
                  '${Money.rate == null ? '' : ' Amounts marked \u2248 are '
                      'today\u2019s approximate equivalent in '
                      '${Money.display.label}s.'}',
                  style: GoogleFonts.inter(fontSize: 12, color: AppColors.ink4),
                ),
                const SizedBox(height: AppSpacing.md),
              ],

              if (subscriptions.isNotEmpty) ...[
                _sectionTitle('Monthly plans'),
                Text(
                  'Renews every month until you cancel. '
                  '${billing == Currency.usd ? 'Taxes' : 'GST'} included, and no '
                  'adverts on any plan.',
                  style: GoogleFonts.inter(fontSize: 12, color: AppColors.ink4),
                ),
                const SizedBox(height: AppSpacing.md),
                for (final p in subscriptions) ...[
                  _subscriptionCard(p, billing, isCurrent: plan.tier == p.tier),
                  const SizedBox(height: AppSpacing.sm),
                ],
                if (hasAnnual) _annualNote(),
                const SizedBox(height: AppSpacing.lg),
              ],

              if (topups.isNotEmpty) ...[
                _sectionTitle('One-time top-ups'),
                Text('A single purchase — credited once, not a subscription.',
                    style: GoogleFonts.inter(fontSize: 12, color: AppColors.ink4)),
                const SizedBox(height: AppSpacing.md),
                for (final p in topups) ...[
                  _topUpRow(p, billing),
                  const SizedBox(height: AppSpacing.sm),
                ],
              ],

              const SizedBox(height: AppSpacing.lg),
              Text(
                'Demo cash has no monetary value, cannot be withdrawn and cannot be '
                'exchanged for anything outside Trading Titans. Payments open in your '
                'browser and are processed by Razorpay — the app never sees your card '
                'details.',
                style: GoogleFonts.inter(fontSize: 11, color: AppColors.ink5, height: 1.5),
              ),
            ],
          );
        },
      ),
    );
  }

  AppBar _bar() => AppBar(
        title: const Text('Plans & top-ups'),
        backgroundColor: AppColors.parchment,
        centerTitle: false,
      );

  /// The charge expressed in the user's *display* currency, for the `≈` line
  /// beside the price — `≈ $1.69` under `₹149`.
  ///
  /// This is what a dollar-reading account in India was missing: the price tag
  /// showed rupees, correctly, but nothing on the screen spoke their currency.
  /// Leading with the rupee figure and putting the dollar one beside it keeps the
  /// invoice unambiguous, which converting the price outright would not: Razorpay
  /// charges ₹149, and a lone "$1.69" would be a number that appears on no
  /// invoice anywhere.
  ///
  /// Returns null when there is nothing to add — the display currency already is
  /// the charged one — and when no exchange rate has loaded. That second guard
  /// matters: [FxConverter] returns its input unchanged without a usable rate, so
  /// this would otherwise render ₹149 as "$149".
  String? _approx(PlanOption product, Currency billing) {
    final charged = product.chargedIn(billing);
    if (Money.display == charged || Money.rate == null) return null;
    final major = product.chargedMinor(billing) / 100;
    return '\u2248 ${Money.from(major, charged, decimals: 2)}';
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.xs),
        child: Text(text,
            style: GoogleFonts.inter(
                fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.ink)),
      );

  /// Where annual pricing lives.
  ///
  /// A line rather than four more cards. Annual only means something next to the
  /// monthly price it is being compared against, and that comparison belongs on
  /// the page that can show both at once.
  Widget _annualNote() => Padding(
        padding: const EdgeInsets.only(top: AppSpacing.xs),
        child: GestureDetector(
          onTap: _openAnnualPlans,
          child: Row(
            children: [
              Icon(Icons.savings_outlined, size: 15, color: AppColors.ink4),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Paying yearly costs less — compare on our website',
                  style: GoogleFonts.inter(fontSize: 12, color: AppColors.ink4),
                ),
              ),
              Icon(Icons.open_in_new_rounded, size: 14, color: AppColors.ink4),
            ],
          ),
        ),
      );

  /// One monthly plan. Name and price on one line, the two things it actually
  /// gives you underneath, one action.
  Widget _subscriptionCard(
    PlanOption product,
    Currency billing, {
    required bool isCurrent,
  }) {
    final isTitan = product.tier == 'titan';
    final accent = isTitan ? AppColors.violet : AppColors.imperialGold;
    final busy = _busySku == product.sku;
    final blocked = isCurrent || (_busySku != null && !busy);
    final approx = _approx(product, billing);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.pureWhite,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: isTitan ? AppColors.violet : AppColors.birch),
      ),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Text(product.title,
                        style: GoogleFonts.inter(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: AppColors.ink)),
                    if (isCurrent) ...[
                      const SizedBox(width: AppSpacing.sm),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: AppCard.badge(AppColors.bullLight),
                        child: Text('CURRENT',
                            style: GoogleFonts.inter(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: AppColors.bull,
                                letterSpacing: 0.5)),
                      ),
                    ],
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(product.priceLabel(billing),
                      style: GoogleFonts.inter(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: AppColors.ink)),
                  Text(
                      approx == null ? 'per month' : 'per month · $approx',
                      style: GoogleFonts.inter(fontSize: 10, color: AppColors.ink5)),
                ],
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _perk('${Money.wallet(product.monthlyStipend)} demo cash every month', accent),
          const SizedBox(height: 6),
          _perk('Futures & options trading', accent),
          const SizedBox(height: 6),
          _perk('${product.tier.toUpperCase()} badge on your profile', accent),
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: blocked || busy ? null : () => _openCheckout(product),
              style: ElevatedButton.styleFrom(
                backgroundColor: accent,
                disabledBackgroundColor: AppColors.cream,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md)),
              ),
              child: busy
                  ? SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.pureWhite),
                    )
                  : Text(
                      isCurrent ? 'Your current plan' : 'Get ${product.title}',
                      style: GoogleFonts.inter(
                          fontSize: 14,
                          color: blocked ? AppColors.ink4 : AppColors.pureWhite,
                          fontWeight: FontWeight.w700),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _perk(String text, Color accent) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.check_circle_rounded, size: 15, color: accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: GoogleFonts.inter(fontSize: 13, color: AppColors.ink3)),
          ),
        ],
      );

  /// A top-up is one number and one price, so it gets one row instead of a card.
  /// Three of these used to be three tall cards, which is most of why this screen
  /// read as a wall.
  Widget _topUpRow(PlanOption product, Currency billing) {
    final busy = _busySku == product.sku;
    final approx = _approx(product, billing);

    return Material(
      color: AppColors.pureWhite,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: _busySku != null ? null : () => _openCheckout(product),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: AppColors.birch),
          ),
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg, vertical: AppSpacing.md),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(Money.wallet(product.cashGrant),
                        style: GoogleFonts.inter(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: AppColors.ink)),
                    Text('${product.title} · one-time',
                        style: GoogleFonts.inter(fontSize: 11, color: AppColors.ink5)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(product.priceLabel(billing),
                      style: GoogleFonts.inter(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink)),
                  if (approx != null)
                    Text(approx,
                        style: GoogleFonts.inter(
                            fontSize: 10, color: AppColors.ink5)),
                ],
              ),
              const SizedBox(width: 6),
              if (busy)
                const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Icon(Icons.chevron_right_rounded, size: 20, color: AppColors.ink4),
            ],
          ),
        ),
      ),
    );
  }

  /// Opens a checkout for this product on Razorpay's own hosted page.
  ///
  /// The SKU is the entire request. Currency comes from the account's residency
  /// and the price from `plan_catalogue`, both resolved server-side, so there is
  /// nothing here a tampered client could change about what it costs.
  ///
  /// Two failures matter and are handled differently. The server refusing (already
  /// subscribed, a checkout already in flight, plan withdrawn) has a message
  /// written for a user to read, so it is shown verbatim. The browser failing to
  /// open is our problem, and has to say so rather than leave someone staring at a
  /// button that did nothing.
  Future<void> _openCheckout(PlanOption product) async {
    if (_busySku != null) return;

    // A guest account cannot be recovered after sign-out, so a purchase made on
    // one would disappear with it. Stop before the money, not after. The server
    // refuses guests too; this is so the refusal is instant and readable.
    if (context.read<AuthService>().isGuest) {
      _tell('Please make your account permanent first — a guest account cannot be '
          'recovered, and a purchase on it would be lost.');
      return;
    }

    setState(() => _busySku = product.sku);
    try {
      final url = await SupabaseService().startHostedCheckout(product.sku);
      final uri = Uri.parse(url);

      bool launched;
      try {
        launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {
        launched = false;
      }
      if (!mounted) return;
      if (!launched) {
        // The link is live either way, so give it to them rather than losing the
        // checkout we just created.
        _tell('We could not open your browser. Open this link to pay: $url');
        return;
      }

      // The purchase completes on Razorpay's page and is granted by the webhook,
      // so there is nothing to await here. Refreshing on return is what makes the
      // new plan and balance appear.
      _tell('Finish the payment in your browser, then come back — your plan will '
          'appear here within a minute.');
    } catch (e) {
      if (!mounted) return;
      _tell(_readable(e));
    } finally {
      if (mounted) setState(() => _busySku = null);
    }
  }

  /// Strips Dart's `Exception: ` prefix, which the server messages do not need.
  String _readable(Object e) =>
      e.toString().replaceFirst(RegExp(r'^(Exception|_Exception):\s*'), '');

  /// Annual pricing needs a side-by-side comparison against monthly to mean
  /// anything, and that lives on the website's plans page rather than here.
  Future<void> _openAnnualPlans() async {
    final base = PlanService.instance.checkoutUrl;
    final uri = Uri.tryParse(base);
    if (uri == null) {
      _tell('We could not open the plans page. Please try again later.');
      return;
    }
    bool launched;
    try {
      launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      launched = false;
    }
    if (!mounted) return;
    if (!launched) _tell('We could not open your browser. See $base');
  }

  void _tell(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.inter(fontSize: 13)),
        duration: const Duration(seconds: 6),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
