import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/symbols.dart';
import '../../core/theme.dart';
import '../../core/app_constants.dart';
import '../../core/market_hours.dart';
import '../../core/money.dart';
import '../../core/option_pricing.dart';
import '../../models/portfolio.dart';
import '../../models/position_model.dart';
import '../../services/market_service.dart';
import '../../services/supabase_service.dart';
import '../../services/auth_service.dart';
import 'stock_detail_screen.dart';
import 'option_detail_screen.dart';
import 'order_entry_screen.dart';
import 'orders_screen.dart';
import 'analytics_screen.dart';
import 'autopsy_screen.dart';
import 'subscribe_screen.dart';
import '../../models/order.dart';
import '../../models/quote.dart';
import '../../widgets/auth_kit.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/empty_state.dart';
import '../../services/churn_telemetry_service.dart';
import '../../services/action_reaction_engine.dart';
import '../../services/nav_tab_service.dart';
import '../../services/theme_service.dart';
import 'package:provider/provider.dart';

/// Today's move of the last traded price against the previous close, in %.
double ltpDayChangePct(Holding h) {
  final prev = h.isNativeCurrency ? (h.nativePreviousClose ?? 0) : h.previousClose;
  return prev > 0 ? (h.displayCurrentPrice - prev) / prev * 100 : 0;
}

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
  int _view = 0; // 0 holdings, 1 F&O positions, 2 closed
  ({int open, int done})? _orderCounts;

  @override
  void initState() {
    super.initState();
    _load();
    _loadOrderCounts();
    _pollTimer = Timer.periodic(AppConstants.portfolioPoll, (_) => _refresh());
  }

  /// "1 open · 14 executed" on the Orders card.
  Future<void> _loadOrderCounts() async {
    try {
      final List<Order> orders = await _supabase.getOrders(limit: 200);
      if (!mounted) return;
      setState(() => _orderCounts = (
            open: orders.where((o) => o.status == 'pending').length,
            done: orders.where((o) => o.status == 'executed' || o.status == 'filled').length,
          ));
    } catch (_) {}
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

    // Valued at the session close while the market is shut, not at the wall clock.
    // THIS is the line behind "P&L keeps increasing after hours": carry and theta
    // both shrink as expiry approaches, so a live clock repriced the position every
    // hour with nothing trading. This screen had its OWN copy of the calculation, so
    // fixing supabase_service alone did not fix what the Portfolio tab displayed.
    final daysLeft = MarketHours.daysToExpiry(pos.expiry);
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
    final daysLeft = MarketHours.daysToExpiry(pos.expiry);
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

  static const _marketNames = {
    'stock': 'India', 'us_stock': 'US', 'crypto': 'Crypto', 'pakistan_stock': 'Pakistan', 'italy_stock': 'Italy'};

  /// Allocation of open holdings by market (derivatives grouped as F&O), as a
  /// stacked bar plus legend. Empty when nothing is held.
  List<Widget> _allocation() {
    final byMarket = <String, double>{};
    for (final h in _holdings.where((h) => h.quantity != 0 && h.current > 0)) {
      final key = h.instrumentType == 'EQUITY' ? (_marketNames[h.market] ?? h.market) : 'F&O';
      byMarket[key] = (byMarket[key] ?? 0) + h.current;
    }
    for (final p in _foPositions) {
      final v = _foCurrentValue(p);
      if (v > 0) byMarket['F&O'] = (byMarket['F&O'] ?? 0) + v;
    }
    final total = byMarket.values.fold<double>(0, (a, b) => a + b);
    if (total <= 0) return const [];
    final parts = byMarket.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final colors = [AppColors.goldMid, AppColors.titanGold, AppColors.violet, AppColors.ink4, AppColors.bull];
    Color c(int i) => colors[i % colors.length];
    return [
      const SizedBox(height: AppSpacing.md),
      ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Row(children: [
          for (var i = 0; i < parts.length; i++)
            Expanded(flex: (parts[i].value / total * 1000).round().clamp(1, 1000), child: Container(height: 8, color: c(i))),
        ]),
      ),
      const SizedBox(height: AppSpacing.sm),
      Wrap(spacing: AppSpacing.md, runSpacing: 4, children: [
        for (var i = 0; i < parts.length; i++)
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(color: c(i), borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 4),
            Text('${parts[i].key} ${(parts[i].value / total * 100).round()}%', style: AppText.bodySmall),
          ]),
      ]),
    ];
  }

  // ── Navigation and exits (unchanged behaviour, lifted out of the old cards) ──

  Future<void> _openHolding(Holding h) async {
    if (h.instrumentType == 'OPTION') {
      final underlyingSymbol = h.symbol.contains('-') ? h.symbol.split('-')[0] : h.symbol;
      final spotQuote = _quotes[MarketService.normalizeSymbol(underlyingSymbol, h.market)] ?? _quotes[underlyingSymbol];
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => OptionDetailScreen(
          optionData: {
            'symbol': h.symbol,
            'name': h.name,
            'strike_price': h.strikePrice ?? 0.0,
            'option_type': h.optionType ?? (h.symbol.endsWith('PE') ? 'PE' : 'CE'),
            'expiry_date': h.expiryDate ?? '',
            'price': h.currentPrice,
            'ltp': h.currentPrice,
            'previous_close': h.previousClose,
            'change': h.currentPrice - h.previousClose,
            'change_pct': h.previousClose > 0 ? ((h.currentPrice - h.previousClose) / h.previousClose) * 100 : 0.0,
          },
          underlyingSymbol: underlyingSymbol,
          underlyingSpotPrice: (spotQuote != null && spotQuote.price > 0) ? spotQuote.price : h.currentPrice,
          market: h.market,
        ),
      ));
    } else {
      await Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => StockDetailScreen(symbol: h.symbol, market: h.market, name: h.name)));
    }
    _load();
  }

  Future<void> _exitHolding(Holding h) async {
    ChurnTelemetryService.instance.recordButtonTap('portfolio_holding_quick_exit_btn', extra: {'sym': h.symbol});
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
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => OrderEntryScreen(
        quote: quote,
        isBuy: h.quantity < 0, // buy to cover a short, sell to close a long
        instrumentType: h.instrumentType,
        prefilledQuantity: h.quantity.abs(),
        isExitOrder: true,
      ),
    ));
    await _load();
    await _afterExit(
      stillOpen: _holdings.any((x) => x.symbol == h.symbol && x.market == h.market && x.quantity != 0),
      symbol: h.symbol,
      pnl: h.pnl,
    );
  }

  /// Once an exit really closed the position, records it and shows at most one
  /// honest reaction (loss recap or win-streak scaling). Backing out or a
  /// partial exit leaves it open: nothing recorded.
  // shortcut: the loss sign comes from the P&L estimated at exit, not the fill; read the closing order's netRealizedPnl if a near-zero trade is ever mislabelled.
  Future<void> _afterExit({required bool stillOpen, required String symbol, required double pnl}) async {
    if (stillOpen) return;
    ChurnTelemetryService.instance.recordTradeOutcome(symbol: symbol, isProfit: pnl >= 0, pnl: pnl);
    final auth = context.read<AuthService>();
    await auth.refreshUser();
    final r = await ActionReactionEngine.instance
        .onTradeClosed(symbol: symbol, pnl: pnl, walletAfter: auth.user?.walletBalance ?? 0);
    if (r == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(r.text),
      duration: const Duration(seconds: 8),
      action: r.action == null
          ? null
          : SnackBarAction(
              label: r.actionLabel!,
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => r.action == 'autopsy' ? const AutopsyScreen() : const SubscribeScreen())),
            ),
    ));
  }

  Future<void> _openFo(FoPosition pos) async {
    if (pos.instrumentType != 'OPTION') return;
    final estPrice = _estimateFoPrice(pos);
    final underlyingSymbol = pos.symbol.contains('-') ? pos.symbol.split('-')[0] : pos.symbol;
    final spotQuote = _quotes[MarketService.normalizeSymbol(underlyingSymbol, 'stock')] ?? _quotes[underlyingSymbol];
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => OptionDetailScreen(
        optionData: {
          'symbol': pos.symbol,
          'strike_price': pos.strikePrice,
          'option_type': pos.optionType,
          'expiry_date': pos.expiry.toIso8601String(),
          'price': estPrice,
          'ltp': estPrice,
          'previous_close': _estimateFoPreviousClose(pos),
          'lot_size': pos.lotSize,
          'open_interest': 0,
          'volume': 0,
        },
        underlyingSymbol: underlyingSymbol,
        underlyingSpotPrice: (spotQuote != null && spotQuote.price > 0) ? spotQuote.price : estPrice,
        market: 'stock',
      ),
    ));
    _load();
  }

  Future<void> _exitFo(FoPosition pos) async {
    // The same estimated price the row shows (carry for futures, Black-Scholes for options).
    final exitPrice = _estimateFoPrice(pos);
    final pnl = pos.unrealizedPnl(exitPrice);
    ChurnTelemetryService.instance.recordButtonTap('portfolio_holding_quick_exit_btn', extra: {'sym': pos.symbol});
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
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => OrderEntryScreen(
        quote: quote,
        isBuy: pos.netQty < 0,
        instrumentType: pos.instrumentType,
        strikePrice: pos.strikePrice > 0 ? pos.strikePrice : null,
        optionType: pos.optionType.isNotEmpty ? pos.optionType : null,
        expiryDate: pos.expiry.toIso8601String().split('T')[0],
        prefilledQuantity: (pos.netQty.abs() * pos.lotSize).toDouble(),
        isExitOrder: true,
        marginUsed: _foCapitalUsed(pos),
      ),
    ));
    await _load();
    await _afterExit(stillOpen: _foPositions.any((x) => x.id == pos.id && x.netQty != 0), symbol: pos.symbol, pnl: pnl);
  }

  // ── Layout ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final holdings = _holdings.where((h) => h.isEquity && h.quantity != 0).toList();
    final closed = _holdings.where((h) => h.quantity == 0).toList();
    final views = <(String, int)>[('Holdings', holdings.length), ('Positions', _foPositions.length), ('Closed', closed.length)];

    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 10, AppSpacing.lg, 10),
            child: Row(children: [
              Expanded(child: Text('Portfolio', style: AppFonts.sans(size: 22, weight: FontWeight.w700, color: AppColors.ink))),
              AuthIconButton(
                icon: Icons.show_chart_rounded,
                label: 'Analytics',
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AnalyticsScreen())),
              ),
              const SizedBox(width: 8),
              ListenableBuilder(
                listenable: ThemeService(),
                builder: (_, _) => AuthIconButton(
                  icon: AppColors.isDark ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
                  label: 'Toggle light or dark theme',
                  onTap: () => ThemeService().setThemeMode(AppColors.isDark ? ThemeMode.light : ThemeMode.dark),
                ),
              ),
            ]),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: _loading
                  ? const PortfolioSkeleton()
                  : ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        _summaryCard(),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 14, AppSpacing.lg, 10),
                          child: _segmented(views),
                        ),
                        // Holdings rows label their own numbers (Qty, Avg, Invested, LTP).
                        if (_view != 0) Container(
                          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 8),
                          decoration: BoxDecoration(border: Border.symmetric(horizontal: BorderSide(color: AppColors.birch))),
                          child: Row(children: [
                            Expanded(child: Text('INSTRUMENT · QTY × AVG', style: AppText.sectionLabel)),
                            Text('VALUE · P&L', style: AppText.sectionLabel),
                          ]),
                        ),
                        ...switch (_view) {
                          1 => _foPositions.isEmpty
                              ? [_empty('No open F&O positions', 'Futures and options you hold show here.', 'Trade F&O')]
                              : [for (final p in _foPositions) _foRow(p)],
                          2 => closed.isEmpty
                              ? [_empty('No closed positions', 'Trades you exit today show here with their realised P&L.', null)]
                              : [for (final h in closed) _holdingRow(h)],
                          _ => holdings.isEmpty
                              ? [_empty('No holdings yet', 'Start trading to build your portfolio.', 'Place a trade')]
                              : [for (final h in holdings) _holdingRow(h)],
                        },
                        _toolCards(),
                      ],
                    ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _summaryCard() {
    final up = _totalPnl >= 0, dayUp = _totalDayPnl >= 0;
    return Container(
      margin: const EdgeInsets.fromLTRB(AppSpacing.lg, 4, AppSpacing.lg, 0),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.pureWhite,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.birch),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('CURRENT VALUE', style: AppText.sectionLabel),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(Money.wallet(_totalCurrent, decimals: 2),
                    style: AppFonts.mono(size: 26, weight: FontWeight.w600, color: AppColors.ink)),
              ),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('TOTAL P&L', style: AppText.sectionLabel),
            Text(_fmtSigned(_totalPnl), style: AppFonts.mono(size: 18, weight: FontWeight.w600, color: up ? AppColors.bull : AppColors.bear)),
            Text('${up ? '+' : ''}${_totalPnlPct.toStringAsFixed(2)}%',
                style: AppFonts.mono(size: 12, color: up ? AppColors.bull : AppColors.bear)),
          ]),
        ]),
        Container(
          margin: const EdgeInsets.only(top: 14),
          padding: const EdgeInsets.only(top: 14),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: AppColors.birch))),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Deployed capital', style: AppFonts.sans(size: 11, color: AppColors.ink4)),
                Text(Money.wallet(_totalInvested, decimals: 2), style: AppFonts.mono(size: 14, weight: FontWeight.w500, color: AppColors.ink)),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('Today', style: AppFonts.sans(size: 11, color: AppColors.ink4)),
              Text(
                '${_fmtSigned(_totalDayPnl)}${_totalCurrent - _totalDayPnl > 0 ? ' (${(_totalDayPnl.abs() / (_totalCurrent - _totalDayPnl) * 100).toStringAsFixed(2)}%)' : ''}',
                style: AppFonts.mono(size: 14, weight: FontWeight.w500, color: dayUp ? AppColors.bull : AppColors.bear),
              ),
            ]),
          ]),
        ),
        ..._allocation(),
      ]),
    );
  }

  Widget _segmented(List<(String, int)> views) => Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: AppColors.cream, borderRadius: BorderRadius.circular(AppRadius.md)),
        child: Row(children: [
          for (final (i, (label, n)) in views.indexed) ...[
            if (i > 0) const SizedBox(width: 4),
            Expanded(
              child: Semantics(
                button: true,
                selected: _view == i,
                label: '$label ($n)',
                excludeSemantics: true,
                child: GestureDetector(
                  onTap: () => setState(() => _view = i),
                  child: Container(
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _view == i ? AppColors.pureWhite : Colors.transparent,
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Text('$label ($n)',
                        style: AppFonts.sans(size: 13, weight: FontWeight.w600, color: _view == i ? AppColors.ink : AppColors.ink3)),
                  ),
                ),
              ),
            ),
          ],
        ]),
      );

  Widget _tag(String text, {Color? fg, Color? bg}) => Container(
        margin: const EdgeInsets.only(left: 6),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: AppCard.badge(bg ?? AppColors.cream),
        child: Text(text, style: AppText.badge.copyWith(color: fg ?? AppColors.ink3)),
      );

  static const _exchange = {'stock': 'NSE', 'us_stock': 'US', 'crypto': 'CRYPTO', 'pakistan_stock': 'PSX', 'italy_stock': 'MIL'};

  /// One row: symbol + tags, "qty × avg", value, signed P&L, and an Exit chip
  /// while the position is open.
  Widget _row({
    required String symbol,
    required List<Widget> tags,
    required String qtyAvg,
    required String value,
    required String pnl,
    required bool up,
    required VoidCallback onTap,
    VoidCallback? onExit,
    bool dim = false,
  }) =>
      InkWell(
        onTap: onTap,
        child: Opacity(
          opacity: dim ? 0.75 : 1,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 12),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.birch))),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Flexible(child: Text(symbol, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.bodyBold)),
                    ...tags,
                  ]),
                  const SizedBox(height: 2),
                  Text(qtyAvg, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppFonts.mono(size: 12, color: AppColors.ink4)),
                ]),
              ),
              const SizedBox(width: 8),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(value, style: AppFonts.mono(size: 14, weight: FontWeight.w500, color: AppColors.ink)),
                Text('${up ? '▲' : '▼'} $pnl', style: AppFonts.mono(size: 12, color: up ? AppColors.bull : AppColors.bear)),
              ]),
              if (onExit != null) ...[
                const SizedBox(width: 8),
                Material(
                  color: AppColors.bearLight,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  child: InkWell(
                    onTap: onExit,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    child: Semantics(
                      button: true,
                      label: 'Exit $symbol',
                      excludeSemantics: true,
                      child: Container(
                        height: 32,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        alignment: Alignment.center,
                        child: Text('Exit', style: AppFonts.sans(size: 12, weight: FontWeight.w700, color: AppColors.bear)),
                      ),
                    ),
                  ),
                ),
              ],
            ]),
          ),
        ),
      );

  Widget _holdingRow(Holding h) {
    final closed = h.quantity == 0;
    if (!closed) return _openHoldingRow(h);
    final base = closed ? 0.0 : h.displayInvested;
    final pct = base > 0 ? h.displayPnl / base * 100 : 0.0;
    final pnl = '${Money.signedInstrument(h.displayPnl, market: h.market, decimals: 2)}'
        '${closed ? ' realised' : ' (${pct >= 0 ? '+' : '−'}${pct.abs().toStringAsFixed(2)}%)'}';
    return _row(
      symbol: displaySymbol(h.symbol),
      tags: [
        _tag(_exchange[h.market] ?? h.market.toUpperCase()),
        if (closed) _tag('CLOSED'),
        if (!closed && h.isShort) _tag('SHORT', fg: AppColors.bear, bg: AppColors.bearLight),
      ],
      qtyAvg: '${h.quantity.abs().toStringAsFixed(h.market == 'crypto' ? 6 : 0)} × ${Money.instrument(h.displayAvgPrice, market: h.market)}',
      value: closed ? '—' : Money.instrument(h.displayCurrentPrice * h.quantity.abs(), market: h.market),
      pnl: pnl,
      up: h.displayPnl >= 0,
      onTap: () => _openHolding(h),
      onExit: closed ? null : () => _exitHolding(h),
      dim: closed,
    );
  }

  /// Kite-style open holding: Qty · Avg and P&L %, symbol and P&L, then
  /// Invested and LTP with today's change.
  Widget _openHoldingRow(Holding h) {
    final up = h.displayPnl >= 0, pnlColor = up ? AppColors.bull : AppColors.bear;
    final day = ltpDayChangePct(h), dayColor = day >= 0 ? AppColors.bull : AppColors.bear;
    final pct = h.displayInvested > 0 ? h.displayPnl / h.displayInvested * 100 : 0.0;
    final muted = AppFonts.sans(size: 12, color: AppColors.ink4);
    final num = AppFonts.mono(size: 12, color: AppColors.ink2);
    String money(double v) => Money.instrument(v, market: h.market);
    return InkWell(
      onTap: () => _openHolding(h),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 12),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.birch))),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(text: 'Qty. ', style: muted),
                      TextSpan(text: h.quantity.abs().toStringAsFixed(h.market == 'crypto' ? 6 : 0), style: num),
                      TextSpan(text: '  •  Avg. ', style: muted),
                      TextSpan(text: money(h.displayAvgPrice), style: num),
                    ]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text('${pct >= 0 ? '+' : '−'}${pct.abs().toStringAsFixed(2)}%', style: AppFonts.mono(size: 12, color: pnlColor)),
              ]),
              const SizedBox(height: 4),
              Row(children: [
                Expanded(
                  child: Row(children: [
                    Flexible(child: Text(displaySymbol(h.symbol), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.bodyBold)),
                    _tag(_exchange[h.market] ?? h.market.toUpperCase()),
                    if (h.isShort) _tag('SHORT', fg: AppColors.bear, bg: AppColors.bearLight),
                  ]),
                ),
                const SizedBox(width: 8),
                Text(Money.signedInstrument(h.displayPnl, market: h.market, decimals: 2),
                    style: AppFonts.mono(size: 15, weight: FontWeight.w600, color: pnlColor)),
              ]),
              const SizedBox(height: 4),
              Row(children: [
                Expanded(
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(text: 'Invested ', style: muted),
                      TextSpan(text: money(h.displayInvested), style: num),
                    ]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text.rich(TextSpan(children: [
                  TextSpan(text: 'LTP ', style: muted),
                  TextSpan(text: money(h.displayCurrentPrice), style: num),
                  TextSpan(text: ' (${day >= 0 ? '+' : '−'}${day.abs().toStringAsFixed(2)}%)', style: AppFonts.mono(size: 12, color: dayColor)),
                ])),
              ]),
            ]),
          ),
          const SizedBox(width: 10),
          Material(
            color: AppColors.bearLight,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: InkWell(
              onTap: () => _exitHolding(h),
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: Semantics(
                button: true,
                label: 'Exit ${h.symbol}',
                excludeSemantics: true,
                child: Container(
                  height: 32,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  alignment: Alignment.center,
                  child: Text('Exit', style: AppFonts.sans(size: 12, weight: FontWeight.w700, color: AppColors.bear)),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _foRow(FoPosition pos) {
    final est = _estimateFoPrice(pos);
    final pnl = pos.unrealizedPnl(est), pct = pos.unrealizedPnlPct(est);
    final name = pos.instrumentType == 'OPTION'
        ? '${pos.symbol.split('-').first} ${pos.strikePrice.toStringAsFixed(0)} ${pos.optionType}'
        : '${pos.symbol.split(' ').first} FUT';
    return _row(
      symbol: name,
      tags: [
        _tag('NFO'),
        _tag(pos.netQty > 0 ? 'LONG' : 'SHORT',
            fg: pos.netQty > 0 ? AppColors.bull : AppColors.bear, bg: pos.netQty > 0 ? AppColors.bullLight : AppColors.bearLight),
      ],
      qtyAvg: '${pos.netQty.abs()} lot × ${pos.lotSize} @ ${Money.wallet(pos.avgEntryPrice, decimals: 2)}',
      value: Money.wallet(_foCurrentValue(pos), decimals: 2),
      pnl: '${_fmtSigned(pnl)} (${pct >= 0 ? '+' : '−'}${pct.abs().toStringAsFixed(2)}%)',
      up: pnl >= 0,
      onTap: () => _openFo(pos),
      onExit: () => _exitFo(pos),
    );
  }

  Widget _empty(String title, String message, String? action) => SizedBox(
        height: 240,
        child: EmptyState(
          icon: Icons.inventory_2_outlined,
          title: title,
          message: message,
          actionLabel: action,
          onAction: action == null ? null : () => NavTabService.goToTab(NavTabService.trade),
        ),
      );

  Widget _toolCards() {
    Widget card(IconData icon, String title, String sub, Widget screen) => Expanded(
          child: Material(
            color: AppColors.pureWhite,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md), side: BorderSide(color: AppColors.birch)),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.md),
              onTap: () async {
                await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
                _load();
              },
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(icon, size: 20, color: AppColors.goldMid),
                  const SizedBox(height: 6),
                  Text(title, style: AppText.bodyBold),
                  Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppFonts.sans(size: 12, color: AppColors.ink4)),
                ]),
              ),
            ),
          ),
        );
    final o = _orderCounts;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Row(children: [
        card(Icons.manage_search_rounded, 'Trade autopsy', 'Why trades won or lost', const AutopsyScreen()),
        const SizedBox(width: 8),
        card(Icons.format_list_bulleted_rounded, 'Orders', o == null ? 'Open and executed' : '${o.open} open · ${o.done} executed',
            const OrdersScreen()),
      ]),
    );
  }
}
