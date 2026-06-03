import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../models/quote.dart';
import '../../models/portfolio.dart';
import '../../services/market_service.dart';
import '../../services/supabase_service.dart';
import '../../core/market_hours.dart';
import 'fullscreen_chart_screen.dart';
import 'package:google_fonts/google_fonts.dart';
import 'order_entry_screen.dart';
import 'option_chain_screen.dart';
import '../../widgets/tradingview_chart.dart';

class StockDetailScreen extends StatefulWidget {
  final String symbol;
  final String market;
  final String name;

  const StockDetailScreen({super.key, required this.symbol, required this.market, required this.name});

  @override
  State<StockDetailScreen> createState() => _StockDetailScreenState();
}

class _StockDetailScreenState extends State<StockDetailScreen> {
  Quote? _quote;
  bool _isWatched = false;
  Holding? _holding;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _loadData();
    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) => _refreshQuote());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    await Future.wait([_refreshQuote(), _loadUserData()]);
  }

  Future<void> _refreshQuote() async {
    final quote = await MarketService.quote(widget.symbol, widget.market);
    if (mounted) setState(() => _quote = quote);
  }


  Future<void> _loadUserData() async {
    final holdings = await SupabaseService().getHoldings();
    final watchCheck = await SupabaseService().isWatched(widget.symbol, widget.market);
    final holding = holdings.where((h) => h.symbol == widget.symbol && h.market == widget.market).firstOrNull;
    if (mounted) {
      setState(() {
        _isWatched = watchCheck;
        _holding = holding;
      });
    }
  }

  Future<void> _toggleWatch() async {
    setState(() => _isWatched = !_isWatched);
    try {
      if (_isWatched) {
        await SupabaseService().addToWatchlist(widget.symbol, widget.market, widget.name);
      } else {
        await SupabaseService().removeFromWatchlist(widget.symbol, widget.market);
      }
    } catch (_) {
      setState(() => _isWatched = !_isWatched);
    }
  }


  bool get _isUp => (_quote?.change ?? 0) >= 0;
  Color get _changeColor => _isUp ? AppColors.bull : AppColors.bear;

  @override
  Widget build(BuildContext context) {
    final q = _quote;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.symbol),
        backgroundColor: AppColors.parchment,
        actions: [
          IconButton(
            icon: Icon(_isWatched ? Icons.star : Icons.star_border, color: _isWatched ? AppColors.goldDeep : AppColors.ink4),
            onPressed: _toggleWatch,
          ),
        ],
      ),
      body: q == null
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              top: false,
              child: Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildPriceCard(q),
                          const SizedBox(height: AppSpacing.lg),
                          _buildChartCard(q),
                          const SizedBox(height: AppSpacing.lg),
                          Row(
                            children: [
                              Expanded(
                                child: _buildViewChartButton(),
                              ),
                              if (widget.market == 'stock') ...[
                                const SizedBox(width: AppSpacing.md),
                                Expanded(
                                  child: _buildOptionChainButton(),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          _buildMarketStatus(),
                          const SizedBox(height: AppSpacing.lg),
                          _buildStatsCard(q),
                          if (_holding != null) ...[
                            const SizedBox(height: AppSpacing.lg),
                            _buildPositionCard(),
                          ],
                          const SizedBox(height: AppSpacing.lg),
                        ],
                      ),
                    ),
                  ),
                  _buildBottomBar(),
                ],
              ),
            ),
    );
  }

  Widget _buildPriceCard(Quote q) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.pureWhite,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: AppColors.birch),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.name, style: const TextStyle(color: AppColors.ink4, fontSize: 13)),
          const SizedBox(height: AppSpacing.sm),
          Text('₹${q.price.toStringAsFixed(2)}',
              style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: AppColors.ink)),
          const SizedBox(height: AppSpacing.sm),
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 6),
              decoration: BoxDecoration(
                color: _isUp ? AppColors.bullLight : AppColors.bearLight,
                borderRadius: BorderRadius.circular(AppRadius.tag),
              ),
              child: Text(
                '${_isUp ? '+' : ''}${q.change.toStringAsFixed(2)} (${q.changePct.toStringAsFixed(2)}%)',
                style: TextStyle(color: _changeColor),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(q.market.toUpperCase(), style: const TextStyle(color: AppColors.ink4)),
          ]),
        ],
      ),
    );
  }

  Widget _buildChartCard(Quote q) {
    return Container(
      height: 350,
      decoration: BoxDecoration(
        color: const Color(0xFF131722),
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: AppColors.birch),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.xl - 1),
        child: Stack(
          children: [
            TradingViewChart(
              symbol: widget.symbol,
              market: widget.market,
            ),
            Positioned(
              top: 12,
              right: 12,
              child: Material(
                color: Colors.black.withValues(alpha: 0.6),
                shape: const CircleBorder(),
                child: IconButton(
                  icon: const Icon(Icons.fullscreen_rounded, color: Colors.white),
                  onPressed: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => FullscreenChartScreen(
                          symbol: widget.symbol,
                          market: widget.market,
                          name: widget.name,
                          quote: _quote,
                        ),
                      ),
                    );
                    _loadData();
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsCard(Quote q) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.pureWhite,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: AppColors.birch),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Key Stats',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.ink)),
          const SizedBox(height: AppSpacing.md),
          _statRow('Previous Close', '₹${q.previousClose.toStringAsFixed(2)}'),
          _divider(),
          _statRow('Day Change',
              '${_isUp ? '+' : ''}${q.change.toStringAsFixed(2)} (${_isUp ? '+' : ''}${q.changePct.toStringAsFixed(2)}%)',
              valueColor: _changeColor),
          _divider(),
          _statRow('Market', q.market == 'crypto' ? 'Crypto' : 'NSE/BSE'),
          _divider(),
          _statRow('Currency', q.currency),
        ],
      ),
    );
  }

  Widget _statRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AppColors.ink4, fontSize: 13)),
          Text(value,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: valueColor ?? AppColors.ink,
              )),
        ],
      ),
    );
  }

  Widget _divider() {
    return Divider(height: 1, color: AppColors.cream);
  }

  Widget _buildPositionCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.warmWhite,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: AppColors.birch),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Your Position',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.ink)),
          const SizedBox(height: AppSpacing.sm),
          Text('Quantity ${_holding!.quantity.toStringAsFixed(4)}',
              style: const TextStyle(color: AppColors.ink4)),
          const SizedBox(height: AppSpacing.xs),
          Text('Avg price ₹${_holding!.avgPrice.toStringAsFixed(2)}',
              style: const TextStyle(color: AppColors.ink4)),
        ],
      ),
    );
  }

  bool get _marketOpen => MarketHours.isOpen(widget.market);

  Widget _buildOptionChainButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        icon: const Icon(Icons.layers_outlined, color: AppColors.pureWhite),
        label: Text('VIEW OPTION CHAIN', style: GoogleFonts.inter(fontWeight: FontWeight.bold, letterSpacing: 0.5)),
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => OptionChainScreen(
                underlyingSymbol: widget.symbol,
                spotPrice: _quote?.price ?? 0.0,
                market: widget.market,
              ),
            ),
          );
          _loadData();
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.imperialGold,
          foregroundColor: AppColors.pureWhite,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
        ),
      ),
    );
  }

  Widget _buildViewChartButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        icon: const Icon(Icons.bar_chart_rounded, color: AppColors.pureWhite),
        label: Text('VIEW CHART', style: GoogleFonts.inter(fontWeight: FontWeight.bold, letterSpacing: 0.5)),
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => FullscreenChartScreen(
                symbol: widget.symbol,
                market: widget.market,
                name: widget.name,
                quote: _quote,
              ),
            ),
          );
          _loadData();
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.ink2,
          foregroundColor: AppColors.pureWhite,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
        ),
      ),
    );
  }

  Widget _buildMarketStatus() {
    final open = _marketOpen;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: open ? AppColors.bullLight : AppColors.bearLight,
        borderRadius: BorderRadius.circular(AppRadius.tag),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(open ? Icons.check_circle : Icons.lock, size: 14, color: open ? AppColors.bull : AppColors.bear),
          const SizedBox(width: 6),
          Text(
            MarketHours.statusText(widget.market),
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: open ? AppColors.bull : AppColors.bear),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.warmWhite,
        border: const Border(top: BorderSide(color: AppColors.birch)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.06), offset: const Offset(0, -2), blurRadius: 8),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: _quote == null ? null : () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => OrderEntryScreen(
                          quote: _quote!,
                          isBuy: true,
                        ),
                      ),
                    );
                    _loadData();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.bull,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
                  ),
                  child: Text(
                    'BUY',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.pureWhite,
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: _quote == null || _holding == null ? null : () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => OrderEntryScreen(
                          quote: _quote!,
                          isBuy: false,
                        ),
                      ),
                    );
                    _loadData();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.bear,
                    disabledBackgroundColor: AppColors.bear.withValues(alpha: 0.3),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
                  ),
                  child: Text(
                    'SELL',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.pureWhite,
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
