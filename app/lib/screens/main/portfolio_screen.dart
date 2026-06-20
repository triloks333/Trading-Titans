import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/theme.dart';
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
    _pollTimer = Timer.periodic(const Duration(seconds: 12), (_) => _refresh());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final auth = Provider.of<AuthService>(context, listen: false);
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

      final quoteMap = <String, Quote>{};
      await Future.wait(uniqueSymbols.map((sym) async {
        try {
          final q = await MarketService.quote(sym, 'stock');
          if (q != null) {
            quoteMap[sym] = q;
            final norm = MarketService.normalizeSymbol(sym, 'stock');
            quoteMap[norm] = q;
          }
        } catch (_) {}
      }));

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

      final quoteMap = <String, Quote>{};
      await Future.wait(uniqueSymbols.map((sym) async {
        try {
          final q = await MarketService.quote(sym, 'stock');
          if (q != null) {
            quoteMap[sym] = q;
            final norm = MarketService.normalizeSymbol(sym, 'stock');
            quoteMap[norm] = q;
          }
        } catch (_) {}
      }));

      if (mounted) {
        setState(() {
          _holdings = holdingsData;
          _foPositions = foPositionsData;
          _quotes = quoteMap;
        });
      }
    } catch (_) {}
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
    if (v.abs() < 1) return '₹${v.toStringAsFixed(2)}';
    return '₹${v.toStringAsFixed(0)}';
  }

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
                                  '${_totalDayPnl >= 0 ? '+' : ''}${_fmt(_totalDayPnl.abs())}',
                                  color: _totalDayPnl >= 0 ? AppColors.bull : AppColors.bear,
                                ),
                                Container(width: 1, height: 32, color: AppColors.ink4.withValues(alpha: 0.3)),
                                _summaryCardItem(
                                  'Total P&L', 
                                  '${_totalPnl >= 0 ? '+' : ''}${_fmt(_totalPnl.abs())} (${_totalPnlPct.toStringAsFixed(2)}%)',
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
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: GoogleFonts.inter(fontSize: 11, color: AppColors.ink4, fontWeight: FontWeight.w500)),
          const SizedBox(height: 2),
          Text(value, style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.bold, color: color ?? AppColors.pureWhite)),
        ],
      ),
    );
  }

  Widget _buildHoldingsList(List<Holding> list) {
    if (list.isEmpty) {
      return _buildEmptyState(
        Icons.inventory_2_outlined,
        'No holdings yet',
        'Start trading equities to build your portfolio',
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

  Widget _buildEmptyState(IconData icon, String title, String subtitle) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: AppColors.ink5),
          const SizedBox(height: AppSpacing.md),
          Text(title, style: GoogleFonts.inter(color: AppColors.ink4, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(subtitle, style: GoogleFonts.inter(fontSize: 12, color: AppColors.ink5)),
        ],
      ),
    );
  }

  Widget _buildHoldingCard(Holding h) {
    final isClosed = h.quantity == 0;
    final isPositive = h.pnl >= 0;
    final dayIsPositive = h.dayPnl >= 0;

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
                        'LTP ₹${h.currentPrice.toStringAsFixed(2)}',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.bold,
                          color: AppColors.ink,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Builder(
                        builder: (context) {
                          final priceDiff = h.currentPrice - h.previousClose;
                          final pct = h.previousClose > 0 ? (priceDiff / h.previousClose) * 100 : 0.0;
                          final isPctPositive = pct >= 0;
                          return Text(
                            '${isPctPositive ? "+" : ""}${pct.toStringAsFixed(2)}%',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: isPctPositive ? AppColors.bull : AppColors.bear,
                            ),
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
                  _holdingStat('Avg', '₹${h.avgPrice.toStringAsFixed(2)}'),
                  _holdingStat('Invested', isClosed ? '₹0' : '₹${h.invested.toStringAsFixed(0)}'),
                  _holdingStat(
                    isClosed ? 'Realized P&L' : 'P&L',
                    '${isPositive ? '+' : '-'}₹${h.pnl.abs().toStringAsFixed(0)}',
                    valueColor: isPositive ? AppColors.bull : AppColors.bear,
                  ),
                  _holdingStat(
                    'Day P&L',
                    '${dayIsPositive ? '+' : '-'}₹${h.dayPnl.abs().toStringAsFixed(0)}',
                    valueColor: dayIsPositive ? AppColors.bull : AppColors.bear,
                  ),
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
                    'LTP ₹${estPrice.toStringAsFixed(2)}',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.bold,
                      color: AppColors.ink,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 2),
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
          const SizedBox(height: AppSpacing.sm),
          Divider(height: 1, color: AppColors.cream),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              _holdingStat('Avg', '₹${pos.avgEntryPrice.toStringAsFixed(2)}'),
              _holdingStat('Invested', '₹${_foCapitalUsed(pos).toStringAsFixed(0)}'),
              _holdingStat(
                'P&L',
                '${isPositive ? '+' : '-'}₹${pnl.abs().toStringAsFixed(0)}',
                valueColor: isPositive ? AppColors.bull : AppColors.bear,
              ),
              _holdingStat(
                'Day P&L',
                '${dayPnlIsPositive ? '+' : '-'}₹${dayPnl.abs().toStringAsFixed(0)}',
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
                        ? '${pos.symbol} ${pos.optionType} ₹${pos.strikePrice.toStringAsFixed(0)}'
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
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: GoogleFonts.inter(fontSize: 10, color: AppColors.ink4)),
          const SizedBox(height: 1),
          Text(value, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: valueColor ?? AppColors.ink2)),
        ],
      ),
    );
  }
}
