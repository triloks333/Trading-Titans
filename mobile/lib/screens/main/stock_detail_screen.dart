import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../models/quote.dart';
import '../../models/portfolio.dart';
import '../../services/market_service.dart';
import '../../services/supabase_service.dart';
import '../../core/market_hours.dart';
import '../../widgets/price_chart.dart';
import 'package:google_fonts/google_fonts.dart';

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
  bool _busy = false;
  String _qty = '';
  Holding? _holding;
  List<Map<String, dynamic>> _history = [];
  String _selectedRange = '1mo';
  Timer? _pollTimer;

  final List<String> _ranges = ['1d', '5d', '1mo', '3mo', '1y', '5y'];

  @override
  void initState() {
    super.initState();
    _loadData();
    _pollTimer = Timer.periodic(const Duration(seconds: 8), (_) => _refreshQuote());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    await Future.wait([_refreshQuote(), _loadHistory(), _loadUserData()]);
  }

  Future<void> _refreshQuote() async {
    final quote = await MarketService.quote(widget.symbol, widget.market);
    if (mounted) setState(() => _quote = quote);
  }

  Future<void> _loadHistory() async {
    final history = await MarketService.getHistory(widget.symbol, widget.market, _selectedRange);
    if (mounted) setState(() => _history = history);
  }

  Future<void> _loadUserData() async {
    final watchlist = await SupabaseService().getWatchlist();
    final holdings = await SupabaseService().getHoldings();
    final holding = holdings.where((h) => h.symbol == widget.symbol && h.market == widget.market).firstOrNull;
    if (mounted) {
      setState(() {
        _isWatched = watchlist.any((item) => item.symbol == widget.symbol && item.market == widget.market);
        _holding = holding;
      });
    }
  }

  Future<void> _toggleWatch() async {
    if (_isWatched) {
      await SupabaseService().removeFromWatchlist(widget.symbol, widget.market);
    } else {
      await SupabaseService().addToWatchlist(widget.symbol, widget.market);
    }
    await _loadUserData();
  }

  Future<void> _placeOrder(String side) async {
    final quantity = double.tryParse(_qty.replaceAll(',', '')) ?? 0.0;
    if (quantity <= 0) return;
    setState(() => _busy = true);
    try {
      await SupabaseService().placeOrder(symbol: widget.symbol, market: widget.market, side: side, quantity: quantity);
      await _loadData();
      if (!mounted) return;
      final isPending = !MarketHours.isOpen(widget.market);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(isPending ? 'Order queued! Will execute at market prices when markets open.' : 'Order placed: $side ${widget.symbol}'),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Order failed: $e')));
    } finally {
      setState(() => _busy = false);
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
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.pureWhite,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: AppColors.birch),
      ),
      child: Column(
        children: [
          PriceChart(points: _history, isPositive: _isUp),
          const SizedBox(height: AppSpacing.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: _ranges.map((range) {
              final selected = range == _selectedRange;
              return GestureDetector(
                onTap: () {
                  setState(() => _selectedRange = range);
                  _loadHistory();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: selected ? AppColors.ink : Colors.transparent,
                    borderRadius: BorderRadius.circular(AppRadius.tag),
                  ),
                  child: Text(
                    range.toUpperCase(),
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: selected ? AppColors.pureWhite : AppColors.ink4,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            decoration: InputDecoration(
              hintText: 'Enter quantity...',
              hintStyle: const TextStyle(color: AppColors.ink5),
              filled: true,
              fillColor: AppColors.pureWhite,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
                borderSide: const BorderSide(color: AppColors.birch),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
                borderSide: const BorderSide(color: AppColors.birch),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 14),
              suffixText: _quote != null ? '≈ ₹${(double.tryParse(_qty.replaceAll(',', '')) ?? 0) * _quote!.price}' : null,
              suffixStyle: const TextStyle(color: AppColors.ink4, fontSize: 12),
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (value) => setState(() => _qty = value),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                  child: SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _busy ? null : () => _placeOrder('buy'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.bull,
                      disabledBackgroundColor: AppColors.bull.withValues(alpha: 0.5),
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
                    ),
                    child: Text(
                      'Buy',
                      style: GoogleFonts.inter(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: AppColors.pureWhite,
                        letterSpacing: 0.5,
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
                    onPressed: _busy || _holding == null ? null : () => _placeOrder('sell'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.bear,
                      disabledBackgroundColor: AppColors.bear.withValues(alpha: 0.5),
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
                    ),
                    child: Text(
                      'Sell',
                      style: GoogleFonts.inter(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: AppColors.pureWhite,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
