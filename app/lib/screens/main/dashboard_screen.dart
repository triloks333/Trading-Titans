import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:showcaseview/showcaseview.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme.dart';
import '../../core/money.dart';
import '../../core/app_constants.dart';
import '../../widgets/diwali_sale_banner.dart';
import '../../widgets/muhurat_card.dart';
import '../../widgets/crown_logo.dart';
import '../../widgets/titan_showcase.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/home_banner_carousel.dart';
import '../../widgets/home_news_section.dart';
import '../../services/supabase_service.dart';
import '../../services/auth_service.dart';
import '../../models/quote.dart';
import '../../models/portfolio.dart';
import 'stock_detail_screen.dart';
import 'analytics_screen.dart';
import 'autopsy_screen.dart';
import 'trade_screen.dart';
import 'whatif_screen.dart';
import 'orders_screen.dart';
import 'notifications_screen.dart';
import 'chat_screen.dart';
import 'subscribe_screen.dart';
import 'package:google_fonts/google_fonts.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool _loading = true;
  List<Holding> _holdings = [];
  List<Quote> _watchlist = [];
  List<Quote> _overview = [];
  Timer? _pollTimer;
  int _unreadNotificationsCount = 0;

  // Showcase Keys
  final GlobalKey _totalValueKey = GlobalKey();
  final GlobalKey _actionsKey = GlobalKey();
  final GlobalKey _pulseKey = GlobalKey();
  final GlobalKey _notificationsKey = GlobalKey();
  final GlobalKey _guideKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _load();
    _pollTimer = Timer.periodic(AppConstants.dashboardPricePoll, (_) => _refreshPrices());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshPrices() async {
    try {
      final results = await Future.wait([
        SupabaseService().getMarketOverview(),
        SupabaseService().getHoldings(),
        SupabaseService().getWatchlist(),
        _loadUnreadNotificationsCount(),
      ]);
      if (mounted) {
        setState(() {
          _overview = results[0] as List<Quote>;
          _holdings = results[1] as List<Holding>;
          _watchlist = results[2] as List<Quote>;
        });
      }
    } catch (_) {}
  }

  Future<void> _load() async {
    // Capture the provider before any await to avoid using context across an
    // async gap.
    final auth = context.read<AuthService>();
    // Cache-first: paint the last-known data instantly so the screen never
    // blocks on the network when we've shown it before. The skeleton only
    // appears on the very first load (no cache yet).
    await _hydrateFromCache();
    try {
      final results = await Future.wait([
        SupabaseService().getMarketOverview(),
        SupabaseService().getHoldings(),
        SupabaseService().getWatchlist(),
        auth.refreshUser(),
        _loadUnreadNotificationsCount(),
      ]);
      if (mounted) {
        setState(() {
          _overview = results[0] as List<Quote>;
          _holdings = results[1] as List<Holding>;
          _watchlist = results[2] as List<Quote>;
        });
      }
    } catch (_) {
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
      // After the dashboard content is laid out, start the interactive tour
      // on first run (or when a replay was requested from Profile).
      unawaited(_maybeStartTour());
    }
  }

  /// Loads any previously cached dashboard data and renders it immediately,
  /// dismissing the skeleton. Safe no-op when nothing is cached (first run).
  Future<void> _hydrateFromCache() async {
    try {
      final svc = SupabaseService();
      final cached = await Future.wait([
        svc.getCachedMarketOverview(),
        svc.getCachedHoldings(),
        svc.getCachedWatchlist(),
      ]);
      if (!mounted) return;
      final overview = cached[0] as List<Quote>;
      final holdings = cached[1] as List<Holding>;
      final watchlist = cached[2] as List<Quote>;
      if (overview.isNotEmpty || holdings.isNotEmpty || watchlist.isNotEmpty) {
        setState(() {
          if (overview.isNotEmpty) _overview = overview;
          if (holdings.isNotEmpty) _holdings = holdings;
          if (watchlist.isNotEmpty) _watchlist = watchlist;
          _loading = false;
        });
      }
    } catch (_) {}
  }

  /// Starts the showcase tour once for new users, and again whenever a replay
  /// was requested. Best-effort: never throws into the load path.
  Future<void> _maybeStartTour() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final seen = prefs.getBool('dashboard_tour_seen') ?? false;
      final pendingReplay = prefs.getBool('pending_tour_replay') ?? false;
      if (seen && !pendingReplay) return;
      await prefs.setBool('dashboard_tour_seen', true);
      if (pendingReplay) await prefs.remove('pending_tour_replay');
      if (!mounted) return;
      // Wait for the next frame so all showcase target widgets are built.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _startGuide();
      });
    } catch (_) {}
  }

  Future<void> _loadUnreadNotificationsCount() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;
      final res = await Supabase.instance.client
          .from('notifications')
          .select('id')
          .eq('user_id', user.id)
          .eq('is_read', false);
      if (mounted) {
        setState(() {
          _unreadNotificationsCount = (res as List).length;
        });
      }
    } catch (_) {}
  }

  void _startGuide() {
    ShowcaseView.get().startShowCase([
      _guideKey,
      _notificationsKey,
      _totalValueKey,
      _actionsKey,
      _pulseKey,
    ]);
  }

  String _formatValue(double value) {
    if (value.abs() < 1) return Money.wallet(value, decimals: 2);
    return Money.wallet(value, decimals: 0);
  }

  /// Signed amount, for gains and losses. [_formatValue] puts the currency
  /// symbol before the minus ("₹-3654"); this reads as "-₹3654" and matches the
  /// portfolio screen, so the same figure looks the same on both.
  String _formatSigned(double value) =>
      '${value >= 0 ? '+' : '-'}${_formatValue(value.abs())}';

  /// Open positions only.
  ///
  /// These folds ran over every holding, including fully closed ones. A closed
  /// row carries `quantity == 0` with `pnl` set to today's REALIZED P&L (see
  /// SupabaseService.getHoldings), so closing a trade added a realized figure
  /// into a total the dashboard labels "unrealized" — and into `currentValue`,
  /// which feeds `totalValue = wallet + positions`. The portfolio screen has
  /// always filtered on `quantity != 0`, so the two screens reported different
  /// numbers for the same portfolio. That mismatch is the bug users hit; the
  /// portfolio screen's definition is the correct one.
  Iterable<Holding> get _openHoldings => _holdings.where((h) => h.quantity != 0);

  double get investedValue => _openHoldings.fold(0.0, (sum, holding) => sum + holding.invested);
  double get currentValue => _openHoldings.fold(0.0, (sum, holding) => sum + holding.current);
  double get unrealizedPnl => _openHoldings.fold(0.0, (sum, holding) => sum + holding.pnl);
  double get unrealizedPnlPct => investedValue > 0 ? (unrealizedPnl / investedValue) * 100 : 0.0;
  double get totalValue => (context.read<AuthService>().user?.walletBalance ?? 0.0) + currentValue;
  double get totalPnL => unrealizedPnl;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final user = auth.user;
    final isPositive = totalPnL >= 0;

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: _loading
              ? const DashboardSkeleton()
              : SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                const CrownLogo(size: 36, withRing: false),
                                const SizedBox(width: AppSpacing.sm),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('Welcome,', style: GoogleFonts.ibmPlexSans(fontSize: 12, color: AppColors.ink4)),
                                      Text(user?.name ?? 'Titan', maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.ibmPlexSans(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.ink)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Row(
                            children: [
                              // Guide Button (Question Mark)
                              TitanShowcase(
                                showcaseKey: _guideKey,
                                title: 'Interactive Guide',
                                description: 'Tap this question mark to launch the tour guide again anytime you want a walkthrough.',
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: _startGuide,
                                  child: SizedBox(
                                    width: 48,
                                    height: 48,
                                    child: Center(
                                      child: Container(
                                        width: 40,
                                        height: 40,
                                        decoration: BoxDecoration(
                                          color: AppColors.cream,
                                          shape: BoxShape.circle,
                                          border: Border.all(color: AppColors.birch),
                                        ),
                                        child: Icon(Icons.help_outline, size: 20, color: AppColors.ink2),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: AppSpacing.xs),
                              // Notification Button
                              TitanShowcase(
                                showcaseKey: _notificationsKey,
                                title: 'System Notifications',
                                description: 'View system messages, custom alerts, and real-time order fill updates here.',
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () async {
                                    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NotificationsScreen()));
                                    _loadUnreadNotificationsCount();
                                  },
                                  child: SizedBox(
                                    width: 48,
                                    height: 48,
                                    child: Center(
                                      child: Container(
                                        width: 40,
                                        height: 40,
                                        decoration: BoxDecoration(
                                          color: AppColors.cream,
                                          shape: BoxShape.circle,
                                          border: Border.all(color: AppColors.birch),
                                        ),
                                        child: Stack(
                                          alignment: Alignment.center,
                                          children: [
                                            Icon(Icons.notifications_outlined, size: 20, color: AppColors.ink2),
                                            if (_unreadNotificationsCount > 0)
                                              Positioned(
                                                top: 8,
                                                right: 8,
                                                child: Container(
                                                  width: 8,
                                                  height: 8,
                                                  decoration: const BoxDecoration(
                                                    color: Colors.red,
                                                    shape: BoxShape.circle,
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: AppSpacing.xs),
                              // Titans Room (public chat). Guests can read it; the
                              // composer is replaced by an upgrade prompt for them,
                              // so the entry point is not hidden.
                              GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ChatScreen())),
                                child: SizedBox(
                                  width: 48,
                                  height: 48,
                                  child: Center(
                                    child: Container(
                                      width: 40,
                                      height: 40,
                                      decoration: BoxDecoration(
                                        color: AppColors.cream,
                                        shape: BoxShape.circle,
                                        border: Border.all(color: AppColors.birch),
                                      ),
                                      child: Icon(Icons.forum_outlined, size: 20, color: AppColors.ink2),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: AppSpacing.xs),
                              // Order History Button
                              GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const OrdersScreen())),
                                child: SizedBox(
                                  width: 48,
                                  height: 48,
                                  child: Center(
                                    child: Container(
                                      width: 40,
                                      height: 40,
                                      decoration: BoxDecoration(
                                        color: AppColors.cream,
                                        shape: BoxShape.circle,
                                        border: Border.all(color: AppColors.birch),
                                      ),
                                      child: Icon(Icons.receipt_outlined, size: 20, color: AppColors.ink2),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      // Renders nothing unless a sale is running.
                      const DiwaliSaleBanner(),
                      // Renders nothing unless a Muhurat-style special session is scheduled.
                      const MuhuratCard(),
                      _buildRoomCard(),
                      TitanShowcase(
                        showcaseKey: _totalValueKey,
                        title: 'Portfolio Value',
                        description: 'This card displays your total account value, current active holdings valuation, and your overall unrealized profit and loss (P&L) in real-time.',
                        child: Container(
                          padding: const EdgeInsets.all(AppSpacing.xl),
                          decoration: AppCard.primary,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('TOTAL PORTFOLIO VALUE', style: AppText.sectionLabel),
                                  GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () => Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => const SubscribeScreen(initialTabIndex: 1),
                                      ),
                                    ),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        gradient: const LinearGradient(
                                          colors: [Color(0xFFE5A93C), Color(0xFFC48818)],
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                        ),
                                        borderRadius: BorderRadius.circular(16),
                                        boxShadow: [
                                          BoxShadow(
                                            color: const Color(0xFFE5A93C).withValues(alpha: 0.35),
                                            blurRadius: 6,
                                            offset: const Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.bolt_rounded, size: 14, color: Colors.white),
                                          const SizedBox(width: 3),
                                          Text(
                                            'TOP UP',
                                            style: GoogleFonts.ibmPlexSans(
                                              fontSize: 10.5,
                                              fontWeight: FontWeight.w800,
                                              color: Colors.white,
                                              letterSpacing: 0.5,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(_formatValue(totalValue), style: AppText.valueLarge),
                              const SizedBox(height: AppSpacing.sm),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 4),
                                decoration: AppCard.badge(isPositive ? AppColors.bullLight : AppColors.bearLight),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(isPositive ? Icons.trending_up : Icons.trending_down, size: 14, color: isPositive ? AppColors.bull : AppColors.bear),
                                    const SizedBox(width: 4),
                                    Text(
                                      '${_formatSigned(totalPnL)} (${unrealizedPnlPct.toStringAsFixed(2)}%)',
                                      style: GoogleFonts.ibmPlexMono(fontFeatures: const [FontFeature.tabularFigures()], fontSize: 13, fontWeight: FontWeight.w600, color: isPositive ? AppColors.bull : AppColors.bear),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: AppSpacing.lg),
                              Row(
                                children: [
                                  _buildStatBox(
                                    'Wallet',
                                    _formatValue(user?.walletBalance ?? 0.0),
                                    onTap: () => Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => const SubscribeScreen(initialTabIndex: 1),
                                      ),
                                    ),
                                    showTopUpAction: true,
                                  ),
                                  const SizedBox(width: AppSpacing.sm),
                                  _buildStatBox('Invested', _formatValue(investedValue)),
                                  const SizedBox(width: AppSpacing.sm),
                                  _buildStatBox('Holdings', '${_holdings.length}'),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      const HomeBannerCarousel(),
                      const SizedBox(height: AppSpacing.lg),
                      TitanShowcase(
                        showcaseKey: _actionsKey,
                        title: 'Advanced Analytics & Simulation',
                        description: 'Access tools like the What-If trade simulator, position Autopsy, and detailed portfolio Analytics to refine your strategy.',
                        child: Row(
                          children: [
                            _buildActionTile(Icons.search, 'Trade', onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TradeScreen()))),
                            const SizedBox(width: AppSpacing.sm),
                            _buildActionTile(Icons.lightbulb_outline, 'What-If', onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const WhatIfScreen()))),
                            const SizedBox(width: AppSpacing.sm),
                            _buildActionTile(Icons.medical_services_outlined, 'Autopsy', onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AutopsyScreen()))),
                            const SizedBox(width: AppSpacing.sm),
                            _buildActionTile(Icons.bar_chart, 'Analytics', onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AnalyticsScreen()))),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      TitanShowcase(
                        showcaseKey: _pulseKey,
                        title: 'Market Pulse',
                        description: 'Follow major stock indices and crypto tickers in real-time to track overall market sentiment.',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Market Pulse', style: GoogleFonts.ibmPlexSans(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.ink)),
                            const SizedBox(height: AppSpacing.sm),
                            SizedBox(
                              height: 120,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: _overview.length,
                                separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
                                itemBuilder: (context, index) {
                                  final quote = _overview[index];
                                  return GestureDetector(
                                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => StockDetailScreen(symbol: quote.symbol, market: quote.market, name: quote.name))),
                                    child: _buildTickerCard(quote.displayName ?? quote.name, _formatValue(quote.price), '${quote.changePct.toStringAsFixed(2)}%', quote.changePct >= 0),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      const HomeNewsSection(),
                      if (_holdings.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.xl),
                        Text('Your Holdings', style: GoogleFonts.ibmPlexSans(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.ink)),
                        const SizedBox(height: AppSpacing.sm),
                        ..._holdings.take(5).map((holding) {
                          return GestureDetector(
                            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => StockDetailScreen(symbol: holding.symbol, market: holding.market, name: holding.name))),
                            child: Container(
                              margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                              padding: const EdgeInsets.all(AppSpacing.md),
                              decoration: AppCard.secondary,
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(holding.symbol, style: GoogleFonts.ibmPlexSans(fontWeight: FontWeight.bold, color: AppColors.ink)),
                                        Text('${holding.quantity.toStringAsFixed(holding.market == 'crypto' ? 4 : 0)} units · avg ${_formatValue(holding.avgPrice)}', style: GoogleFonts.ibmPlexMono(fontFeatures: const [FontFeature.tabularFigures()], color: AppColors.ink4)),
                                      ],
                                    ),
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(_formatValue(holding.current), style: GoogleFonts.ibmPlexSans(fontWeight: FontWeight.bold, color: AppColors.ink)),
                                      Text('${holding.pnl >= 0 ? '+' : '-'}${holding.pnlPct.toStringAsFixed(2)}%', style: TextStyle(color: holding.pnl >= 0 ? AppColors.bull : AppColors.bear)),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                      ],
                      if (_watchlist.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.xl),
                        Text('Watchlist', style: GoogleFonts.ibmPlexSans(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.ink)),
                        const SizedBox(height: AppSpacing.sm),
                        ..._watchlist.map((quote) {
                          return GestureDetector(
                            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => StockDetailScreen(symbol: quote.symbol, market: quote.market, name: quote.name))),
                            child: Container(
                              margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                              padding: const EdgeInsets.all(AppSpacing.md),
                              decoration: AppCard.secondary,
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(quote.symbol, style: GoogleFonts.ibmPlexSans(fontWeight: FontWeight.bold, color: AppColors.ink)),
                                        Text(quote.name, style: GoogleFonts.ibmPlexSans(color: AppColors.ink4)),
                                      ],
                                    ),
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(_formatValue(quote.price), style: GoogleFonts.ibmPlexMono(fontFeatures: const [FontFeature.tabularFigures()], fontWeight: FontWeight.bold, color: AppColors.ink)),
                                      Text('${quote.changePct >= 0 ? '+' : ''}${quote.changePct.toStringAsFixed(2)}%', style: TextStyle(color: quote.changePct >= 0 ? AppColors.bull : AppColors.bear)),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                      ],
                      const SizedBox(height: AppSpacing.xl),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildStatBox(
    String label,
    String value, {
    VoidCallback? onTap,
    bool showTopUpAction = false,
  }) {
    final boxContent = Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: showTopUpAction
          ? BoxDecoration(
              color: AppColors.goldPale.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: AppColors.goldBorder),
            )
          : AppCard.cream,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: GoogleFonts.ibmPlexSans(fontSize: 11, color: AppColors.ink4)),
              if (showTopUpAction)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: AppColors.goldDeep,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    '+ ADD',
                    style: GoogleFonts.ibmPlexSans(
                      fontSize: 8,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 2),
          Text(value, style: GoogleFonts.ibmPlexMono(fontFeatures: const [FontFeature.tabularFigures()], fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.ink)),
        ],
      ),
    );

    return Expanded(
      child: onTap != null
          ? GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
              child: boxContent,
            )
          : boxContent,
    );
  }

  Widget _buildActionTile(IconData icon, String label, {required VoidCallback onTap}) => Expanded(
        child: Material(
          color: AppColors.pureWhite,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md), side: BorderSide(color: AppColors.birch)),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Column(children: [
                Icon(icon, size: 20, color: AppColors.goldMid),
                const SizedBox(height: 4),
                Text(label, style: AppFonts.sans(size: 11.5, weight: FontWeight.w500, color: AppColors.ink)),
              ]),
            ),
          ),
        ),
      );

  /// Titans Room entry: chat, support tickets and the wishlist in one place.
  Widget _buildRoomCard() => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.lg),
        child: Material(
          color: AppColors.pureWhite,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg), side: BorderSide(color: AppColors.birch)),
          child: ListTile(
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ChatScreen())),
            leading: Icon(Icons.forum_outlined, color: AppColors.goldMid),
            title: Row(children: [
              Text('Titans Room', style: AppText.bodyBold),
              const SizedBox(width: AppSpacing.sm),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: AppCard.badge(AppColors.bullLight),
                child: Text('LIVE', style: AppText.badge.copyWith(color: AppColors.bull)),
              ),
            ]),
            subtitle: Text('Chat, support tickets & wishlist', style: AppText.bodySmall),
            trailing: Icon(Icons.chevron_right_rounded, color: AppColors.ink4),
          ),
        ),
      );

  Widget _buildTickerCard(String name, String price, String change, bool isPositive) {
    return Container(
      width: 160,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: AppCard.primary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(name, style: GoogleFonts.ibmPlexSans(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.ink3), maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          Text(price, style: AppFonts.mono(size: 15, weight: FontWeight.w600, color: AppColors.ink)),
          const SizedBox(height: 2),
          Text('${isPositive ? '▲' : '▼'} $change', style: AppFonts.mono(size: 12, weight: FontWeight.w600, color: isPositive ? AppColors.bull : AppColors.bear)),
        ],
      ),
    );
  }
}
