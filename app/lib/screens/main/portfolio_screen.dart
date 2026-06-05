import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../models/portfolio.dart';
import '../../services/supabase_service.dart';
import '../../services/auth_service.dart';
import 'stock_detail_screen.dart';
import 'order_entry_screen.dart';
import '../../models/quote.dart';
import '../../utils/lot_size.dart';
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
    setState(() => _loading = true);
    try {
      final auth = Provider.of<AuthService>(context, listen: false);
      final results = await Future.wait([
        _supabase.getHoldings(),
        auth.refreshUser(),
      ]);
      if (mounted) {
        setState(() {
          _holdings = results[0] as List<Holding>;
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
      final results = await Future.wait([
        _supabase.getHoldings(),
        auth.refreshUser(),
      ]);
      if (mounted) {
        setState(() {
          _holdings = results[0] as List<Holding>;
        });
      }
    } catch (_) {}
  }

  double get _totalInvested => _holdings.fold(0.0, (s, h) => s + h.invested);
  double get _totalCurrent => _holdings.fold(0.0, (s, h) => s + h.current);
  double get _totalPnl => _totalCurrent - _totalInvested;
  double get _totalPnlPct => _totalInvested > 0 ? (_totalPnl / _totalInvested) * 100 : 0.0;
  double get _totalDayPnl => _holdings.fold(0.0, (s, h) => s + h.dayPnl);

  String _fmt(double v) {
    if (v.abs() < 1) return '₹${v.toStringAsFixed(2)}';
    return '₹${v.toStringAsFixed(0)}';
  }

  @override
  Widget build(BuildContext context) {
    final equityHoldings = _holdings.where((h) => h.isEquity && h.quantity > 0).toList();
    final optionPositions = _holdings.where((h) => (h.isOption || h.instrumentType == 'FUTURE' || h.quantity < 0) && h.quantity != 0).toList();
    final closedPositions = _holdings.where((h) => h.quantity == 0).toList();

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        body: SafeArea(
          child: RefreshIndicator(
            onRefresh: _load,
            child: _loading
                ? const Center(child: CircularProgressIndicator())
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
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        decoration: AppCard.primary,
                        child: Column(
                          children: [
                            Row(
                              children: [
                                _summaryItem('Invested', _fmt(_totalInvested)),
                                const SizedBox(width: AppSpacing.sm),
                                _summaryItem('Current', _fmt(_totalCurrent)),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.md),
                            Row(
                              children: [
                                _summaryItem(
                                  'P&L',
                                  '${_totalPnl >= 0 ? '+' : ''}${_fmt(_totalPnl.abs())}',
                                  valueColor: _totalPnl >= 0 ? AppColors.bull : AppColors.bear,
                                ),
                                const SizedBox(width: AppSpacing.sm),
                                _summaryItem(
                                  'Today',
                                  '${_totalDayPnl >= 0 ? '+' : ''}${_fmt(_totalDayPnl.abs())}',
                                  valueColor: _totalDayPnl >= 0 ? AppColors.bull : AppColors.bear,
                                ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            Text(
                              '${_totalPnlPct >= 0 ? '+' : ''}${_totalPnlPct.toStringAsFixed(2)}% overall',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: _totalPnl >= 0 ? AppColors.bull : AppColors.bear,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      TabBar(
                        labelColor: AppColors.ink,
                        unselectedLabelColor: AppColors.ink4,
                        indicatorColor: AppColors.imperialGold,
                        indicatorWeight: 3,
                        labelStyle: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13),
                        unselectedLabelStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13),
                        tabs: [
                          Tab(text: 'Holdings (${equityHoldings.length})'),
                          Tab(text: 'Positions (${optionPositions.length})'),
                          Tab(text: 'Closed (${closedPositions.length})'),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Expanded(
                        child: TabBarView(
                          children: [
                            _buildHoldingsTab(equityHoldings, type: 'holdings'),
                            _buildHoldingsTab(optionPositions, type: 'positions'),
                            _buildHoldingsTab(closedPositions, type: 'closed'),
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

  Widget _buildHoldingsTab(List<Holding> list, {required String type}) {
    if (list.isEmpty) {
      IconData icon = Icons.inventory_2_outlined;
      String title = 'No holdings yet';
      String subtitle = 'Start trading to build your portfolio';
      if (type == 'positions') {
        icon = Icons.trending_up_rounded;
        title = 'No active positions';
        subtitle = 'Open derivatives and F&O positions will show here';
      } else if (type == 'closed') {
        icon = Icons.assignment_turned_in_outlined;
        title = 'No closed positions';
        subtitle = 'Closed positions for the day will appear here';
      }
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: AppColors.ink5),
            const SizedBox(height: AppSpacing.md),
            Text(title, style: GoogleFonts.inter(color: AppColors.ink4)),
            const SizedBox(height: 4),
            Text(subtitle, style: GoogleFonts.inter(fontSize: 12, color: AppColors.ink5)),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      itemCount: list.length,
      itemBuilder: (context, index) => _buildHoldingCard(list[index]),
    );
  }

  Widget _summaryItem(String label, String value, {Color? valueColor}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: AppCard.cream,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: GoogleFonts.inter(fontSize: 11, color: AppColors.ink4)),
            const SizedBox(height: 2),
            Text(value, style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, color: valueColor ?? AppColors.ink)),
          ],
        ),
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
                                  color: AppColors.ink5.withAlpha(38),
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
                          ],
                        ),
                        const SizedBox(height: 2),
                        Builder(
                          builder: (context) {
                            if (isClosed) {
                              return Text(
                                '0 shares',
                                style: GoogleFonts.inter(fontSize: 12, color: AppColors.ink4),
                              );
                            }
                             final isDerivative = h.instrumentType == 'OPTION' || h.instrumentType == 'FUTURE' || h.symbol.contains('-CE') || h.symbol.contains('-PE') || h.symbol.toUpperCase().contains('FUT');
                             final lotSize = isDerivative ? getOptionLotSize(h.symbol) : 1;
                             final numLots = h.quantity / lotSize;
                             final qtyText = isDerivative
                                 ? '${numLots.toStringAsFixed(1).replaceAll('.0', '')} lot${numLots.abs() == 1 ? '' : 's'} (${h.quantity.toInt()} units)'
                                 : '${h.quantity.toStringAsFixed(h.market == 'crypto' ? 4 : 0)} shares';
                            return Text(
                              qtyText,
                              style: GoogleFonts.inter(fontSize: 12, color: AppColors.ink4),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Builder(
                        builder: (context) {
                          return Text(
                            'LTP ₹${h.currentPrice.toStringAsFixed(2)}',
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.bold,
                              color: AppColors.ink,
                              fontSize: 13,
                            ),
                          );
                        },
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
                    '${isPositive ? '+' : ''}₹${h.pnl.abs().toStringAsFixed(0)}',
                    valueColor: isPositive ? AppColors.bull : AppColors.bear,
                  ),
                  _holdingStat(
                    'Day P&L',
                    '${dayIsPositive ? '+' : ''}₹${h.dayPnl.abs().toStringAsFixed(0)}',
                    valueColor: dayIsPositive ? AppColors.bull : AppColors.bear,
                  ),
                ],
              ),
              if (!isClosed) ...[
                const SizedBox(height: AppSpacing.md),
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
                          changePct: h.previousClose > 0 
                              ? ((h.currentPrice - h.previousClose) / h.previousClose) * 100 
                              : 0.0,
                          currency: 'INR',
                          market: h.market,
                        );
                        
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => OrderEntryScreen(
                              quote: quote,
                              isBuy: h.quantity < 0, // buy to cover if quantity is negative (short), sell to close if positive (long)
                              instrumentType: h.instrumentType,
                              strikePrice: h.strikePrice,
                              optionType: h.optionType,
                              expiryDate: h.expiryDate,
                              prefilledQuantity: h.quantity.abs(),
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
