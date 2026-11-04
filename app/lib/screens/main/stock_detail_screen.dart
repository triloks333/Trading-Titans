import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../core/money.dart';
import '../../models/quote.dart';
import '../../models/portfolio.dart';
import '../../models/price_alert.dart';
import '../../services/market_service.dart';
import '../../services/supabase_service.dart';
import '../../core/market_hours.dart';
import 'fullscreen_chart_screen.dart';
import 'package:google_fonts/google_fonts.dart';
import 'order_entry_screen.dart';
import 'option_chain_screen.dart';
import '../../widgets/instrument_chart.dart';


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
  bool _hasError = false;

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
    try {
      final quote = await MarketService.quote(widget.symbol, widget.market);
      if (mounted) {
        setState(() {
          _quote = quote;
          if (quote != null) {
            _hasError = false;
          } else if (_quote == null) {
            _hasError = true;
          }
        });
      }
    } catch (_) {
      if (mounted && _quote == null) {
        setState(() {
          _hasError = true;
        });
      }
    }
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

  void _showPriceAlertSheet() {
    final currentPrice = _quote?.price ?? 0.0;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => _PriceAlertSheet(
        symbol: widget.symbol,
        market: widget.market,
        displayName: _displaySymbol,
        currentPrice: currentPrice,
      ),
    );
  }


  bool get _isUp => (_quote?.change ?? 0) >= 0;
  Color get _changeColor => _isUp ? AppColors.bull : AppColors.bear;

  /// Clean symbol for display (strips NSE:, BSE:, -EQ, -SM)
  String get _displaySymbol {
    var s = widget.symbol;
    if (s.startsWith('NSE:') || s.startsWith('BSE:')) {
      s = s.substring(4);
    }
    return s.replaceAll(RegExp(r'-(EQ|SM|BE|BZ)$'), '');
  }

  @override
  Widget build(BuildContext context) {
    final q = _quote;
    return Scaffold(
      appBar: AppBar(
        title: Text(_displaySymbol),
        backgroundColor: AppColors.parchment,
        actions: [
          IconButton(
            tooltip: 'Price alert',
            icon: Icon(Icons.notifications_outlined, color: AppColors.ink4),
            onPressed: _quote == null ? null : _showPriceAlertSheet,
          ),
          IconButton(
            icon: Icon(_isWatched ? Icons.star : Icons.star_border, color: _isWatched ? AppColors.goldDeep : AppColors.ink4),
            onPressed: _toggleWatch,
          ),
        ],
      ),
      body: q == null
          ? (_hasError
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.error_outline_rounded, size: 48, color: AppColors.bear),
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          'Unable to load price data',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.ink),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          'Please check your connection or try again.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.ink4),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        ElevatedButton.icon(
                          onPressed: () {
                            setState(() {
                              _hasError = false;
                            });
                            _loadData();
                          },
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Retry'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.ink,
                            foregroundColor: AppColors.pureWhite,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : const Center(child: CircularProgressIndicator()))
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

  /// Quote header: name, big monospace price, arrowed change pill.
  Widget _buildPriceCard(Quote q) => Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: AppCard.primary,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.name, style: AppText.bodySmall),
          const SizedBox(height: AppSpacing.xs),
          Text(Money.instrument(q.price, market: q.market), style: AppText.valueLarge),
          const SizedBox(height: AppSpacing.sm),
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 4),
              decoration: AppCard.badge(_isUp ? AppColors.bullLight : AppColors.bearLight),
              child: Text(
                '${_isUp ? '▲ +' : '▼ '}${Money.instrument(q.change, market: widget.market)} (${q.changePct.toStringAsFixed(2)}%)',
                style: AppFonts.mono(size: 13, weight: FontWeight.w600, color: _changeColor),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(q.market.toUpperCase(), style: AppText.badge.copyWith(color: AppColors.ink4)),
          ]),
        ]),
      );

  Widget _buildChartCard(Quote q) {
    return Container(
      height: 350,
      decoration: BoxDecoration(
        // The chart page's own dark surface, so the frame and the chart do not
        // meet in two different shades at the rounded corners.
        color: AppColors.pureWhite,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: AppColors.birch),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.xl - 1),
        child: Stack(
          children: [
            InstrumentChart(
              symbol: widget.symbol,
              market: widget.market,
              livePrice: q.price,
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

  /// Key stats as a two-column grid of label/value cells.
  Widget _buildStatsCard(Quote q) {
    String px(double v) => Money.instrument(v, market: q.market);
    final stats = <(String, String, Color?)>[
      ('Prev close', px(q.previousClose), null),
      if (q.open != null) ('Open', px(q.open!), null),
      if (q.dayHigh != null) ('Day high', px(q.dayHigh!), null),
      if (q.dayLow != null) ('Day low', px(q.dayLow!), null),
      if (q.volume != null && q.volume! > 0) ('Volume', q.volume!.toString(), null),
      ('Day change', '${_isUp ? '+' : ''}${q.changePct.toStringAsFixed(2)}%', _changeColor),
      ('Market', q.market == 'crypto' ? 'Crypto' : 'NSE/BSE', null),
      ('Currency', q.currency, null),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('KEY STATS', style: AppText.sectionLabel),
      const SizedBox(height: AppSpacing.sm),
      Container(
        decoration: AppCard.primary,
        child: LayoutBuilder(builder: (context, c) => Wrap(children: [
              for (final (label, value, color) in stats)
                Container(
                  width: c.maxWidth / 2,
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 10),
                  decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.birch))),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(label, style: AppText.bodySmall),
                    const SizedBox(height: 2),
                    Text(value, style: AppFonts.mono(size: 14, weight: FontWeight.w500, color: color ?? AppColors.ink)),
                  ]),
                ),
            ])),
      ),
    ]);
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
                Text('Your Position',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.ink)),
          const SizedBox(height: AppSpacing.sm),
          Text('Quantity ${_holding!.quantity.toStringAsFixed(4)}',
              style:       TextStyle(color: AppColors.ink4)),
          const SizedBox(height: AppSpacing.xs),
          Text('Avg price ${Money.instrument(_holding!.displayAvgPrice, market: _holding!.market)}',
              style:       TextStyle(color: AppColors.ink4)),
        ],
      ),
    );
  }

  bool get _marketOpen => MarketHours.isOpen(widget.market);

  Widget _buildOptionChainButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        icon:       Icon(Icons.layers_outlined, color: AppColors.pureWhite),
        label: Text('VIEW OPTION CHAIN', style: GoogleFonts.ibmPlexSans(fontWeight: FontWeight.bold, letterSpacing: 0.5)),
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
        icon:       Icon(Icons.bar_chart_rounded, color: AppColors.pureWhite),
        label: Text('VIEW CHART', style: GoogleFonts.ibmPlexSans(fontWeight: FontWeight.bold, letterSpacing: 0.5)),
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

  /// Sticky Buy / Sell bar. Both open the same order ticket on a side.
  Widget _buildBottomBar() => Container(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.sm),
        decoration: BoxDecoration(color: AppColors.pureWhite, border: Border(top: BorderSide(color: AppColors.birch))),
        child: SafeArea(
          child: Row(children: [
            Expanded(child: _sideButton(isBuy: true)),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: _sideButton(isBuy: false)),
          ]),
        ),
      );

  Widget _sideButton({required bool isBuy}) => SizedBox(
        height: 52,
        child: ElevatedButton(
          onPressed: _quote == null ? null : () => _openOrder(isBuy),
          style: ElevatedButton.styleFrom(
              backgroundColor: isBuy ? AppColors.bull : AppColors.bear, foregroundColor: Colors.white),
          child: Text(isBuy ? 'Buy' : 'Sell', style: AppFonts.sans(size: 16, weight: FontWeight.w700, color: Colors.white)),
        ),
      );

  Future<void> _openOrder(bool isBuy) async {
    final sym = widget.symbol.toUpperCase();
    final isOption = sym.contains('-CE') || sym.contains('-PE');
    final isFuture = sym.contains('FUT') || sym.contains('FUTURE');
    await Navigator.push(context, MaterialPageRoute(
      builder: (_) => OrderEntryScreen(
        quote: _quote!, isBuy: isBuy, instrumentType: isOption ? 'OPTION' : (isFuture ? 'FUTURE' : 'EQUITY')),
    ));
    _loadData();
  }
}

/// Bottom sheet for creating and managing price alerts for a single symbol.
class _PriceAlertSheet extends StatefulWidget {
  final String symbol;
  final String market;
  final String displayName;
  final double currentPrice;

  const _PriceAlertSheet({
    required this.symbol,
    required this.market,
    required this.displayName,
    required this.currentPrice,
  });

  @override
  State<_PriceAlertSheet> createState() => _PriceAlertSheetState();
}

class _PriceAlertSheetState extends State<_PriceAlertSheet> {
  final TextEditingController _targetController = TextEditingController();
  String _direction = 'above';
  bool _saving = false;
  bool _loadingList = true;
  List<PriceAlert> _alerts = [];

  @override
  void initState() {
    super.initState();
    _direction = 'above';
    _loadAlerts();
  }

  @override
  void dispose() {
    _targetController.dispose();
    super.dispose();
  }

  Future<void> _loadAlerts() async {
    final list = await SupabaseService().getPriceAlerts(
      symbol: widget.symbol,
      market: widget.market,
      activeOnly: true,
    );
    if (mounted) {
      setState(() {
        _alerts = list;
        _loadingList = false;
      });
    }
  }

  Future<void> _create() async {
    final target = double.tryParse(_targetController.text.trim());
    if (target == null || target <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid target price')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final nativeTarget = Money.fromDisplay(target, market: widget.market);
      await SupabaseService().createPriceAlert(
        symbol: widget.symbol,
        market: widget.market,
        name: widget.displayName,
        targetPrice: nativeTarget,
        direction: _direction,
        referencePrice: widget.currentPrice,
      );
      _targetController.clear();
      await _loadAlerts();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              // `target` is what the user typed, already in the display currency,
                // so it is echoed back rather than converted again.
                'Alert set: notify when price goes $_direction ${Money.symbol}${target.toStringAsFixed(2)}',
            ),
            backgroundColor: AppColors.bull,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to set alert: $e'), backgroundColor: AppColors.bear),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete(PriceAlert alert) async {
    setState(() => _alerts = _alerts.where((a) => a.id != alert.id).toList());
    try {
      await SupabaseService().deletePriceAlert(alert.id);
    } catch (_) {
      _loadAlerts();
    }
  }

  void _autoDirection() {
    final typed = double.tryParse(_targetController.text.trim());
    if (typed == null) return;
    // The field holds a display-currency figure; currentPrice is native. Compare
    // like with like, or "above"/"below" flips the wrong way in dollars view.
    final target = Money.fromDisplay(typed, market: widget.market);
    if (widget.currentPrice > 0) {
      final newDir = target >= widget.currentPrice ? 'above' : 'below';
      if (newDir != _direction) setState(() => _direction = newDir);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.pureWhite,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.birch,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Icon(Icons.notifications_active_outlined, color: AppColors.imperialGold, size: 22),
                const SizedBox(width: 8),
                Text(
                  'Price Alert',
                  style: GoogleFonts.ibmPlexSans(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.ink),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${widget.displayName}  •  Current ${Money.wallet(widget.currentPrice, decimals: 2)}',
              style: GoogleFonts.ibmPlexMono(fontFeatures: const [FontFeature.tabularFigures()], fontSize: 13, color: AppColors.ink4),
            ),
            const SizedBox(height: 20),

            // Direction toggle
            Row(
              children: [
                _dirTab('Above', 'above'),
                const SizedBox(width: 10),
                _dirTab('Below', 'below'),
              ],
            ),
            const SizedBox(height: 14),

            // Target price input
            TextField(
              controller: _targetController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => _autoDirection(),
              style: GoogleFonts.ibmPlexSans(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.ink),
              decoration: InputDecoration(
                labelText: 'Target price (${Money.symbol})',
                labelStyle: TextStyle(color: AppColors.ink4),
                hintText: 'e.g. ${Money.bare(widget.currentPrice * 1.02, from: Money.sourceFor(widget.market))}',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppColors.birch)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppColors.birch)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppColors.imperialGold)),
              ),
            ),
            const SizedBox(height: 16),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving ? null : _create,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.imperialGold,
                  foregroundColor: AppColors.pureWhite,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _saving
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text('SET ALERT', style: GoogleFonts.ibmPlexSans(fontWeight: FontWeight.bold, letterSpacing: 0.5)),
              ),
            ),

            if (_loadingList) ...[
              const SizedBox(height: 20),
              const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
            ] else if (_alerts.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text('Active alerts', style: GoogleFonts.ibmPlexSans(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.ink4, letterSpacing: 0.5)),
              const SizedBox(height: 8),
              ..._alerts.map(_alertRow),
            ],
          ],
        ),
      ),
    );
  }

  Widget _dirTab(String label, String value) {
    final selected = _direction == value;
    final color = value == 'above' ? AppColors.bull : AppColors.bear;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _direction = value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected ? color.withValues(alpha: 0.12) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: selected ? color : AppColors.birch),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                value == 'above' ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                size: 16,
                color: selected ? color : AppColors.ink4,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.ibmPlexSans(
                  fontWeight: FontWeight.w700,
                  color: selected ? color : AppColors.ink4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _alertRow(PriceAlert a) {
    final color = a.isAbove ? AppColors.bull : AppColors.bear;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.parchment,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.birch),
      ),
      child: Row(
        children: [
          Icon(a.isAbove ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'When price goes ${a.direction} ${Money.instrument(a.targetPrice, market: widget.market)}',
              style: GoogleFonts.ibmPlexMono(fontFeatures: const [FontFeature.tabularFigures()], fontSize: 13, color: AppColors.ink2, fontWeight: FontWeight.w600),
            ),
          ),
          GestureDetector(
            onTap: () => _delete(a),
            child: Icon(Icons.delete_outline_rounded, size: 20, color: AppColors.ink4),
          ),
        ],
      ),
    );
  }
}
