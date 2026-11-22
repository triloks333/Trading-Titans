import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme.dart';
import '../../core/currency.dart';
import '../../core/money.dart';
import '../../services/auth_service.dart';
import '../../services/app_flags_service.dart';
import '../../services/currency_service.dart';
import '../../services/plan_service.dart';
import '../../services/supabase_service.dart';
import '../../services/theme_service.dart';
import '../../widgets/auth_kit.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_state.dart';
import '../../services/churn_telemetry_service.dart';

/// Plans and top-ups, presented with a clean segmented view.
///
/// Tab 0: VIP Mentorship Plans (Titan Pro ₹999 with 1-on-1 Founder Mentorship, Pro Monthly).
/// Tab 1: One-time Demo Capital Top-Ups (Instant ₹10L, ₹5L, ₹1L non-expiring cash packs).
class SubscribeScreen extends StatefulWidget {
  final int initialTabIndex;

  /// The catalogue to show instead of fetching it (tests).
  final List<PlanOption>? catalogue;

  /// A plan to preselect, e.g. `pro_trial_week` from the upgrade sheet.
  final String? initialSku;

  const SubscribeScreen({
    super.key,
    this.initialTabIndex = 0,
    this.catalogue,
    this.initialSku,
  });

  @override
  State<SubscribeScreen> createState() => _SubscribeScreenState();
}

class _SubscribeScreenState extends State<SubscribeScreen> {
  static const String _phonePrefKey = 'tt_checkout_phone_v1';

  late Future<List<PlanOption>> _plans;
  late int _selectedTab;
  String _billingInterval = 'monthly';

  /// The plan the footer will buy; null picks a sensible default per tab.
  String? _selectedSku;

  /// The SKU whose checkout is being opened, so its button can show a spinner and
  /// every other one can be disabled.
  String? _busySku;

  Razorpay? _razorpay;
  PaymentSession? _activeSession;
  PlanOption? _activeProduct;
  String? _savedPhone;

  /// Open downshift offers by SKU (from intel_my_offers / intel_request_offer).
  final Map<String, Map<String, dynamic>> _offers = {};
  String? _lastViewedSku;

  /// Viewing the first pack, then the second, without buying earns a real
  /// discount on the second; the server decides and records it.
  static const _downshifts = {
    ('topup_max', 'topup_plus'), ('topup_plus', 'topup_boost'),
    ('titan_annual', 'titan_monthly'), ('titan_monthly', 'pro_monthly'),
  };

  @override
  void initState() {
    super.initState();
    _selectedTab = widget.initialTabIndex.clamp(0, 1);
    _selectedSku = widget.initialSku;
    if (widget.initialSku?.startsWith('topup') == true) _selectedTab = 1;
    if (widget.initialSku?.endsWith('_annual') == true) _billingInterval = 'annual';
    _plans = widget.catalogue != null ? Future.value(widget.catalogue!) : (SupabaseService().getPlanCatalogue()..ignore());
    _initRazorpay();
    _loadSavedPhone();
    _loadOffers();
  }

  Future<void> _loadOffers() async {
    try {
      final res = await SupabaseService().client.rpc('intel_my_offers');
      if (res is! List || !mounted) return;
      setState(() {
        for (final o in res.whereType<Map>()) {
          _offers['${o['sku']}'] = Map<String, dynamic>.from(o);
        }
      });
    } catch (_) {}
  }

  /// Called on every pack tap; asks for an offer when the tap is a downshift.
  Future<void> _onPackViewed(String sku) async {
    final prev = _lastViewedSku;
    _lastViewedSku = sku;
    if (prev == null || !_downshifts.contains((prev, sku)) || _offers.containsKey(sku)) return;
    try {
      final res = await SupabaseService().client.rpc('intel_request_offer', params: {'p_from': prev, 'p_to': sku});
      if (res is! Map || !mounted) return;
      setState(() => _offers[sku] = Map<String, dynamic>.from(res));
      ChurnTelemetryService.instance.recordPaywallStep('offer_shown', sku: sku);
    } catch (_) {}
  }

  /// The offer's price in the billing currency, or null when it has none there.
  int? _offerMinor(PlanOption p, Currency billing) {
    final o = _offers[p.sku];
    if (o == null || ((o['pct'] as num?) ?? 0) <= 0) return null;
    final v = p.chargedIn(billing) == Currency.usd ? o['price_usd_cents'] : o['price_paise'];
    return (v as num?)?.round();
  }

  String _fmtMinor(int minor, Currency c) {
    final major = minor / 100;
    return '${c.symbol}${major.toStringAsFixed(major == major.roundToDouble() ? 0 : 2)}';
  }

  /// The offer banner: real percent, real price, real end time.
  Widget _offerBanner(Map<String, dynamic> o, PlanOption p, Currency billing) {
    final pct = (o['pct'] as num?)?.toInt() ?? 0;
    final price = _offerMinor(p, billing);
    if (pct <= 0 || price == null) return const SizedBox.shrink();
    final until = DateTime.tryParse('${pct == 50 ? o['stage2_at'] : o['expires_at']}')?.toLocal();
    final list = p.chargedMinor(billing);
    final when = until == null ? '' : ', until ${DateFormat('EEE d MMM, h:mm a').format(until)}';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: AppColors.bullLight, borderRadius: BorderRadius.circular(AppRadius.md)),
      child: Row(children: [
        Icon(Icons.sell_outlined, size: 20, color: AppColors.bull),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            '$pct% off ${p.title} for you: ${_fmtMinor(price, p.chargedIn(billing))} '
            '(was ${_fmtMinor(list, p.chargedIn(billing))})$when.',
            style: AppFonts.sans(size: 13, weight: FontWeight.w600, color: AppColors.ink),
          ),
        ),
      ]),
    );
  }

  void _initRazorpay() {
    if (kIsWeb || Platform.isIOS) return;
    try {
      final rzp = Razorpay();
      rzp.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handlePaymentSuccess);
      rzp.on(Razorpay.EVENT_PAYMENT_ERROR, _handlePaymentError);
      rzp.on(Razorpay.EVENT_EXTERNAL_WALLET, _handleExternalWallet);
      _razorpay = rzp;
    } catch (e) {
      debugPrint('SubscribeScreen: Razorpay init fallback: $e');
    }
  }

  Future<void> _loadSavedPhone() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final local = prefs.getString(_phonePrefKey)?.trim();
      if (local != null && local.isNotEmpty && mounted) {
        setState(() => _savedPhone = local);
      }
      final remote = await SupabaseService().getSavedPhoneNumber();
      if (remote != null && remote.isNotEmpty) {
        await prefs.setString(_phonePrefKey, remote);
        if (mounted) setState(() => _savedPhone = remote);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    try {
      _razorpay?.clear();
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final plan = context.watch<PlanService>();
    final billing = context.watch<CurrencyService>().billingCurrency;

    // Defence in depth: hidden when monetisation is off, and on iOS, where Apple
    // requires StoreKit for digital goods (Guideline 3.1.1).
    if (!context.watch<AppFlagsService>().monetizationEnabled || (!kIsWeb && Platform.isIOS)) {
      return Scaffold(
        body: SafeArea(
          child: Column(children: [
            _header(),
            Expanded(
              child: EmptyState(
                icon: Icons.school_rounded,
                title: 'Educational Mode',
                message: 'Trading Titans is completely free here. All simulation markets, real-time charts, options and '
                    'futures are unlocked. Earn more demo capital by completing challenges!',
              ),
            ),
          ]),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          _header(),
          Padding(padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, 12), child: _segmented()),
          Expanded(
            child: FutureBuilder<List<PlanOption>>(
              future: _plans,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
                if (snapshot.hasError) {
                  return ErrorState(
                    message: "We couldn't load the plans. Check your connection and try again.",
                    onRetry: () => setState(() {
                      _plans = SupabaseService().getPlanCatalogue()..ignore();
                    }),
                  );
                }
                final all = snapshot.data ?? const <PlanOption>[];
                final hasAnnual = all.any((p) => p.isSubscription && p.billingInterval == 'annual');
                final interval = hasAnnual && _billingInterval == 'annual' ? 'annual' : 'monthly';
                // The 7-day pass leads the list: the ₹1 first week while the account
                // qualifies, the ₹29 week after. Only one of the two is ever shown.
                final passSku = plan.trialEligible ? 'pro_trial_week' : 'pro_week';
                final pass = all.where((p) => p.sku == passSku).firstOrNull;
                final options = _selectedTab == 0
                    ? [
                        ?pass,
                        ...(all.where((p) => p.isSubscription && !p.isWeekPass && p.billingInterval == interval).toList()
                          ..sort((a, b) => a.pricePaise.compareTo(b.pricePaise))),
                      ]
                    : (all.where((p) => !p.isSubscription).toList()..sort((a, b) => a.pricePaise.compareTo(b.pricePaise)));
                // Default pick: the cheapest paid subscription the user does not have, or the first top-up.
                final selected = options.where((p) => p.sku == _selectedSku).firstOrNull ??
                    (_selectedTab == 0 ? options.where((p) => p.tier != plan.tier).firstOrNull : options.firstOrNull);
                return Column(children: [
                  Expanded(
                    child: ListView(padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, 12), children: [
                      if (plan.saleActive) _saleBanner(plan),
                      for (final p in options)
                        if (_offers[p.sku] != null) _offerBanner(_offers[p.sku]!, p, billing),
                      if (billing != Money.display) _currencyNote(billing),
                      if (_selectedTab == 0 && hasAnnual) _intervalToggle(),
                      if (_selectedTab == 0) _starterCard(plan),
                      if (options.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(AppSpacing.xl),
                          child: Text('Nothing on sale here right now.', textAlign: TextAlign.center, style: AppText.body),
                        ),
                      for (final p in options) _planCard(p, billing, selected: p.sku == selected?.sku, current: _isCurrent(p, plan)),
                      const SizedBox(height: 4),
                      Text(
                        'Demo cash is virtual and cannot be withdrawn. The 7-day pass is a one-time payment and does not renew. '
                        'Operated by Kashivwealth Management LLP.',
                        style: AppFonts.sans(size: 11, color: AppColors.ink4, height: 1.45),
                      ),
                      const SizedBox(height: 12),
                      _selectedTab == 0 ? _mentorshipFaqSection() : _topUpFaqSection(),
                    ]),
                  ),
                  _footer(selected, billing, plan),
                ]);
              },
            ),
          ),
        ]),
      ),
    );
  }

  Widget _header() => Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 10, AppSpacing.lg, 10),
        child: Row(children: [
          AuthIconButton(icon: Icons.arrow_back_rounded, label: 'Back', onTap: () => Navigator.of(context).maybePop()),
          const SizedBox(width: 10),
          Expanded(child: Text('Plans & top-ups', style: AppFonts.sans(size: 20, weight: FontWeight.w700, color: AppColors.ink))),
          ListenableBuilder(
            listenable: ThemeService(),
            builder: (_, _) => AuthIconButton(
              icon: AppColors.isDark ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
              label: 'Toggle light or dark theme',
              onTap: () {
                ChurnTelemetryService.instance.recordButtonTap('global_theme_dark_light_toggle');
                ThemeService().setThemeMode(AppColors.isDark ? ThemeMode.light : ThemeMode.dark);
              },
            ),
          ),
        ]),
      );

  Widget _segmented() => Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: AppColors.cream, borderRadius: BorderRadius.circular(AppRadius.md)),
        child: Row(children: [
          for (final (i, label) in const ['Subscriptions', 'Top-ups'].indexed) ...[
            if (i > 0) const SizedBox(width: 4),
            Expanded(
              child: Semantics(
                button: true,
                selected: _selectedTab == i,
                label: label,
                excludeSemantics: true,
                child: GestureDetector(
                  onTap: () {
                    ChurnTelemetryService.instance.recordButtonTap(i == 0 ? 'subscribe_seg_tab_0_subscriptions' : 'subscribe_seg_tab_1_topups');
                    if (_selectedTab == i) return;
                    HapticFeedback.selectionClick();
                    setState(() {
                      _selectedTab = i;
                      _selectedSku = null;
                    });
                  },
                  child: Container(
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _selectedTab == i ? AppColors.pureWhite : Colors.transparent,
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Text(label, style: AppFonts.sans(size: 13, weight: FontWeight.w600, color: _selectedTab == i ? AppColors.ink : AppColors.ink3)),
                  ),
                ),
              ),
            ),
          ],
        ]),
      );

  Widget _saleBanner(PlanService plan) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: AppColors.titanGoldSoft, borderRadius: BorderRadius.circular(AppRadius.md)),
        child: Row(children: [
          Icon(Icons.local_fire_department_outlined, size: 20, color: AppColors.titanGold),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Diwali sale: 50% off every pack${plan.saleEndsAt == null ? '' : ' · ends ${DateFormat('d MMM, h:mm a').format(plan.saleEndsAt!.toLocal())}'}',
              style: AppFonts.sans(size: 13, weight: FontWeight.w600, color: AppColors.titanGold),
            ),
          ),
        ]),
      );

  Widget _currencyNote(Currency billing) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.pureWhite,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.birch),
        ),
        child: Text(
          'Charges are in ${billing.label}s.'
          '${Money.rate == null ? '' : ' Amounts marked ≈ are today’s equivalent in ${Money.display.label}s.'}',
          style: AppFonts.mono(size: 11, color: AppColors.ink4),
        ),
      );

  Widget _intervalToggle() => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          for (final (i, (key, label)) in const [('monthly', 'Monthly'), ('annual', 'Annual')].indexed) ...[
            if (i > 0) const SizedBox(width: 6),
            Expanded(
              child: ChoiceChip(
                label: SizedBox(width: double.infinity, child: Text(label, textAlign: TextAlign.center)),
                selected: _billingInterval == key,
                showCheckmark: false,
                onSelected: (_) {
                  ChurnTelemetryService.instance.recordButtonTap('subscribe_interval_${key}_chip');
                  setState(() {
                    _billingInterval = key;
                    _selectedSku = null;
                  });
                },
              ),
            ),
          ],
        ]),
      );

  Widget _tag(String text, {bool gold = false}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: AppCard.badge(gold ? AppColors.titanGoldSoft : AppColors.cream),
        child: Text(text, style: AppText.badge.copyWith(color: gold ? AppColors.titanGold : AppColors.ink3)),
      );

  /// A selectable plan card: name and tag, radio, price (struck-through while on
  /// sale), and its features.
  Widget _card({
    required String name,
    required String tag,
    bool goldTag = false,
    required bool selected,
    required String price,
    required String per,
    Widget? was,
    String? approx,
    required List<String> features,
    VoidCallback? onTap,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Semantics(
          button: true,
          selected: selected,
          label: '$name, $price $per',
          child: Material(
            color: selected ? AppColors.goldPale : AppColors.pureWhite,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              side: BorderSide(color: selected ? AppColors.goldMid : AppColors.birch),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Text(name, style: AppFonts.sans(size: 17, weight: FontWeight.w700, color: AppColors.ink)),
                    const SizedBox(width: 8),
                    _tag(tag, gold: goldTag),
                    const Spacer(),
                    Container(
                      width: 22,
                      height: 22,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: selected ? AppColors.goldMid : AppColors.birch, width: 2)),
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(shape: BoxShape.circle, color: selected ? AppColors.goldMid : Colors.transparent),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 6),
                  Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 6, children: [
                    Text(price, style: AppFonts.mono(size: 24, weight: FontWeight.w600, color: AppColors.ink)),
                    Text(per, style: AppFonts.sans(size: 13, color: AppColors.ink4)),
                    ?was,
                    if (approx != null) Text(approx, style: AppFonts.sans(size: 11, color: AppColors.ink4)),
                  ]),
                  for (final f in features)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('✓', style: AppFonts.sans(size: 13, color: AppColors.bull)),
                        const SizedBox(width: 8),
                        Expanded(child: Text(f, style: AppFonts.sans(size: 13, color: AppColors.ink3))),
                      ]),
                    ),
                ]),
              ),
            ),
          ),
        ),
      );

  /// The free tier, so the current plan is always visible beside the paid ones.
  Widget _starterCard(PlanService plan) => _card(
        name: 'Starter',
        tag: plan.isPaid ? 'FREE' : 'CURRENT',
        selected: false,
        price: Money.wallet(0, decimals: 0),
        per: 'free',
        features: const ['Stocks, US, crypto and commodities paper trading', '3 F&O trades a month', '3 trade autopsies a month and 1 What-If a day', '7 days of history, 3 alerts, 1 watchlist of 10'],
      );

  /// Analytics ids for the plan cards; other skus (e.g. USD variants) record nothing.
  static const _cardIds = {
    'pro_monthly': 'pro_monthly_149',
    'pro_annual': 'pro_annual_1199',
    'titan_monthly': 'titan_monthly_799',
    'titan_annual': 'titan_annual_5999',
    'topup_mini': 'topup_mini_29',
    'pro_trial_week': 'pro_trial_week_1',
    'pro_week': 'pro_week_29',
    'topup_boost': 'topup_boost_199',
    'topup_plus': 'topup_plus_599',
    'topup_max': 'topup_max_999',
  };

  Widget _planCard(PlanOption p, Currency billing, {required bool selected, required bool current}) {
    final titan = p.tier == 'titan' || p.pricePaise >= 79900;
    final features = p.isWeekPass
        ? const [
            'Everything in Pro for 7 days',
            '25 F&O trades a month instead of 3',
            'Unlimited trade autopsies and What-If',
            'Full P&L history, all chart ranges, unlimited alerts and watchlists',
            'Weekly coach report, Pro league and follow top traders',
          ]
        : p.isSubscription
            ? [
                if (titan) 'Twice-weekly live 1-on-1 mentorship with founders (Wed & Sat)',
                titan ? 'Unlimited F&O trades' : '25 F&O trades a month (free: 3)',
                if (titan) 'Options strategy builder with payoff chart and one-tap basket orders',
                if (titan) 'Greeks and "what if NIFTY moves" risk panel',
                'Unlimited trade autopsies and What-If simulations',
                'Full P&L history, all chart ranges, unlimited alerts and watchlists',
                'Weekly coach report, ${titan ? 'Titan' : 'Pro'} league and follow top traders',
                if (p.monthlyStipend > 0) '${Money.wallet(p.monthlyStipend)} virtual capital added every month',
                '${p.tier.toUpperCase()} VIP badge across chat & leaderboards',
              ]
            : ['${Money.wallet(p.cashGrant)} demo cash added instantly', 'Never expires · usable for F&O trading'];
    final tag = current
        ? 'CURRENT'
        : p.isWeekPass
            ? (p.sku == 'pro_trial_week' ? 'FIRST WEEK ₹1' : '7 DAYS')
        : p.isSubscription
            ? (titan ? 'FLAGSHIP' : 'POPULAR')
            : p.pricePaise >= 99900
                ? 'BEST VALUE'
                : p.pricePaise >= 49900
                    ? 'PRO PACK'
                    : p.sku == 'topup_mini' || p.pricePaise <= 3000
                        ? 'TOP-UP'
                        : 'STARTER PACK';
    return _card(
      name: p.title,
      tag: tag,
      goldTag: !current && (titan || tag == 'POPULAR' || tag == 'BEST VALUE'),
      selected: selected,
      price: _offerMinor(p, billing) == null ? p.priceLabel(billing) : _fmtMinor(_offerMinor(p, billing)!, p.chargedIn(billing)),
      per: _per(p),
      was: _offerMinor(p, billing) != null
          ? Text(p.priceLabel(billing),
              style: AppFonts.mono(size: 13, color: AppColors.ink4).copyWith(decoration: TextDecoration.lineThrough))
          : p.onSale ? _wasPrice(p, billing) : null,
      approx: _approx(p, billing),
      features: features,
      onTap: current || _busySku != null ? null : () {
        final cardId = _cardIds[p.sku];
        if (cardId != null) ChurnTelemetryService.instance.recordButtonTap('subscribe_card_$cardId');
        ChurnTelemetryService.instance.recordPaywallPackView(p.sku);
        setState(() => _selectedSku = p.sku);
        _onPackViewed(p.sku);
      },
    );
  }

  String _per(PlanOption p) => p.isWeekPass
      ? 'for 7 days'
      : p.isSubscription
          ? (p.billingInterval == 'annual' ? 'per year' : 'per month')
          : 'one-time';

  /// Whether [p] is what the account already has. A running 7-day pass makes the
  /// pass "current" but never the monthly or annual plans, which stay buyable as
  /// the upgrade.
  bool _isCurrent(PlanOption p, PlanService plan) {
    if (!p.isSubscription) return false;
    if (p.isWeekPass) return plan.passEndsAt != null;
    return plan.tier == p.tier && plan.passEndsAt == null;
  }

  /// Selected plan and its price, then the pay button.
  Widget _footer(PlanOption? p, Currency billing, PlanService plan) {
    final busy = p != null && _busySku == p.sku;
    final current = p != null && _isCurrent(p, plan);
    return Container(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 12, AppSpacing.lg, 16),
      decoration: BoxDecoration(color: AppColors.pureWhite, border: Border(top: BorderSide(color: AppColors.birch))),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Expanded(
            child: Text(
              p == null ? 'Pick a plan' : '${p.title} · ${_per(p)}',
              style: AppFonts.sans(size: 13, color: AppColors.ink3),
            ),
          ),
          if (p != null)
            Text(_offerMinor(p, billing) == null ? p.priceLabel(billing) : _fmtMinor(_offerMinor(p, billing)!, p.chargedIn(billing)),
                style: AppFonts.mono(size: 13, weight: FontWeight.w600, color: AppColors.ink)),
        ]),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton.icon(
            onPressed: p == null || current || _busySku != null ? null : () => _openCheckout(p),
            icon: busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.phone_android_rounded),
            label: Text(current ? 'Current plan' : 'Pay with UPI'),
          ),
        ),
        const SizedBox(height: 8),
        Text('GPay · PhonePe · Paytm · any UPI app or card · secured by Razorpay',
            textAlign: TextAlign.center, style: AppFonts.sans(size: 11, color: AppColors.ink4)),
      ]),
    );
  }

  Widget _mentorshipFaqSection() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.pureWhite,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: AppColors.birch),
      ),
      // Own Material so the header's ink isn't hidden under the white box.
      child: Material(
        type: MaterialType.transparency,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        clipBehavior: Clip.antiAlias,
        child: ExpansionTile(
        onExpansionChanged: (open) {
          if (open) ChurnTelemetryService.instance.recordButtonTap('subscribe_faq_mentorship_expand');
        },
        tilePadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 2),
        childrenPadding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
        title: Text(
          'Frequently Asked Questions',
          style: GoogleFonts.ibmPlexSans(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.ink),
        ),
        subtitle: Text(
          'Mentorship schedule, cancellations & simulated funds',
          style: GoogleFonts.ibmPlexSans(fontSize: 11, color: AppColors.ink4),
        ),
        children: [
          _faqItem(
            'When are the live mentorship sessions?',
            'Twice every week (every Wednesday & Saturday evening). Founders and senior trading mentors host live breakdowns of real market events, option setups, and risk management.',
          ),
          const SizedBox(height: AppSpacing.sm),
          _faqItem(
            'Can I cancel my subscription anytime?',
            'Yes. You can cancel at any time with one tap. Your benefits remain active until the end of your prepaid billing period.',
          ),
          const SizedBox(height: AppSpacing.sm),
          _faqItem(
            'Can demo cash be withdrawn?',
            'No. Demo cash is purely for educational simulation so you can master the markets safely without risking your own capital.',
          ),
        ],
      ),
      ),
    );
  }

  Widget _topUpFaqSection() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.pureWhite,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: AppColors.birch),
      ),
      // Own Material so the header's ink isn't hidden under the white box.
      child: Material(
        type: MaterialType.transparency,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        clipBehavior: Clip.antiAlias,
        child: ExpansionTile(
        onExpansionChanged: (open) {
          if (open) ChurnTelemetryService.instance.recordButtonTap('subscribe_faq_topup_expand');
        },
        tilePadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 2),
        childrenPadding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
        title: Text(
          'Top-Up FAQs',
          style: GoogleFonts.ibmPlexSans(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.ink),
        ),
        subtitle: Text(
          'Instant balance addition & validity',
          style: GoogleFonts.ibmPlexSans(fontSize: 11, color: AppColors.ink4),
        ),
        children: [
          _faqItem(
            'Does purchased demo cash expire?',
            'Never. Your demo balance remains in your virtual wallet indefinitely until deployed in trades.',
          ),
          const SizedBox(height: AppSpacing.sm),
          _faqItem(
            'How fast will my balance update?',
            'Your virtual capital credits automatically to your wallet within seconds of completing the checkout.',
          ),
          const SizedBox(height: AppSpacing.sm),
          _faqItem(
            'Can I use top-up demo cash for F&O trading?',
            'Yes, your demo capital can be used across equities, futures, and options.',
          ),
        ],
      ),
      ),
    );
  }

  Widget _faqItem(String question, String answer) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          question,
          style: GoogleFonts.ibmPlexSans(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.ink),
        ),
        const SizedBox(height: 2),
        Text(
          answer,
          style: GoogleFonts.ibmPlexSans(fontSize: 11, color: AppColors.ink3, height: 1.4),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Checkout & Native In-App Razorpay Handling
  // ---------------------------------------------------------------------------
  Future<void> _openCheckout(PlanOption product) async {
    if (_busySku != null) return;
    ChurnTelemetryService.instance.recordButtonTap('subscribe_footer_pay_with_upi_cta');

    if (Platform.isIOS) {
      _tell('In-app purchases are not enabled on iOS yet. All trading simulation features are completely free!');
      return;
    }

    final auth = context.read<AuthService>();
    if (auth.isGuest) {
      _tell('Please make your account permanent first — a guest account cannot be recovered, and a purchase on it would be lost.');
      return;
    }

    // No phone prompt: Razorpay collects it if it needs one. A saved number still pre-fills.
    final phone = _savedPhone;

    setState(() => _busySku = product.sku);
    ChurnTelemetryService.instance.recordPaywallStep('checkout_start', sku: product.sku);
    try {
      final session = await SupabaseService().createPaymentSession(
        product.sku,
        contact: phone,
      );
      if (!mounted) return;

      _activeSession = session;
      _activeProduct = product;

      // Open native in-app Razorpay Checkout if supported
      if (_razorpay != null) {
        final userEmail = session.prefillEmail ?? auth.user?.email ?? '';
        final userName = session.prefillName ?? auth.user?.name ?? '';
        final userContact = session.prefillContact ?? phone ?? '';

        final options = <String, dynamic>{
          'key': session.keyId,
          'name': 'Trading Titans',
          'description': session.title,
          'theme': {'color': '#B8860B'},
          'retry': {'enabled': true, 'max_count': 3},
          'prefill': {
            if (userContact.isNotEmpty) 'contact': userContact,
            if (userEmail.isNotEmpty) 'email': userEmail,
            if (userName.isNotEmpty) 'name': userName,
          },
          'notes': {
            'sku': product.sku,
            if (auth.user?.id != null) 'user_id': auth.user!.id,
            if (userContact.isNotEmpty) 'phone': userContact,
          },
        };

        if (session.orderId != null && session.orderId!.isNotEmpty) {
          options['order_id'] = session.orderId;
          options['amount'] = session.amountPaise;
          options['currency'] = session.currency;
        } else if (session.subscriptionId != null) {
          options['subscription_id'] = session.subscriptionId;
        }

        _razorpay!.open(options);
        return;
      }

      // Fallback to hosted browser URL only if native plugin is unavailable
      await _launchHostedFallback(session);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busySku = null);
      _tell(_readable(e));
    }
  }

  Future<void> _launchHostedFallback(PaymentSession session) async {
    final url = session.hostedUrl;
    if (url == null || !url.startsWith('https://')) {
      if (mounted) setState(() => _busySku = null);
      _tell('We could not start the payment. Please try again.');
      return;
    }
    final uri = Uri.parse(url);
    bool launched = false;
    try {
      launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      launched = false;
    }
    if (!mounted) return;
    setState(() => _busySku = null);
    if (!launched) {
      _tell('We could not open your browser. Open this link to pay: $url');
      return;
    }
    _tell('Finish the payment in your browser, then return — your balance will update automatically.');
  }

  Future<void> _handlePaymentSuccess(PaymentSuccessResponse response) async {
    final session = _activeSession;
    final product = _activeProduct;
    ChurnTelemetryService.instance.recordPaywallStep('purchase_success', sku: product?.sku);
    if (!mounted) return;

    _tell('Payment received! Confirming and crediting your account...');

    bool granted = false;
    if (session != null) {
      granted = await SupabaseService().waitForPaymentGrant(session);
    }

    if (!mounted) return;
    final auth = context.read<AuthService>();
    await auth.refreshUser();
    await PlanService.instance.refresh();

    if (!mounted) return;
    setState(() => _busySku = null);

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.pureWhite,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.xl)),
        title: Row(
          children: [
            Icon(Icons.check_circle_rounded, color: AppColors.bull, size: 26),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                granted ? 'Payment Confirmed!' : 'Payment Received!',
                style: GoogleFonts.ibmPlexSans(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.ink),
              ),
            ),
          ],
        ),
        content: Text(
          product != null && product.isSubscription
              ? 'Welcome to ${product.title}! Your VIP badge and monthly virtual capital stipend are now active.'
              : product != null
                  ? '+${Money.wallet(product.cashGrant)} has been credited to your demo wallet.'
                  : 'Your account balance and benefits have been updated.',
          style: GoogleFonts.ibmPlexSans(fontSize: 13.5, color: AppColors.ink2, height: 1.45),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.bull,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
            ),
            child: Text('Start Trading', style: GoogleFonts.ibmPlexSans(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  void _handlePaymentError(PaymentFailureResponse response) {
    ChurnTelemetryService.instance.recordPaywallStep('purchase_failed', sku: _activeProduct?.sku, code: response.code);
    ChurnTelemetryService.instance.recordActionError('payment_failed');
    if (!mounted) return;
    final product = _activeProduct;
    final session = _activeSession;
    setState(() => _busySku = null);

    // Code 2 is Razorpay's user-cancelled back press
    if (response.code == Razorpay.NETWORK_ERROR) {
      _tell('Network issue during payment. Please check your connection and try again.');
      return;
    }
    if (response.code == Razorpay.PAYMENT_CANCELLED) {
      _tell('Payment cancelled. You have not been charged.');
      return;
    }

    final rawMsg = response.message ?? 'The payment could not be completed. You have not been charged.';
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.pureWhite,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.xl)),
        title: Row(
          children: [
            Icon(Icons.error_outline_rounded, color: AppColors.bear, size: 24),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Payment Incomplete',
                style: GoogleFonts.ibmPlexSans(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.ink),
              ),
            ),
          ],
        ),
        content: Text(
          'Your payment did not go through ($rawMsg). If you were charged, it will auto-credit or refund shortly.',
          style: GoogleFonts.ibmPlexSans(fontSize: 13, color: AppColors.ink3, height: 1.45),
        ),
        actions: [
          if (session?.hostedUrl != null)
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                _launchHostedFallback(session!);
              },
              child: Text(
                'Pay via Browser',
                style: GoogleFonts.ibmPlexSans(color: AppColors.ink3, fontWeight: FontWeight.w600),
              ),
            ),
          if (product != null)
            ElevatedButton(
              onPressed: () {
                ChurnTelemetryService.instance.recordButtonTap('subscribe_payment_failed_retry_btn');
                Navigator.of(ctx).pop();
                _openCheckout(product);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.ink,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
              ),
              child: Text('Retry Payment', style: GoogleFonts.ibmPlexSans(fontWeight: FontWeight.w700)),
            ),
        ],
      ),
    );
  }

  void _handleExternalWallet(ExternalWalletResponse response) {
    if (!mounted) return;
    _tell('Continuing payment in ${response.walletName ?? "external wallet"}...');
  }

  String _readable(Object e) =>
      e.toString().replaceFirst(RegExp(r'^(Exception|_Exception):\s*'), '');

  String? _approx(PlanOption product, Currency billing) {
    final charged = product.chargedIn(billing);
    if (Money.display == charged || Money.rate == null) return null;
    final major = product.chargedMinor(billing) / 100;
    return '\u2248 ${Money.from(major, charged, decimals: 2)}';
  }

  void _tell(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.ibmPlexSans(fontSize: 13)),
        duration: const Duration(seconds: 6),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

/// The pre-sale price, struck through, with the discount beside it.
Widget _wasPrice(PlanOption product, Currency billing) {
  final now = product.chargedMinor(billing);
  final was = product.chargedIn(billing) == Currency.usd ? product.compareAtUsdCents : product.compareAtPaise;
  final off = was == null || was <= 0 ? 0 : (100 - now * 100 / was).floor();
  return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
          decoration: BoxDecoration(
            color: AppColors.titanGoldSoft,
            borderRadius: BorderRadius.circular(AppRadius.tag),
          ),
          child: Text(
            '$off% OFF',
            style: AppFonts.mono(size: 9.5, weight: FontWeight.w600, color: AppColors.titanGold),
          ),
        ),
        const SizedBox(width: 5),
        Text(
          product.wasPriceLabel(billing) ?? '',
          style: GoogleFonts.ibmPlexSans(
            fontSize: 12,
            color: AppColors.ink4,
            decoration: TextDecoration.lineThrough,
          ),
        ),
      ],
    );
}
