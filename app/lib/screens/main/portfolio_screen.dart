import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../core/app_constants.dart';
import '../../core/money.dart';
import '../../core/option_pricing.dart';
import '../../models/portfolio.dart';
import '../../models/position_model.dart';
import '../../services/market_service.dart';
import '../../services/supabase_service.dart';
import '../../services/auth_service.dart';
import 'stock_detail_screen.dart';
import 'order_entry_screen.dart';
import 'orders_screen.dart';
import '../../models/quote.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/trend_arrow.dart';
import '../../widgets/stat_cell.dart';
import '../../services/nav_tab_service.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

class PortfolioScreen extends StatefulWidget {
  const PortfolioScreen({super.key});

  @override
  State<PortfolioScreen> createState() => _PortfolioScreenState();
}

class _PortfolioScreenState extends State<PortfolioScreen> {
  final SupabaseService _supabase = SupabaseService();
  List<Holding> _holdings = [];
  List<FoPosition> _foPositions = [];
  Map<String, Quote> _quotes = {};
  bool _loading = true;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _load();
    _pollTimer = Timer.periodic(AppConstants.portfolioPoll, (_) => _refresh());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    // Capture the provider before any await to avoid using context across an
    // async gap.
    final auth = Provider.of<AuthService>(context, listen: false);
    // Cache-first: show the last-known holdings instantly; the skeleton only
    // shows on the very first load (no cache yet). Fresh data follows below.
    await _hydrateFromCache();
    try {
      final holdingsData = await _supabase.getHoldings();
      final foPositionsData = await _supabase.getFoPositions();
      await auth.refreshUser();
      
      // Fetch quotes for all required symbols (using underlying symbols for options and futures)
      final uniqueSymbols = <String>{};
      for (final h in holdingsData) {
        if (h.instrumentType == 'OPTION' && h.symbol.contains('-')) {
          uniqueSymbols.add(h.symbol.split('-')[0]);
        } else if (h.instrumentType == 'FUTURE') {
          String underlying = h.symbol;
          if (h.symbol.contains(' ')) {
            underlying = h.symbol.split(' ')[0];
          }
          uniqueSymbols.add(underlying);
        } else {
          uniqueSymbols.add(h.symbol);
        }
      }
      for (final p in foPositionsData) {
        if (p.instrumentType == 'OPTION' && p.symbol.contains('-')) {
          uniqueSymbols.add(p.symbol.split('-')[0]);
        } else if (p.instrumentType == 'FUTURE') {
          String underlying = p.symbol;
          if (p.symbol.contains(' ')) {
            underlying = p.symbol.split(' ')[0];
          }
          uniqueSymbols.add(underlying);
        } else {
          uniqueSymbols.add(p.symbol);
        }
      }

      final quoteMap = await _fetchQuoteMap(uniqueSymbols);

      if (mounted) {
        setState(() {
          _holdings = holdingsData;
          _foPositions = foPositionsData;
          _quotes = quoteMap;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  /// Renders previously cached holdings immediately so returning to the
  /// portfolio doesn't block on the network. No-op on first run (no cache).
  Future<void> _hydrateFromCache() async {
    try {
      final cached = await _supabase.getCachedHoldings();
      if (!mounted) return;
      if (cached.isNotEmpty) {
        setState(() {
          _holdings = cached;
          _loading = false;
        });
      }
    } catch (_) {}
  }

  Future<void> _refresh() async {
    try {
      final auth = Provider.of<AuthService>(context, listen: false);
      final holdingsData = await _supabase.getHoldings();
      final foPositionsData = await _supabase.getFoPositions();
      await auth.refreshUser();
      
      final uniqueSymbols = <String>{};
      for (final h in holdingsData) {
        if (h.instrumentType == 'OPTION' && h.symbol.contains('-')) {
          uniqueSymbols.add(h.symbol.split('-')[0]);
        } else if (h.instrumentType == 'FUTURE') {
          String underlying = h.symbol;
          if (h.symbol.contains(' ')) {
            underlying = h.symbol.split(' ')[0];
          }
          uniqueSymbols.add(underlying);
        } else {
          uniqueSymbols.add(h.symbol);
        }
      }
      for (final p in foPositionsData) {
        if (p.instrumentType == 'OPTION' && p.symbol.contains('-')) {
          uniqueSymbols.add(p.symbol.split('-')[0]);
        } else if (p.instrumentType == 'FUTURE') {
          String underlying = p.symbol;
          if (p.symbol.contains(' ')) {
            underlying = p.symbol.split(' ')[0];
          }
          uniqueSymbols.add(underlying);
        } else {
          uniqueSymbols.add(p.symbol);
        }
      }

      final quoteMap = await _fetchQuoteMap(uniqueSymbols);

      if (mounted) {
        setState(() {
          _holdings = holdingsData;
          _foPositions = foPositionsData;
          _quotes = quoteMap;
        });
      }
    } catch (_) {}
  }

  /// Fetches quotes for all [uniqueSymbols] (treated as stock underlyings) in a
  /// single batched server-cache read (with live fallback), then maps each by
  /// both its raw and normalized symbol — identical shape to the previous
  /// per-symbol fan-out, just fewer round-trips.
  Future<Map<String, Quote>> _fetchQuoteMap(Set<String> uniqueSymbols) async {
    final fetched = await MarketService.quotes(
      uniqueSymbols.map((s) => (symbol: s, market: 'stock')).toList(),
    );
    final quoteMap = <String, Quote>{};
    for (final sym in uniqueSymbols) {
      final q = fetched['$sym\x1Fstock'];
      if (q != null) {
        quoteMap[sym] = q;
        quoteMap[MarketService.normalizeSymbol(sym, 'stock')] = q;
      }
    }
    return quoteMap;
  }

  // Helper to estimate F&O position price
  double _estimateFoPrice(FoPosition pos) {
    final underlyingSymbol = (pos.instrumentType == 'OPTION' && pos.symbol.contains('-'))
        ? pos.symbol.split('-')[0]
        : (pos.instrumentType == 'FUTURE' && pos.symbol.contains(' '))
            ? pos.symbol.split(' ')[0]
            : pos.symbol;
    final normUnderlying = MarketService.normalizeSymbol(underlyingSymbol, 'stock');
    final spotQuote = _quotes[normUnderlying] ?? _quotes[underlyingSymbol];
    if (spotQuote == null || spotQuote.price <= 0) return pos.avgEntryPrice;
    final spotPrice = spotQuote.price;

    final daysLeft = pos.expiry.difference(DateTime.now()).inHours / 24.0;
    if (pos.instrumentType == 'FUTURE') {
      return OptionPricing.futurePrice(spot: spotPrice, daysToExpiry: daysLeft);
    } else {
      return OptionPricing.optionPremium(
        optionType: pos.optionType,
        spot: spotPrice,
        strike: pos.strikePrice,
        daysToExpiry: daysLeft,
      );
    }
  }

  // Helper to estimate F&O position previous close price
  double _estimateFoPreviousClose(FoPosition pos) {
    if (pos.createdAt != null) {
      final localCreated = pos.createdAt!.toLocal();
      final now = DateTime.now();
      if (localCreated.year == now.year && localCreated.month == now.month && localCreated.day == now.day) {
        return pos.avgEntryPrice;
      }
    }

    final underlyingSymbol = (pos.instrumentType == 'OPTION' && pos.symbol.contains('-'))
        ? pos.symbol.split('-')[0]
        : (pos.instrumentType == 'FUTURE' && pos.symbol.contains(' '))
            ? pos.symbol.split(' ')[0]
            : pos.symbol;
    final normUnderlying = MarketService.normalizeSymbol(underlyingSymbol, 'stock');
    final spotQuote = _quotes[normUnderlying] ?? _quotes[underlyingSymbol];
    if (spotQuote == null || spotQuote.previousClose <= 0) return pos.avgEntryPrice;
    final spotPrevClose = spotQuote.previousClose;

    // Price the prior session by treating it as one extra day to expiry.
    final daysLeft = pos.expiry.difference(DateTime.now()).inHours / 24.0;
    if (pos.instrumentType == 'FUTURE') {
      return OptionPricing.futurePrice(spot: spotPrevClose, daysToExpiry: daysLeft + 1.0);
    } else {
      return OptionPricing.optionPremium(
        optionType: pos.optionType,
        spot: spotPrevClose,
        strike: pos.strikePrice,
        daysToExpiry: daysLeft + 1.0,
      );
    }
  }

  // Day P&L for F&O positions
  double _foDayPnl(FoPosition pos) {
    final currentPrice = _estimateFoPrice(pos);
    final previousClose = _estimateFoPreviousClose(pos);
    final totalUnits = pos.netQty.abs() * pos.lotSize;
    if (pos.netQty > 0) {
      return (currentPrice - previousClose) * totalUnits;
    } else {
      return (previousClose - currentPrice) * totalUnits;
    }
  }

  // Capital/Margin used for F&O
  double _foCapitalUsed(FoPosition pos) {
    if (pos.instrumentType == 'OPTION' && pos.netQty > 0) {
      // Long option - premium paid is the capital used
      return pos.avgEntryPrice * pos.netQty * pos.lotSize;
    } else {
      // Short option or future - blocked margin is the capital used
      return pos.marginBlocked;
    }
  }

  // Current contract value for F&O
  double _foCurrentValue(FoPosition pos) {
    final estPrice = _estimateFoPrice(pos);
    if (pos.instrumentType == 'OPTION' && pos.netQty > 0) {
      return estPrice * pos.netQty * pos.lotSize;
    } else {
      return pos.marginBlocked + pos.unrealizedPnl(estPrice);
    }
  }

  // P&L Metrics
  double get _totalInvested {
    final equityInvested = _holdings.where((h) => h.isEquity && h.quantity != 0).fold(0.0, (s, h) => s + h.invested);
    final foInvested = _foPositions.fold(0.0, (s, p) => s + _foCapitalUsed(p));
    return equityInvested + foInvested;
  }

  double get _totalCurrent {
    final equityCurrent = _holdings.where((h) => h.isEquity && h.quantity != 0).fold(0.0, (s, h) => s + h.current);
    final foCurrent = _foPositions.fold(0.0, (s, p) => s + _foCurrentValue(p));
    return equityCurrent + foCurrent;
  }

  double get _totalPnl => _totalCurrent - _totalInvested;
  double get _totalPnlPct => _totalInvested > 0 ? (_totalPnl / _totalInvested) * 100 : 0.0;

  double get _totalDayPnl {
    final equityDayPnl = _holdings.where((h) => h.isEquity && h.quantity != 0).fold(0.0, (s, h) => s + h.dayPnl);
    final foDayPnl = _foPositions.fold(0.0, (s, p) => s + _foDayPnl(p));
    return equityDayPnl + foDayPnl;
  }

  String _fmt(double v) {
    if (v.abs() < 1) return Money.wallet(v, decimals: 2);
    return Money.wallet(v, decimals: 0);
  }

  /// Signed amount, for anything that can be a gain or a loss.
  ///
  /// Every P&L call site used to work around [_fmt] being unsigned with
  /// `'${v >= 0 ? '+' : ''}${_fmt(v.abs())}'`. That ternary emits a plus for a
  /// gain and *nothing* for a loss, so `.abs()` then stripped the minus and a
  /// loss rendered as a bare positive number: "₹3654 (-2.27%)" in red, where the
  /// percentage carried the only clue that it was negative. Owning the sign here
  /// means no call site can drop it again.
  String _fmtSigned(double v) => '${v >= 0 ? '+' : '-'}${_fmt(v.abs())}';

  @override
  Widget build(BuildContext context) {
    final equityHoldings = _holdings.where((h) => h.isEquity && h.quantity != 0).toList();
    final closedPositions = _holdings.where((h) => h.quantity == 0).toList();

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        backgroundColor: AppColors.parchment,
        body: SafeArea(
          child: RefreshIndicator(
            onRefresh: _load,
            child: _loading
                ? const PortfolioSkeleton()
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Portfolio', style: GoogleFonts.inter(fontSize: 28, fontWeight: FontWeight.w900, color: AppColors.ink)),
                            const SizedBox(height: 2),
                            Text('Track your holdings and P&L', style: GoogleFonts.inter(fontSize: 13, color: AppColors.ink4)),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      
                      // Combined Summary Card (Aesthetic design upgrade)
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        decoration: BoxDecoration(
                          color: AppColors.ink,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: AppShadows.md,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('DEPLOYED CAPITAL', style: GoogleFonts.inter(fontSize: 10, color: AppColors.ink5, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
                            const SizedBox(height: 4),
                            Text(_fmt(_totalInvested), style: GoogleFonts.inter(fontSize: 32, fontWeight: FontWeight.w900, color: AppColors.pureWhite)),
                            const SizedBox(height: AppSpacing.lg),
                            Row(
                              children: [
                                _summaryCardItem('Current Value', _fmt(_totalCurrent)),
                                Container(width: 1, height: 32, color: AppColors.ink4.withValues(alpha: 0.3)),
                                _summaryCardItem(
                                  'Today P&L',
                                  _fmtSigned(_totalDayPnl),
                                  color: _totalDayPnl >= 0 ? AppColors.bull : AppColors.bear,
                                ),
                                Container(width: 1, height: 32, color: AppColors.ink4.withValues(alpha: 0.3)),
                                _summaryCardItem(
                                  'Total P&L', 
                                  '${_fmtSigned(_totalPnl)} (${_totalPnlPct.toStringAsFixed(2)}%)',
                                  color: _totalPnl >= 0 ? AppColors.bull : AppColors.bear,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      
                      TabBar(
                        isScrollable: true,
                        tabAlignment: TabAlignment.start,
                        labelColor: AppColors.ink,
                        unselectedLabelColor: AppColors.ink4,
                        indicatorColor: AppColors.imperialGold,
                        indicatorWeight: 3,
                        labelStyle: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13),
                        unselectedLabelStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13),
                        tabs: [
                          Tab(text: 'Holdings (${equityHoldings.length})'),
                          Tab(text: 'F&O Positions (${_foPositions.length})'),
                          Tab(text: 'Closed (${closedPositions.length})'),
                          const Tab(text: 'Orders'),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Expanded(
                        child: TabBarView(
                          children: [
                            _buildHoldingsList(equityHoldings),
                            _buildFoPositionsList(),
                            _buildClosedList(closedPositions),
                            const OrdersScreen(embedded: true),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _summaryCardItem(String label, String value, {Color? color}) {
    return StatCell(
      label: label,
      value: value,
      valueColor: color,
      labelSize: 11,
      labelWeight: FontWeight.w500,
      gap: 2,
      valueSize: 15,
      valueWeight: FontWeight.bold,
      defaultValueColor: AppColors.pureWhite,
    );
  }

  Widget _buildHoldingsList(List<Holding> list) {
    if (list.isEmpty) {
      return _buildEmptyState(
        Icons.inventory_2_outlined,
        'No holdings yet',
        'Start trading equities to build your portfolio',
        actionLabel: 'Place a trade',
        onAction: () => NavTabService.goToTab(NavTabService.trade),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      itemCount: list.length,
      itemBuilder: (context, index) => _buildHoldingCard(list[index]),
    );
  }

  Widget _buildFoPositionsList() {
    if (_foPositions.isEmpty) {
      return _buildEmptyState(
        Icons.trending_up_rounded,
        'No active F&O positions',
        'Live futures and options positions will show here',
        actionLabel: 'Trade F&O',
        onAction: () => NavTabService.goToTab(NavTabService.trade),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      itemCount: _foPositions.length,
      itemBuilder: (context, index) => _buildFoPositionCard(_foPositions[index]),
    );
  }

  Widget _buildClosedList(List<Holding> list) {
    if (list.isEmpty) {
      return _buildEmptyState(
        Icons.assignment_turned_in_outlined,
        'No closed positions',
        'Completed trades will appear here after exit',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      itemCount: list.length,
      itemBuilder: (context, index) => _buildHoldingCard(list[index]),
    );
  }

  Widget _buildEmptyState(
    IconData icon,
    String title,
    String subtitle, {
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    return EmptyState(
      icon: icon,
      title: title,
      message: subtitle,
      actionLabel: actionLabel,
      onAction: onAction,
    );
  }

  Widget _buildHoldingCard(Holding h) {
    final isClosed = h.quantity == 0;
    // Signs come from the displayed (native) figures so the colour always
    // matches the number next to it.
    final isPositive = h.displayPnl >= 0;
    final dayIsPositive = h.displayDayPnl >= 0;

    return GestureDetector(
      onTap: () async {
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => StockDetailScreen(symbol: h.symbol, market: h.market, name: h.name)),
        );
        _load();
      },
      child: Opacity(
        opacity: isClosed ? 0.75 : 1.0,
        child: Container(
          margin: const EdgeInsets.only(bottom: AppSpacing.sm),
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: AppCard.secondary,
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: isClosed ? AppColors.parchment : AppColors.goldPale,
                      shape: BoxShape.circle,
                      border: Border.all(color: isClosed ? AppColors.birch : AppColors.goldBorder),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      h.symbol.length >= 2 ? h.symbol.substring(0, 2) : h.symbol,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isClosed ? AppColors.ink4 : AppColors.goldDeep,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              h.symbol,
                              style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: AppColors.ink),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                            if (isClosed) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.ink5.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'CLOSED',
                                  style: GoogleFonts.inter(
                                    fontSize: 8,
                                    fontWeight: FontWeight.w900,
                                    color: AppColors.ink3,
                                  ),
                                ),
                              ),
                            ],
                            if (!isClosed && h.isShort) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.bear.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'SHORT',
                                  style: GoogleFonts.inter(
                                    fontSize: 8,
                                    fontWeight: FontWeight.w900,
                                    color: AppColors.bear,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${h.quantity.abs().toStringAsFixed(h.market == 'crypto' ? 4 : 0)} ${h.isShort ? 'units short' : 'shares'}',
                          style: GoogleFonts.inter(fontSize: 12, color: AppColors.ink4),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'LTP ${Money.instrument(h.displayCurrentPrice, market: h.market)}',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.bold,
                          color: AppColors.ink,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Builder(
                        builder: (context) {
                          // Ratio, so the currency does not matter — but taken
                          // from the native pair to avoid mixing an FX rate in.
                          final base = h.isNativeCurrency
                              ? (h.nativePreviousClose ?? h.displayCurrentPrice)
                              : h.previousClose;
                          final priceDiff = h.displayCurrentPrice - base;
                          final pct = base > 0 ? (priceDiff / base) * 100 : 0.0;
                          final isPctPositive = pct >= 0;
                          return Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              TrendArrow(isPositive: isPctPositive, size: 16),
                              Text(
                                '${isPctPositive ? "+" : ""}${pct.toStringAsFixed(2)}%',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: isPctPositive ? AppColors.bull : AppColors.bear,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Divider(height: 1, color: AppColors.cream),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  // A US position is shown entirely in dollars: cost basis, live
                  // price and P&L are all USD, so no rate enters the card.
                  _holdingStat('Avg', Money.instrument(h.displayAvgPrice, market: h.market)),
                  _holdingStat(
                    'Invested',
                    isClosed
                        ? Money.instrument(0, market: h.market, decimals: 0)
                        : Money.instrument(h.displayInvested, market: h.market, decimals: 0),
                  ),
                  _holdingStat(
                    // A closed position's realized figure is already net of the
                    // charges on the trades that closed it, so say so. The open
                    // case is a mark-to-market number with no charges in it yet.
                    isClosed ? 'Realized (net)' : 'P&L',
                    Money.signedInstrument(h.displayPnl, market: h.market, decimals: 0),
                    valueColor: isPositive ? AppColors.bull : AppColors.bear,
                  ),
                  // "Day P&L" is only meaningful while a position is still open.
                  // For a closed one the service sets dayPnl to the very same
                  // realized figure as P&L above, so the card printed the identical
                  // number twice under two different labels -- the single biggest
                  // source of "the portfolio shows different numbers" reports.
                  if (!isClosed)
                    _holdingStat(
                      'Day P&L',
                      Money.signedInstrument(h.displayDayPnl, market: h.market, decimals: 0),
                      valueColor: dayIsPositive ? AppColors.bull : AppColors.bear,
                    )
                  else
                    _holdingStat('Qty', '0'),
                ],
              ),
              if (!isClosed) ...[
                const SizedBox(height: AppSpacing.sm),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      style: TextButton.styleFrom(
                        backgroundColor: AppColors.bearLight,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.tag)),
                      ),
                      onPressed: () async {
                        final quote = Quote(
                          symbol: h.symbol,
                          yfSymbol: h.symbol,
                          name: h.name,
                          price: h.currentPrice,
                          previousClose: h.previousClose,
                          change: h.currentPrice - h.previousClose,
                          changePct: h.previousClose > 0 ? ((h.currentPrice - h.previousClose) / h.previousClose) * 100 : 0.0,
                          currency: 'INR',
                          market: h.market,
                        );
                        
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => OrderEntryScreen(
                              quote: quote,
                              isBuy: h.quantity < 0, // buy to cover if quantity is negative (short), sell to close if positive (long)
                              instrumentType: h.instrumentType,
                              prefilledQuantity: h.quantity.abs(),
                              isExitOrder: true,
                            ),
                          ),
                        );
                        _load();
                      },
                      child: Text(
                        'EXIT',
                        style: GoogleFonts.inter(
                          color: AppColors.bear,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFoPositionCard(FoPosition pos) {
    final estPrice = _estimateFoPrice(pos);
    final pnl = pos.unrealizedPnl(estPrice);
    final pnlPct = pos.unrealizedPnlPct(estPrice);
    final isPositive = pnl >= 0;
    final dayPnl = _foDayPnl(pos);
    final dayPnlIsPositive = dayPnl >= 0;
    
    final formattedQty = '${pos.netQty > 0 ? "+" : ""}${pos.netQty} Lot${pos.netQty.abs() > 1 ? "s" : ""}';
    final totalUnits = pos.netQty.abs() * pos.lotSize;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: AppCard.secondary,
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: pos.netQty > 0 ? AppColors.bull.withValues(alpha: 0.1) : AppColors.bear.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                  border: Border.all(color: pos.netQty > 0 ? AppColors.bull.withValues(alpha: 0.3) : AppColors.bear.withValues(alpha: 0.3)),
                ),
                alignment: Alignment.center,
                child: Text(
                  pos.instrumentType == 'OPTION' ? pos.optionType : 'FUT',
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: pos.netQty > 0 ? AppColors.bull : AppColors.bear,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pos.instrumentType == 'OPTION' 
                          ? '${pos.symbol} ${pos.expiry.month}/${pos.expiry.day} ${pos.strikePrice.toStringAsFixed(0)} ${pos.optionType}'
                          : '${pos.symbol} FUT',
                      style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: AppColors.ink, fontSize: 13),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$formattedQty ($totalUnits units)',
                      style: GoogleFonts.inter(fontSize: 12, color: AppColors.ink4),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'LTP ${Money.wallet(estPrice, decimals: 2)}',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.bold,
                      color: AppColors.ink,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TrendArrow(isPositive: isPositive, size: 16),
                      Text(
                        '${isPositive ? "+" : ""}${pnlPct.toStringAsFixed(2)}%',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isPositive ? AppColors.bull : AppColors.bear,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Divider(height: 1, color: AppColors.cream),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              _holdingStat('Avg', Money.wallet(pos.avgEntryPrice, decimals: 2)),
              _holdingStat('Invested', Money.wallet(_foCapitalUsed(pos), decimals: 0)),
              _holdingStat(
                'P&L',
                _fmtSigned(pnl),
                valueColor: isPositive ? AppColors.bull : AppColors.bear,
              ),
              _holdingStat(
                'Day P&L',
                _fmtSigned(dayPnl),
                valueColor: dayPnlIsPositive ? AppColors.bull : AppColors.bear,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                style: TextButton.styleFrom(
                  backgroundColor: AppColors.bearLight,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.tag)),
                ),
                onPressed: () async {
                  // Use the same estimated price shown on the card (futures carry / Black-Scholes for options)
                  final exitPrice = _estimateFoPrice(pos);
                  final capitalUsed = _foCapitalUsed(pos);
                  final quote = Quote(
                    symbol: pos.symbol,
                    yfSymbol: pos.symbol,
                    name: pos.instrumentType == 'OPTION'
                        ? '${pos.symbol} ${pos.optionType} ${Money.wallet(pos.strikePrice, decimals: 0)}'
                        : '${pos.symbol} FUT',
                    price: exitPrice,
                    previousClose: exitPrice,
                    change: 0,
                    changePct: 0,
                    currency: 'INR',
                    market: 'stock',
                  );
                  
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => OrderEntryScreen(
                        quote: quote,
                        isBuy: pos.netQty < 0, // Buy to cover if negative, Sell to close if positive
                        instrumentType: pos.instrumentType,
                        strikePrice: pos.strikePrice > 0 ? pos.strikePrice : null,
                        optionType: pos.optionType.isNotEmpty ? pos.optionType : null,
                        expiryDate: pos.expiry.toIso8601String().split('T')[0],
                        prefilledQuantity: (pos.netQty.abs() * pos.lotSize).toDouble(),
                        isExitOrder: true,
                        marginUsed: capitalUsed,
                      ),
                    ),
                  );
                  _load();
                },
                child: Text(
                  'EXIT',
                  style: GoogleFonts.inter(
                    color: AppColors.bear,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _holdingStat(String label, String value, {Color? valueColor}) {
    return StatCell(label: label, value: value, valueColor: valueColor);
  }
}
