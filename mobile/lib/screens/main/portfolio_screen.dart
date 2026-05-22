import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../models/portfolio.dart';
import '../../services/supabase_service.dart';
import 'stock_detail_screen.dart';
import 'package:google_fonts/google_fonts.dart';

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
    final holdings = await _supabase.getHoldings();
    if (mounted) {
      setState(() {
        _holdings = holdings;
        _loading = false;
      });
    }
  }

  Future<void> _refresh() async {
    final holdings = await _supabase.getHoldings();
    if (mounted) setState(() => _holdings = holdings);
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
    return Scaffold(
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
                                'Total P&L',
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
                    const SizedBox(height: AppSpacing.lg),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                      child: Text(
                        'HOLDINGS (${_holdings.length})',
                        style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.ink4, letterSpacing: 0.5),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Expanded(
                      child: _holdings.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.inventory_2_outlined, size: 48, color: AppColors.ink5),
                                  const SizedBox(height: AppSpacing.md),
                                  Text('No holdings yet', style: GoogleFonts.inter(color: AppColors.ink4)),
                                  const SizedBox(height: 4),
                                  Text('Start trading to build your portfolio', style: GoogleFonts.inter(fontSize: 12, color: AppColors.ink5)),
                                ],
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                              itemCount: _holdings.length,
                              itemBuilder: (context, index) => _buildHoldingCard(_holdings[index]),
                            ),
                    ),
                  ],
                ),
        ),
      ),
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
    final isPositive = h.pnl >= 0;
    final dayIsPositive = h.dayPnl >= 0;

    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => StockDetailScreen(symbol: h.symbol, market: h.market, name: h.name)),
      ),
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
                    color: AppColors.goldPale,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.goldBorder),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    h.symbol.length >= 2 ? h.symbol.substring(0, 2) : h.symbol,
                    style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.goldDeep),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(h.symbol, style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: AppColors.ink)),
                      Text('${h.quantity.toStringAsFixed(h.market == 'crypto' ? 4 : 0)} shares',
                          style: GoogleFonts.inter(fontSize: 12, color: AppColors.ink4)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('₹${h.currentPrice.toStringAsFixed(2)}', style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: AppColors.ink)),
                    Text(
                      '${isPositive ? '+' : ''}${h.pnlPct.toStringAsFixed(2)}%',
                      style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: isPositive ? AppColors.bull : AppColors.bear),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            const Divider(height: 1, color: AppColors.cream),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                _holdingStat('Avg', '₹${h.avgPrice.toStringAsFixed(2)}'),
                _holdingStat('Invested', '₹${h.invested.toStringAsFixed(0)}'),
                _holdingStat(
                  'P&L',
                  '${isPositive ? '+' : ''}₹${h.pnl.abs().toStringAsFixed(0)}',
                  valueColor: isPositive ? AppColors.bull : AppColors.bear,
                ),
                _holdingStat(
                  'Day',
                  '${dayIsPositive ? '+' : ''}₹${h.dayPnl.abs().toStringAsFixed(0)}',
                  valueColor: dayIsPositive ? AppColors.bull : AppColors.bear,
                ),
              ],
            ),
          ],
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
