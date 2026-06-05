import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:showcaseview/showcaseview.dart';
import '../../core/theme.dart';
import '../../widgets/crown_logo.dart';
import '../../widgets/titan_showcase.dart';
import '../../services/supabase_service.dart';
import '../../services/auth_service.dart';
import '../../models/quote.dart';
import '../../models/portfolio.dart';
import 'stock_detail_screen.dart';
import 'analytics_screen.dart';
import 'autopsy_screen.dart';
import 'subscribe_screen.dart';
import 'trade_screen.dart';
import 'whatif_screen.dart';
import 'orders_screen.dart';
import 'notifications_screen.dart';
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
    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) => _refreshPrices());
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
    setState(() => _loading = true);
    try {
      final auth = context.read<AuthService>();
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
    }
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
    ShowCaseWidget.of(context).startShowCase([
      _guideKey,
      _notificationsKey,
      _totalValueKey,
      _actionsKey,
      _pulseKey,
    ]);
  }

  String _formatValue(double value) {
    if (value.abs() < 1) return '₹${value.toStringAsFixed(2)}';
    return '₹${value.toStringAsFixed(0)}';
  }

  double get investedValue => _holdings.fold(0.0, (sum, holding) => sum + holding.invested);
  double get currentValue => _holdings.fold(0.0, (sum, holding) => sum + holding.current);
  double get unrealizedPnl => _holdings.fold(0.0, (sum, holding) => sum + holding.pnl);
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
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const CrownLogo(size: 36, withRing: false),
                              const SizedBox(width: AppSpacing.sm),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Welcome,', style: GoogleFonts.inter(fontSize: 12, color: AppColors.ink4)),
                                  Text(user?.name ?? 'Titan', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.ink)),
                                ],
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              // Guide Button (Question Mark)
                              TitanShowcase(
                                showcaseKey: _guideKey,
                                title: 'Interactive Guide',
                                description: 'Tap this question mark to launch the tour guide again anytime you want a walkthrough.',
                                child: GestureDetector(
                                  onTap: _startGuide,
                                  child: Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: AppColors.cream,
                                      shape: BoxShape.circle,
                                      border: Border.all(color: AppColors.birch),
                                    ),
                                    child:       Icon(Icons.help_outline, size: 20, color: AppColors.ink2),
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
                                  onTap: () async {
                                    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NotificationsScreen()));
                                    _loadUnreadNotificationsCount();
                                  },
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
                              const SizedBox(width: AppSpacing.xs),
                              // Order History Button
                              GestureDetector(
                                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const OrdersScreen())),
                                child: Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: AppColors.cream,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: AppColors.birch),
                                  ),
                                  child:       Icon(Icons.receipt_outlined, size: 20, color: AppColors.ink2),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.lg),
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
                              Text('TOTAL PORTFOLIO VALUE', style: AppText.sectionLabel),
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
                                      '${_formatValue(totalPnL)} (${unrealizedPnlPct.toStringAsFixed(2)}%)',
                                      style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: isPositive ? AppColors.bull : AppColors.bear),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: AppSpacing.lg),
                              Row(
                                children: [
                                  _buildStatBox('Wallet', _formatValue(user?.walletBalance ?? 0.0)),
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
                      if ((user?.walletBalance ?? 0) < 200000)
                        GestureDetector(
                          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SubscribeScreen())),
                          child: Container(
                            padding: const EdgeInsets.all(AppSpacing.lg),
                            decoration: AppCard.darkCta,
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('Need more demo capital?', style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.bold, color: AppColors.goldLight)),
                                      const SizedBox(height: 2),
                                      Text('Top-up plans from ₹199 · Up to ₹10,00,000', style: GoogleFonts.inter(fontSize: 12, color: AppColors.parchment)),
                                    ],
                                  ),
                                ),
                                      Icon(Icons.arrow_forward, color: AppColors.parchment, size: 20),
                              ],
                            ),
                          ),
                        ),
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
                            Text('Market Pulse', style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.ink)),
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
                      if (_holdings.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.xl),
                        Text('Your Holdings', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.ink)),
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
                                        Text(holding.symbol, style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: AppColors.ink)),
                                        Text('${holding.quantity.toStringAsFixed(holding.market == 'crypto' ? 4 : 0)} units · avg ${_formatValue(holding.avgPrice)}', style: GoogleFonts.inter(color: AppColors.ink4)),
                                      ],
                                    ),
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(_formatValue(holding.current), style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: AppColors.ink)),
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
                        Text('Watchlist', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.ink)),
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
                                        Text(quote.symbol, style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: AppColors.ink)),
                                        Text(quote.name, style: GoogleFonts.inter(color: AppColors.ink4)),
                                      ],
                                    ),
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(_formatValue(quote.price), style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: AppColors.ink)),
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

  Widget _buildStatBox(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: AppCard.cream,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: GoogleFonts.inter(fontSize: 11, color: AppColors.ink4)),
            const SizedBox(height: 2),
            Text(value, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.ink)),
          ],
        ),
      ),
    );
  }

  Widget _buildActionTile(IconData icon, String label, {required VoidCallback onTap}) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          decoration: AppCard.secondary,
          child: Column(
            children: [
              Container(
                width: 36,
                height: 36,
                margin: const EdgeInsets.only(bottom: 4),
                decoration:       BoxDecoration(
                  color: AppColors.goldPale,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 20, color: AppColors.goldDeep),
              ),
              Text(label, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.ink2)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTickerCard(String name, String price, String change, bool isPositive) {
    return Container(
      width: 160,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: AppCard.primary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(name, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.ink3), maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          Text(price, style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.ink)),
          const SizedBox(height: 2),
          Text(change, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: isPositive ? AppColors.bull : AppColors.bear)),
        ],
      ),
    );
  }
}
