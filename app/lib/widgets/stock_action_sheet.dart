import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/theme.dart';
import '../core/app_constants.dart';
import '../core/money.dart';
import '../models/quote.dart';
import '../services/market_service.dart';
import '../screens/main/stock_detail_screen.dart';
import '../screens/main/order_entry_screen.dart';
import '../screens/main/option_chain_screen.dart';
import '../services/supabase_service.dart';

class StockActionSheet extends StatefulWidget {
  final String symbol;
  final String market;
  final String name;
  final VoidCallback? onRefresh;

  const StockActionSheet({
    super.key,
    required this.symbol,
    required this.market,
    required this.name,
    this.onRefresh,
  });

  static Future<void> show(
    BuildContext context, {
    required String symbol,
    required String market,
    required String name,
    VoidCallback? onRefresh,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          StockActionSheet(symbol: symbol, market: market, name: name, onRefresh: onRefresh),
    );
  }

  @override
  State<StockActionSheet> createState() => _StockActionSheetState();
}

class _StockActionSheetState extends State<StockActionSheet> {
  Quote? _quote;
  bool _loading = true;
  bool _isWatched = false;
  Timer? _pollTimer;

  /// Clean symbol for display (strips NSE:, BSE:, -EQ, -SM)
  static String _cleanSymbol(String sym) {
    var s = sym;
    if (s.startsWith('NSE:') || s.startsWith('BSE:')) {
      s = s.substring(4);
    }
    return s.replaceAll(RegExp(r'-(EQ|SM|BE|BZ)$'), '');
  }

  @override
  void initState() {
    super.initState();
    _load();
    // The sheet used to fetch once and freeze for as long as it stayed open.
    _pollTimer = Timer.periodic(
      AppConstants.dashboardPricePoll,
      (_) => _refreshQuote(),
    );
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  /// Quote-only background refresh: no spinner, and it leaves the watchlist state
  /// alone so a poll cannot fight a tap on the star.
  Future<void> _refreshQuote() async {
    try {
      final q = await MarketService.quote(widget.symbol, widget.market);
      if (q != null && mounted) setState(() => _quote = q);
    } catch (_) {
      // Keep showing the last good price.
    }
  }

  Future<void> _load() async {
    try {
      final q = await MarketService.quote(widget.symbol, widget.market);
      final watchCheck = await SupabaseService().isWatched(widget.symbol, widget.market);
      if (mounted) {
        setState(() {
          _quote = q;
          _isWatched = watchCheck;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Formats an optional quote figure in the user's display currency, converting
  /// from the instrument's own currency.
  String _fmt(double? value) =>
      value == null ? '-' : Money.instrument(value, market: widget.market);

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

  void _navigateToDetail() async {
    final navigator = Navigator.of(context);
    final refresh = widget.onRefresh;
    Navigator.pop(context);
    await navigator.push(
      MaterialPageRoute(
        builder: (_) => StockDetailScreen(
          symbol: widget.symbol,
          market: widget.market,
          name: widget.name,
        ),
      ),
    );
    if (refresh != null) refresh();
  }

  void _navigateToOrder(bool isBuy) async {
    if (_quote == null) return;
    final deriv = MarketService.parseDerivative(widget.symbol);
    final navigator = Navigator.of(context);
    final refresh = widget.onRefresh;
    Navigator.pop(context);
    await navigator.push(
      MaterialPageRoute(
        builder: (_) => OrderEntryScreen(
          quote: _quote!,
          isBuy: isBuy,
          instrumentType: deriv?.type ?? 'EQUITY',
          strikePrice: deriv?.strikePrice,
          optionType: deriv?.optionType,
          expiryDate: deriv?.expiryDate,
        ),
      ),
    );
    if (refresh != null) refresh();
  }

  String get _exchangeLabel {
    switch (widget.market) {
      case 'crypto':
        return 'CRYPTO';
      case 'pakistan_stock':
        return 'PSX';
      case 'italy_stock':
        return 'BORSA ITALIANA';
      case 'us_stock':
        return 'US';
      case 'stock':
      default:
        return 'NSE';
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.45,
      minChildSize: 0.45,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration:       BoxDecoration(
            color: AppColors.pureWhite,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(AppRadius.xl),
            ),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.md,
                    AppSpacing.lg,
                    AppSpacing.xxl,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _cleanSymbol(widget.symbol),
                            style: GoogleFonts.ibmPlexSans(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppColors.ink,
                            ),
                          ),
                          IconButton(
                            onPressed: _toggleWatch,
                            icon: Icon(
                              _isWatched ? Icons.star : Icons.star_border,
                              color: _isWatched ? AppColors.goldDeep : AppColors.ink4,
                            ),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            _exchangeLabel,
                            style: GoogleFonts.ibmPlexSans(
                              fontSize: 12,
                              color: AppColors.ink4,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          if (_loading)
                            const SizedBox(
                              height: 14,
                              width: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          else if (_quote != null) ...[
                            Text(
                              Money.instrument(_quote!.price, market: widget.market),
                              style: GoogleFonts.ibmPlexMono(fontFeatures: const [FontFeature.tabularFigures()], 
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: _quote!.change >= 0
                                    ? AppColors.bull
                                    : AppColors.bear,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            Text(
                              '${_quote!.change >= 0 ? '+' : ''}${Money.instrument(_quote!.change, market: widget.market)} (${_quote!.changePct.toStringAsFixed(2)}%)',
                              style: GoogleFonts.ibmPlexMono(fontFeatures: const [FontFeature.tabularFigures()], 
                                fontSize: 12,
                                color: _quote!.change >= 0
                                    ? AppColors.bull
                                    : AppColors.bear,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      Row(
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: 48,
                              child: ElevatedButton(
                                onPressed: () => _navigateToOrder(true),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF4A84F6),
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(
                                      AppRadius.sm,
                                    ),
                                  ),
                                ),
                                child: Text(
                                  'BUY',
                                  style: GoogleFonts.ibmPlexSans(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: SizedBox(
                              height: 48,
                              child: ElevatedButton(
                                onPressed: () => _navigateToOrder(false),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFE55B5B),
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(
                                      AppRadius.sm,
                                    ),
                                  ),
                                ),
                                child: Text(
                                  'SELL',
                                  style: GoogleFonts.ibmPlexSans(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xl),
                            Divider(height: 1, color: AppColors.birch),
                      const SizedBox(height: AppSpacing.md),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          GestureDetector(
                            onTap: _navigateToDetail,
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.bar_chart,
                                  color: Color(0xFF4A84F6),
                                  size: 20,
                                ),
                                const SizedBox(width: AppSpacing.xs),
                                Text(
                                  'View chart',
                                  style: GoogleFonts.ibmPlexSans(
                                    color: const Color(0xFF4A84F6),
                                    fontWeight: FontWeight.w500,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (widget.market == 'stock')
                            GestureDetector(
                              onTap: () async {
                                final navigator = Navigator.of(context);
                                final refresh = widget.onRefresh;
                                final deriv = MarketService.parseDerivative(widget.symbol);
                                final underlying = deriv?.underlying ?? widget.symbol;
                                Navigator.pop(context);
                                await navigator.push(
                                  MaterialPageRoute(
                                    builder: (_) => OptionChainScreen(
                                      underlyingSymbol: underlying,
                                      spotPrice: _quote?.price ?? 0.0,
                                      market: widget.market,
                                    ),
                                  ),
                                );
                                if (refresh != null) refresh();
                              },
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.toc,
                                    color: Color(0xFF4A84F6),
                                    size: 20,
                                  ),
                                  const SizedBox(width: AppSpacing.xs),
                                  Text(
                                    'Option chain',
                                    style: GoogleFonts.ibmPlexSans(
                                      color: const Color(0xFF4A84F6),
                                      fontWeight: FontWeight.w500,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),
                            Divider(height: 1, color: AppColors.birch),
                      const SizedBox(height: AppSpacing.xl),
                      _buildMarketStats(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMarketStats() {
    final low = _fmt(_quote?.dayLow);
    final high = _fmt(_quote?.dayHigh);
    final open = _fmt(_quote?.open);
    final prevClose = _fmt(_quote?.previousClose);
    final volume = _quote?.volume?.toString() ?? '0';
    final avgPrice = _fmt(_quote?.avgTradePrice);
    final lastQty = _quote?.lastTradedQuantity?.toString() ?? '0';
    final lastTime = _quote?.lastTradedTime ?? '--';
    final lowerCircuit = _fmt(_quote?.lowerCircuit);
    final upperCircuit = _fmt(_quote?.upperCircuit);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Day\'s range',
          style: GoogleFonts.ibmPlexSans(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.ink,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Low',
                  style: GoogleFonts.ibmPlexSans(fontSize: 11, color: AppColors.ink4),
                ),
                const SizedBox(height: 4),
                Text(
                  low,
                  style: GoogleFonts.ibmPlexSans(fontSize: 13, color: AppColors.ink),
                ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'High',
                  style: GoogleFonts.ibmPlexSans(fontSize: 11, color: AppColors.ink4),
                ),
                const SizedBox(height: 4),
                Text(
                  high,
                  style: GoogleFonts.ibmPlexSans(fontSize: 13, color: AppColors.ink),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          height: 4,
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.grey[300],
            borderRadius: BorderRadius.circular(2),
          ),
          // We could add a Stack here with an indicator if we wanted to show current price position
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Text(
                  'Open  ',
                  style: GoogleFonts.ibmPlexSans(fontSize: 11, color: AppColors.ink4),
                ),
                Text(
                  open,
                  style: GoogleFonts.ibmPlexSans(fontSize: 13, color: AppColors.ink),
                ),
              ],
            ),
            Row(
              children: [
                Text(
                  'Prev. close  ',
                  style: GoogleFonts.ibmPlexSans(fontSize: 11, color: AppColors.ink4),
                ),
                Text(
                  prevClose,
                  style: GoogleFonts.ibmPlexSans(fontSize: 13, color: AppColors.ink),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 24),
        _buildStatRow('Volume', volume),
        _buildStatRow('Avg. trade price', avgPrice),
        _buildStatRow('Last traded quantity', lastQty),
        _buildStatRow('Last traded at', lastTime),
        _buildStatRow('Lower circuit', lowerCircuit),
        _buildStatRow('Upper circuit', upperCircuit),
      ],
    );
  }

  Widget _buildStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.ibmPlexSans(fontSize: 13, color: AppColors.ink4),
          ),
          Text(
            value,
            style: GoogleFonts.ibmPlexMono(fontFeatures: const [FontFeature.tabularFigures()], fontSize: 13, color: AppColors.ink),
          ),
        ],
      ),
    );
  }
}
