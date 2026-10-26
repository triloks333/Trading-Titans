import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

/// Plans and top-ups, presented with a clean segmented view.
///
/// Tab 0: VIP Mentorship Plans (Titan Pro ₹999 with 1-on-1 Founder Mentorship, Pro Monthly).
/// Tab 1: One-time Demo Capital Top-Ups (Instant ₹10L, ₹5L, ₹1L non-expiring cash packs).
class SubscribeScreen extends StatefulWidget {
  final int initialTabIndex;

  const SubscribeScreen({
    super.key,
    this.initialTabIndex = 0,
  });

  @override
  State<SubscribeScreen> createState() => _SubscribeScreenState();
}

class _SubscribeScreenState extends State<SubscribeScreen> {
  late Future<List<PlanOption>> _plans;
  late int _selectedTab;

  /// The SKU whose checkout is being opened, so its button can show a spinner and
  /// every other one can be disabled.
  String? _busySku;

  @override
  void initState() {
    super.initState();
    _selectedTab = widget.initialTabIndex.clamp(0, 1);
    _plans = SupabaseService().getPlanCatalogue();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final plan = context.watch<PlanService>();
    final billing = context.watch<CurrencyService>().billingCurrency;
    final wallet = auth.user?.walletBalance ?? 0.0;

    // Defence in depth: hidden when monetization is off, or on iOS where Apple
    // strictly mandates StoreKit In-App Purchases for digital goods (Guideline 3.1.1).
    if (!context.watch<AppFlagsService>().monetizationEnabled || Platform.isIOS) {
      return Scaffold(
        appBar: _bar(),
        body: EmptyState(
          icon: Icons.school_rounded,
          title: 'Educational Mode',
          message:
              'Trading Titans on iOS is completely free. '
              'All simulation markets, real-time charts, options, and futures are unlocked. '
              'Earn additional demo capital by completing daily challenges!',
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.parchment,
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
          final topups = all.where((p) => !p.isSubscription).toList()
            ..sort((a, b) => a.pricePaise.compareTo(b.pricePaise)); // Lower price packages on top (199 -> 599 -> 999)
          final subscriptions = all
              .where((p) => p.isSubscription && p.billingInterval == 'monthly')
              .toList()
            ..sort((a, b) => a.pricePaise.compareTo(b.pricePaise)); // Lower price packages on top (149 -> 799)
          final hasAnnual = all.any((p) => p.isSubscription && p.billingInterval == 'annual');

          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
            children: [
              // --- Current Balance Strip ---
              _balanceStrip(wallet, plan),
              const SizedBox(height: AppSpacing.md),

              // --- Segmented Tab Switcher ---
              _segmentedBar(),
              const SizedBox(height: AppSpacing.md),

              // Currency equivalence notice if applicable
              if (billing != Money.display) ...[
                Container(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: AppColors.pureWhite,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(color: AppColors.birch),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline_rounded, size: 16, color: AppColors.ink4),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Charges are in ${billing.label}s.'
                          '${Money.rate == null ? '' : ' Amounts marked \u2248 are today\u2019s equivalent in ${Money.display.label}s.'}',
                          style: GoogleFonts.inter(fontSize: 11, color: AppColors.ink4),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
              ],

              // --- Content based on Selected Tab ---
              if (_selectedTab == 0) ...[
                _buildMentorshipTab(subscriptions, billing, plan, hasAnnual),
              ] else ...[
                _buildTopUpTab(topups, billing),
              ],

              const SizedBox(height: AppSpacing.xl),

              // --- Regulatory Disclaimer ---
              Center(
                child: Text(
                  'Demo cash is educational virtual capital with zero monetary value and cannot be withdrawn. '
                  'Transactions use secure 256-bit encrypted Razorpay checkout.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(fontSize: 11, color: AppColors.ink5, height: 1.45),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
            ],
          );
        },
      ),
    );
  }

  AppBar _bar() => AppBar(
        title: Text(
          'Plans & Top-Ups',
          style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 18, color: AppColors.ink),
        ),
        backgroundColor: AppColors.parchment,
        elevation: 0,
        centerTitle: false,
      );

  // ---------------------------------------------------------------------------
  // Top Balance Strip
  // ---------------------------------------------------------------------------
  Widget _balanceStrip(double wallet, PlanService plan) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.pureWhite,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.birch),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.goldPale,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.goldBorder),
            ),
            child: const Icon(Icons.account_balance_wallet_rounded, size: 20, color: AppColors.goldDeep),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'CURRENT DEMO BALANCE',
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink4,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  Money.wallet(wallet),
                  style: GoogleFonts.inter(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: AppColors.ink,
                  ),
                ),
              ],
            ),
          ),
          if (plan.isPaid)
            PlanBadge(tier: plan.tier)
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.cream,
                borderRadius: BorderRadius.circular(AppRadius.tag),
                border: Border.all(color: AppColors.birch),
              ),
              child: Text(
                'FREE TIER',
                style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink4,
                  letterSpacing: 0.5,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Segmented Pill Control
  // ---------------------------------------------------------------------------
  Widget _segmentedBar() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.birch.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      child: Row(
        children: [
          Expanded(
            child: _segmentTab(
              index: 0,
              icon: Icons.workspace_premium_rounded,
              title: 'VIP Mentorship',
              badge: '₹1L+/mo',
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _segmentTab(
              index: 1,
              icon: Icons.bolt_rounded,
              title: 'Top-Up Capital',
              badge: 'INSTANT',
            ),
          ),
        ],
      ),
    );
  }

  Widget _segmentTab({
    required int index,
    required IconData icon,
    required String title,
    required String badge,
  }) {
    final isSelected = _selectedTab == index;
    final activeColor = index == 0 ? AppColors.violet : AppColors.goldDeep;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (_selectedTab != index) {
          HapticFeedback.selectionClick();
          setState(() => _selectedTab = index);
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.pureWhite : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 17,
              color: isSelected ? activeColor : AppColors.ink4,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                title,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                  color: isSelected ? AppColors.ink : AppColors.ink3,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 5),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
              decoration: BoxDecoration(
                color: isSelected ? activeColor.withValues(alpha: 0.12) : AppColors.birch,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                badge,
                style: GoogleFonts.inter(
                  fontSize: 8.5,
                  fontWeight: FontWeight.w800,
                  color: isSelected ? activeColor : AppColors.ink4,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // TAB 0: VIP Mentorship Plans
  // ---------------------------------------------------------------------------
  Widget _buildMentorshipTab(
    List<PlanOption> subscriptions,
    Currency billing,
    PlanService plan,
    bool hasAnnual,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Hero Mentorship Card
        _heroMentorshipBanner(),
        const SizedBox(height: AppSpacing.lg),

        if (subscriptions.isNotEmpty) ...[
          for (final p in subscriptions) ...[
            _subscriptionCard(p, billing, isCurrent: plan.tier == p.tier),
            const SizedBox(height: AppSpacing.md),
          ],
          if (hasAnnual) _annualNote(),
        ],

        const SizedBox(height: AppSpacing.lg),
        _trustStrip(isMentorship: true),
        const SizedBox(height: AppSpacing.lg),
        _mentorshipFaqSection(),
      ],
    );
  }

  Widget _heroMentorshipBanner() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F172A), Color(0xFF1E1B4B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppRadius.xl),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6366F1).withValues(alpha: 0.2),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFD700).withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(AppRadius.tag),
                  border: Border.all(color: const Color(0xFFFFD700).withValues(alpha: 0.4)),
                ),
                child: Text(
                  '★ FLAGSHIP PROGRAM · ₹1L+/MO VALUE',
                  style: GoogleFonts.inter(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFFFFD700),
                    letterSpacing: 0.6,
                  ),
                ),
              ),
              const Spacer(),
              const Icon(Icons.verified_rounded, size: 16, color: Color(0xFFFFD700)),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Live Founder Mentorship & Pro Setups',
            style: GoogleFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Twice-weekly interactive live sessions (Wed & Sat) with founders, institutional strategy reviews, and ₹10L monthly virtual stipend.',
            style: GoogleFonts.inter(
              fontSize: 12,
              color: Colors.white.withValues(alpha: 0.85),
              height: 1.4,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(child: _badgePill(Icons.school_outlined, 'Twice-Weekly Live')),
              const SizedBox(width: AppSpacing.xs),
              Expanded(child: _badgePill(Icons.trending_up_rounded, 'Institutional Setups')),
              const SizedBox(width: AppSpacing.xs),
              Expanded(child: _badgePill(Icons.all_inclusive_rounded, 'F&O Unlocked')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _badgePill(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 12, color: const Color(0xFFFFD700)),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              text,
              style: GoogleFonts.inter(
                fontSize: 9.5,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _subscriptionCard(
    PlanOption product,
    Currency billing, {
    required bool isCurrent,
  }) {
    final isTitan = product.tier == 'titan' || product.pricePaise >= 79900;
    final accent = isTitan ? AppColors.violet : AppColors.imperialGold;
    final busy = _busySku == product.sku;
    final blocked = isCurrent || (_busySku != null && !busy);
    final approx = _approx(product, billing);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.pureWhite,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(
          color: isTitan ? AppColors.violet : AppColors.birch,
          width: isTitan ? 1.8 : 1.0,
        ),
        boxShadow: isTitan
            ? [
                BoxShadow(
                  color: AppColors.violet.withValues(alpha: 0.12),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ]
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isTitan) ...[
            Container(
              margin: const EdgeInsets.only(bottom: AppSpacing.sm),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.violet.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadius.tag),
              ),
              child: Text(
                '★ MOST POPULAR · INCLUDES LIVE FOUNDER SESSIONS',
                style: GoogleFonts.inter(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.violet,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          product.title,
                          style: GoogleFonts.inter(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: AppColors.ink,
                          ),
                        ),
                        if (isCurrent) ...[
                          const SizedBox(width: AppSpacing.sm),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: AppCard.badge(AppColors.bullLight),
                            child: Text(
                              'ACTIVE',
                              style: GoogleFonts.inter(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: AppColors.bull,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    Text(
                      isTitan ? 'Ultimate mentorship & pro trading pass' : 'Starter simulation plan',
                      style: GoogleFonts.inter(fontSize: 11, color: AppColors.ink4),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    product.priceLabel(billing),
                    style: GoogleFonts.inter(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: AppColors.ink,
                    ),
                  ),
                  Text(
                    approx == null ? 'per month' : 'per month · $approx',
                    style: GoogleFonts.inter(fontSize: 10, color: AppColors.ink5),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),

          // High impact value points
          if (isTitan) ...[
            _perkItem('Twice-weekly live 1-on-1 mentorship with founders (Wed & Sat)', accent, isBold: true),
            const SizedBox(height: 6),
            _perkItem('₹1 Lakh+/month worth of institutional option setups', accent, isBold: true),
            const SizedBox(height: 6),
          ],
          _perkItem('${Money.wallet(product.monthlyStipend)} virtual capital added every month', accent),
          const SizedBox(height: 6),
          _perkItem('Unrestricted Futures & Options (F&O) trading', accent),
          const SizedBox(height: 6),
          _perkItem('${product.tier.toUpperCase()} VIP badge across chat & leaderboards', accent),
          if (isTitan) ...[
            const SizedBox(height: 6),
            _perkItem('Unlimited trade autopsies with tailored risk diagnosis', accent),
          ],

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
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
              ),
              child: busy
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Text(
                      isCurrent ? 'Current Plan' : 'Unlock ${product.title}',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: blocked ? AppColors.ink4 : AppColors.pureWhite,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _perkItem(String text, Color accent, {bool isBold = false}) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.check_circle_rounded, size: 15, color: accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.inter(
                fontSize: 12.5,
                fontWeight: isBold ? FontWeight.w600 : FontWeight.w400,
                color: isBold ? AppColors.ink : AppColors.ink3,
              ),
            ),
          ),
        ],
      );

  Widget _annualNote() => Padding(
        padding: const EdgeInsets.only(top: AppSpacing.xs),
        child: GestureDetector(
          onTap: _openAnnualPlans,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.savings_outlined, size: 14, color: AppColors.ink4),
              const SizedBox(width: 6),
              Text(
                'Paying yearly saves up to 40% — compare on our website',
                style: GoogleFonts.inter(fontSize: 11.5, color: AppColors.ink4, fontWeight: FontWeight.w500),
              ),
              const SizedBox(width: 4),
              Icon(Icons.open_in_new_rounded, size: 12, color: AppColors.ink4),
            ],
          ),
        ),
      );

  // ---------------------------------------------------------------------------
  // TAB 1: One-time Top-Up Capital
  // ---------------------------------------------------------------------------
  Widget _buildTopUpTab(
    List<PlanOption> topups,
    Currency billing,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Intro Banner
        _topUpIntroBanner(),
        const SizedBox(height: AppSpacing.lg),

        // Package Cards
        if (topups.isEmpty)
          const Center(child: Text('No top-up packages available currently.'))
        else
          for (final p in topups) ...[
            _topUpCard(p, billing),
            const SizedBox(height: AppSpacing.md),
          ],

        const SizedBox(height: AppSpacing.lg),
        _trustStrip(isMentorship: false),
        const SizedBox(height: AppSpacing.lg),
        _topUpFaqSection(),
      ],
    );
  }

  Widget _topUpIntroBanner() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.goldPale.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.goldBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: const BoxDecoration(
              color: AppColors.goldDeep,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.bolt_rounded, size: 22, color: Colors.white),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'INSTANT CAPITAL BOOST',
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: AppColors.goldDeep,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'One-time demo cash · Never expires · Stocks & F&O simulation with zero personal capital risk.',
                  style: GoogleFonts.inter(
                    fontSize: 11.5,
                    color: AppColors.ink2,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _topUpCard(PlanOption product, Currency billing) {
    final busy = _busySku == product.sku;
    final approx = _approx(product, billing);
    final isMax = product.pricePaise >= 99900;
    final isMid = product.pricePaise >= 49900 && !isMax;
    final isMini = product.sku == 'topup_mini' || product.pricePaise <= 3000;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.pureWhite,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(
          color: isMax ? AppColors.imperialGold : (isMini ? const Color(0xFF38BDF8) : AppColors.birch),
          width: isMax || isMini ? 1.8 : 1.0,
        ),
        boxShadow: isMax
            ? [
                BoxShadow(
                  color: AppColors.imperialGold.withValues(alpha: 0.15),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ]
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (isMax)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.goldPale,
                    borderRadius: BorderRadius.circular(AppRadius.tag),
                    border: Border.all(color: AppColors.goldBorder),
                  ),
                  child: Text(
                    '⚡ BEST VALUE · 10X CAPITAL',
                    style: GoogleFonts.inter(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      color: AppColors.goldDeep,
                      letterSpacing: 0.5,
                    ),
                  ),
                )
              else if (isMini)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE0F2FE),
                    borderRadius: BorderRadius.circular(AppRadius.tag),
                    border: Border.all(color: const Color(0xFFBAE6FD)),
                  ),
                  child: Text(
                    '⚡ MINI BOOST · ₹29 ONLY',
                    style: GoogleFonts.inter(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF0284C7),
                      letterSpacing: 0.5,
                    ),
                  ),
                )
              else if (isMid)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.cream,
                    borderRadius: BorderRadius.circular(AppRadius.tag),
                    border: Border.all(color: AppColors.birch),
                  ),
                  child: Text(
                    'PRO PACK',
                    style: GoogleFonts.inter(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink3,
                      letterSpacing: 0.5,
                    ),
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.cream,
                    borderRadius: BorderRadius.circular(AppRadius.tag),
                    border: Border.all(color: AppColors.birch),
                  ),
                  child: Text(
                    'STARTER PACK',
                    style: GoogleFonts.inter(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink4,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              Text(
                'One-Time Purchase',
                style: GoogleFonts.inter(fontSize: 11, color: AppColors.ink4),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),

          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '+${Money.wallet(product.cashGrant)}',
                      style: GoogleFonts.inter(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: isMax ? AppColors.goldDeep : AppColors.ink,
                      ),
                    ),
                    Text(
                      'Credited instantly · Never expires',
                      style: GoogleFonts.inter(fontSize: 11, color: AppColors.ink4),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    product.priceLabel(billing),
                    style: GoogleFonts.inter(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: AppColors.ink,
                    ),
                  ),
                  if (approx != null)
                    Text(
                      approx,
                      style: GoogleFonts.inter(fontSize: 10, color: AppColors.ink5),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: busy || _busySku != null ? null : () => _openCheckout(product),
              style: ElevatedButton.styleFrom(
                backgroundColor: isMax ? AppColors.imperialGold : AppColors.ink,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
              ),
              child: busy
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Text(
                      'Get ${Money.wallet(product.cashGrant)} for ${product.priceLabel(billing)}',
                      style: GoogleFonts.inter(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Minimalist Trust Strip
  // ---------------------------------------------------------------------------
  Widget _trustStrip({required bool isMentorship}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.pureWhite,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.birch),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _trustPill(Icons.bolt_rounded, 'Instant Credit'),
          Container(width: 1, height: 20, color: AppColors.birch),
          _trustPill(Icons.shield_outlined, 'Zero Real Risk'),
          Container(width: 1, height: 20, color: AppColors.birch),
          _trustPill(Icons.lock_outline_rounded, 'Encrypted Pay'),
        ],
      ),
    );
  }

  Widget _trustPill(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppColors.goldDeep),
        const SizedBox(width: 4),
        Text(
          text,
          style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.ink2),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // FAQs
  // ---------------------------------------------------------------------------
  Widget _mentorshipFaqSection() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.pureWhite,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: AppColors.birch),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 2),
        childrenPadding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
        title: Text(
          'Frequently Asked Questions',
          style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.ink),
        ),
        subtitle: Text(
          'Mentorship schedule, cancellations & simulated funds',
          style: GoogleFonts.inter(fontSize: 11, color: AppColors.ink4),
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
    );
  }

  Widget _topUpFaqSection() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.pureWhite,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: AppColors.birch),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 2),
        childrenPadding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
        title: Text(
          'Top-Up FAQs',
          style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.ink),
        ),
        subtitle: Text(
          'Instant balance addition & validity',
          style: GoogleFonts.inter(fontSize: 11, color: AppColors.ink4),
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
    );
  }

  Widget _faqItem(String question, String answer) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          question,
          style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.ink),
        ),
        const SizedBox(height: 2),
        Text(
          answer,
          style: GoogleFonts.inter(fontSize: 11, color: AppColors.ink3, height: 1.4),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Checkout & URL Handling
  // ---------------------------------------------------------------------------
  Future<void> _openCheckout(PlanOption product) async {
    if (_busySku != null) return;

    if (Platform.isIOS) {
      _tell('In-app purchases are not enabled on iOS yet. All trading simulation features are completely free!');
      return;
    }

    if (context.read<AuthService>().isGuest) {
      _tell('Please make your account permanent first — a guest account cannot be recovered, and a purchase on it would be lost.');
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
        _tell('We could not open your browser. Open this link to pay: $url');
        return;
      }

      _tell('Finish the payment in your browser, then return — your balance will update automatically.');
    } catch (e) {
      if (!mounted) return;
      _tell(_readable(e));
    } finally {
      if (mounted) setState(() => _busySku = null);
    }
  }

  String _readable(Object e) =>
      e.toString().replaceFirst(RegExp(r'^(Exception|_Exception):\s*'), '');

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

  String? _approx(PlanOption product, Currency billing) {
    final charged = product.chargedIn(billing);
    if (Money.display == charged || Money.rate == null) return null;
    final major = product.chargedMinor(billing) / 100;
    return '\u2248 ${Money.from(major, charged, decimals: 2)}';
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
