import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/market_hours.dart';
import '../../core/money.dart';
import '../../core/symbols.dart';
import '../../core/theme.dart';
import '../../models/portfolio.dart';
import '../../models/price_alert.dart';
import '../../models/quote.dart';
import '../../services/fo_instruments_service.dart';
import '../../services/market_service.dart';
import '../../services/supabase_service.dart';
import '../../services/theme_service.dart';
import '../../widgets/auth_kit.dart';
import 'fullscreen_chart_screen.dart';
import 'option_chain_screen.dart';
import 'order_entry_screen.dart';
import '../../services/churn_telemetry_service.dart';
import '../../widgets/upgrade_sheet.dart';
import '../../services/plan_service.dart';

/// Chart range buttons and the `market-history` range each one fetches.
const Map<String, String> kStockRanges = {'1D': '1d', '1W': '5d', '1M': '1mo', '1Y': '1y', '5Y': '5y'};

/// Compact volume: 6.42M, 1.20B, 84.5K.
String compactVolume(num v) {
  if (v >= 1e9) return '${(v / 1e9).toStringAsFixed(2)}B';
  if (v >= 1e6) return '${(v / 1e6).toStringAsFixed(2)}M';
  if (v >= 1e3) return '${(v / 1e3).toStringAsFixed(1)}K';
  return v.toStringAsFixed(0);
}

class StockDetailScreen extends StatefulWidget {
  final String symbol;
  final String market;
  final String name;

  /// A price the caller already has, painted at once while the live quote loads.
  final Quote? initialQuote;

  /// Whether F&O exists for this symbol; looked up when null (tests pass it).
  final bool? hasFo;

  const StockDetailScreen({super.key, required this.symbol, required this.market, required this.name, this.initialQuote, this.hasFo});

  @override
  State<StockDetailScreen> createState() => _StockDetailScreenState();
}

class _StockDetailScreenState extends State<StockDetailScreen> {
  late Quote? _quote = widget.initialQuote;
  bool _isWatched = false;
  Holding? _holding;
  List<PriceAlert> _alerts = const [];
  Timer? _pollTimer;
  bool _hasError = false;
  String _range = '1D';
  final Map<String, List<double>> _history = {}; // closes per range, fetched once each
  ({double low, double high})? _yearRange;
  int? _lotSize;
  late bool _hasFo = widget.hasFo ?? false;

  @override
  void initState() {
    super.initState();
    ChurnTelemetryService.instance.recordSymbolChartView(widget.symbol);
    _loadData();
    _loadHistory(_range);
    _loadExtras();
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
          _quote = quote ?? _quote;
          _hasError = _quote == null;
        });
      }
    } catch (_) {
      if (mounted && _quote == null) setState(() => _hasError = true);
    }
  }

  Future<void> _loadUserData() async {
    try {
      final results = await Future.wait<Object>([
        SupabaseService().getHoldings(),
        SupabaseService().isWatched(widget.symbol, widget.market),
        SupabaseService().getPriceAlerts(symbol: widget.symbol, market: widget.market, activeOnly: true),
      ]);
      final holding = (results[0] as List<Holding>)
          .where((h) => h.symbol == widget.symbol && h.market == widget.market && h.quantity != 0)
          .firstOrNull;
      if (mounted) {
        setState(() {
          _holding = holding;
          _isWatched = results[1] as bool;
          _alerts = results[2] as List<PriceAlert>;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadHistory(String range) async {
    if (_history.containsKey(range)) return;
    _history[range] = const [];
    try {
      final pts = await SupabaseService().getHistory(widget.symbol, widget.market, kStockRanges[range]!);
      if (mounted) setState(() => _history[range] = [for (final p in pts) if (p['v'] is num) (p['v'] as num).toDouble()]);
    } catch (_) {}
  }

  /// 52-week range from a year of closes, and the F&O lot size for NSE names.
  Future<void> _loadExtras() async {
    try {
      final year = await SupabaseService().getHistory(widget.symbol, widget.market, '1y');
      final closes = [for (final p in year) if (p['v'] is num) (p['v'] as num).toDouble()];
      if (mounted && closes.isNotEmpty) {
        setState(() => _yearRange = (low: closes.reduce((a, b) => a < b ? a : b), high: closes.reduce((a, b) => a > b ? a : b)));
      }
    } catch (_) {}
    if (widget.market != 'stock') return;
    try {
      // Option chain and lot size only for names with real F&O contracts.
      final fo = widget.hasFo ?? await FoInstrumentsService().hasFo(widget.symbol);
      if (mounted) setState(() => _hasFo = fo);
      if (!fo) return;
      final lot = await FoInstrumentsService().getLotSize(widget.symbol);
      if (mounted && lot > 1) setState(() => _lotSize = lot);
    } catch (_) {}
  }

  Future<void> _toggleWatch() async {
    ChurnTelemetryService.instance.recordButtonTap('stock_detail_watchlist_bookmark_btn');
    setState(() => _isWatched = !_isWatched);
    try {
      if (_isWatched) {
        await SupabaseService().addToWatchlist(widget.symbol, widget.market, widget.name);
      } else {
        await SupabaseService().removeFromWatchlist(widget.symbol, widget.market);
      }
    } catch (e) {
      if (mounted) setState(() => _isWatched = !_isWatched);
      if (mounted) await handlePlanLimitError(context, e, source: 'watchlist_symbol');
    }
  }

  Future<void> _showPriceAlertSheet() async {
    ChurnTelemetryService.instance.recordButtonTap('stock_detail_price_alert_bell_btn');
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PriceAlertSheet(
        symbol: widget.symbol,
        market: widget.market,
        displayName: _displaySymbol,
        currentPrice: _quote?.price ?? 0.0,
      ),
    );
    _loadUserData();
  }

  Future<void> _push(Widget screen) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    _loadData();
  }

  void _openProChart() {
    ChurnTelemetryService.instance.recordButtonTap('stock_detail_open_pro_fullscreen_chart_btn');
    _push(FullscreenChartScreen(symbol: widget.symbol, market: widget.market, name: widget.name, quote: _quote));
  }

  bool get _isUp => (_quote?.change ?? 0) >= 0;
  Color get _changeColor => _isUp ? AppColors.bull : AppColors.bear;
  String _px(double v) => Money.instrument(v, market: widget.market);

  /// Clean symbol for display (strips NSE:, BSE:, -EQ, -SM).
  String get _displaySymbol => displaySymbol(widget.symbol);

  String get _exchange => switch (widget.market) {
        'crypto' => 'Crypto',
        'us_stock' => 'US',
        'commodity' => 'Commodity',
        'pakistan_stock' => 'PSX',
        'italy_stock' => 'Borsa Italiana',
        _ => 'NSE',
      };

  @override
  Widget build(BuildContext context) {
    final q = _quote;
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          _header(),
          Expanded(
            child: q == null
                ? (_hasError ? _error() : const Center(child: CircularProgressIndicator()))
                : RefreshIndicator(
                    onRefresh: _loadData,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        _priceHeader(q),
                        _chart(q),
                        _rangeRow(),
                        _toolButtons(),
                        if (_holding != null) _positionCard(_holding!),
                        _keyStats(q),
                        _alertsCard(),
                      ],
                    ),
                  ),
          ),
          if (q != null) _bottomBar(),
        ]),
      ),
    );
  }

  Widget _header() => Container(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 10, AppSpacing.lg, 10),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.birch))),
        child: Row(children: [
          AuthIconButton(icon: Icons.arrow_back_rounded, label: 'Back', onTap: () => Navigator.of(context).maybePop()),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_displaySymbol,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: AppFonts.sans(size: 16, weight: FontWeight.w700, color: AppColors.ink)),
              Text('$_exchange · ${widget.name}',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: AppFonts.sans(size: 11, color: AppColors.ink4)),
            ]),
          ),
          Semantics(
            button: true,
            label: _isWatched ? 'Remove from watchlist' : 'Add to watchlist',
            excludeSemantics: true,
            child: Material(
              color: AppColors.pureWhite,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md), side: BorderSide(color: AppColors.birch)),
              child: InkWell(
                onTap: _toggleWatch,
                borderRadius: BorderRadius.circular(AppRadius.md),
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: Icon(_isWatched ? Icons.star_rounded : Icons.star_outline_rounded,
                      size: 22, color: _isWatched ? AppColors.titanGold : AppColors.ink),
                ),
              ),
            ),
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
      );

  Widget _error() => Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.error_outline_rounded, size: 48, color: AppColors.bear),
            const SizedBox(height: AppSpacing.md),
            Text('Unable to load price data', style: AppFonts.sans(size: 18, weight: FontWeight.w700, color: AppColors.ink)),
            const SizedBox(height: AppSpacing.xs),
            Text('Please check your connection or try again.', textAlign: TextAlign.center, style: AppText.body),
            const SizedBox(height: AppSpacing.lg),
            ElevatedButton.icon(
              onPressed: () {
                setState(() => _hasError = false);
                _loadData();
              },
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ]),
        ),
      );

  Widget _priceHeader(Quote q) {
    final open = MarketHours.isOpen(widget.market);
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 16, AppSpacing.lg, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(_px(q.price), style: AppFonts.mono(size: 32, weight: FontWeight.w600, color: AppColors.ink, spacing: -0.6)),
        ),
        Text.rich(TextSpan(children: [
          TextSpan(
            text: '${_isUp ? '▲ +' : '▼ −'}${_px(q.change.abs())} (${_isUp ? '+' : '−'}${q.changePct.abs().toStringAsFixed(2)}%)',
            style: AppFonts.mono(size: 14, color: _changeColor),
          ),
          TextSpan(
            text: open ? '  today · live' : '  ${MarketHours.statusText(widget.market).toLowerCase()}',
            style: AppFonts.sans(size: 14, color: AppColors.ink4),
          ),
        ])),
      ]),
    );
  }

  /// Area chart for the chosen range with a dashed previous-close line on 1D.
  Widget _chart(Quote q) {
    final closes = _history[_range] ?? const [];
    final series = _range == '1D' && closes.isNotEmpty ? [...closes, q.price] : closes;
    final up = series.length < 2 ? _isUp : series.last >= series.first;
    return Semantics(
      label: series.length < 2
          ? 'Price chart loading'
          : '$_range price chart, ${up ? 'up' : 'down'} ${((series.last / series.first - 1) * 100).abs().toStringAsFixed(2)}%',
      child: SizedBox(
        height: 180,
        width: double.infinity,
        child: series.length < 2
            ? Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.ink4)))
            : CustomPaint(
                painter: _AreaChart(
                  series,
                  up ? AppColors.bull : AppColors.bear,
                  baseline: _range == '1D' ? q.previousClose : null,
                  baselineColor: AppColors.ink4,
                ),
              ),
      ),
    );
  }

  Widget _chip(String label, bool on, VoidCallback onTap, {String? semantics, Widget? child}) => Material(
        color: on ? AppColors.goldPale : Colors.transparent,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm), side: BorderSide(color: on ? AppColors.goldMid : AppColors.birch)),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: Semantics(
            label: semantics,
            button: true,
            child: Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              alignment: Alignment.center,
              child: child ??
                  Text(label, style: AppFonts.sans(size: 13, weight: FontWeight.w500, color: on ? AppColors.goldMid : AppColors.ink3)),
            ),
          ),
        ),
      );

  /// Ranges beyond the plan's chart allowance (free: 1 month).
  bool _rangeLocked(String r) {
    final days = PlanService.instance.chartDays;
    return days != null && (r == '1Y' || r == '5Y' || r == 'ALL');
  }

  Widget _rangeRow() => Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 8, AppSpacing.lg, 8),
        child: Row(children: [
          for (final r in kStockRanges.keys) ...[
            Expanded(
              child: _chip(_rangeLocked(r) ? '$r 🔒' : r, r == _range, () {
                ChurnTelemetryService.instance.recordButtonTap('stock_detail_range_${r.toLowerCase()}_btn');
                if (_rangeLocked(r)) {
                  showUpgradeSheet(context,
                      title: 'Longer charts are a Pro feature',
                      message: 'Free accounts see charts up to 1 month. Pro unlocks 1-year and 5-year charts.',
                      source: 'chart_range');
                  return;
                }
                setState(() => _range = r);
                _loadHistory(r);
              }),
            ),
            const SizedBox(width: 6),
          ],
          _chip('', false, _openProChart,
              semantics: 'Open full-screen chart', child: Icon(Icons.fullscreen_rounded, size: 18, color: AppColors.ink3)),
        ]),
      );

  Widget _toolButtons() => Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 8, AppSpacing.lg, 0),
        child: Row(children: [
          Expanded(child: _toolButton('Pro chart', _openProChart)),
          if (widget.market == 'stock' && _hasFo) ...[
            const SizedBox(width: 8),
            Expanded(
              child: _toolButton(
                'Option chain',
                () {
                  ChurnTelemetryService.instance.recordButtonTap('stock_detail_open_option_chain_btn', extra: {'sym': widget.symbol});
                  _push(OptionChainScreen(underlyingSymbol: widget.symbol, spotPrice: _quote?.price ?? 0.0, market: widget.market));
                },
              ),
            ),
          ],
        ]),
      );

  Widget _toolButton(String label, VoidCallback onTap) => SizedBox(
        height: 44,
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(backgroundColor: AppColors.cream, minimumSize: const Size(0, 44)),
          onPressed: onTap,
          child: Text(label, style: AppFonts.sans(size: 14, weight: FontWeight.w600)),
        ),
      );

  Widget _card({required Widget child, EdgeInsets margin = const EdgeInsets.all(AppSpacing.lg)}) => Container(
        margin: margin,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.pureWhite,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.birch),
        ),
        child: child,
      );

  Widget _tag(String text, Color fg, Color bg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: AppCard.badge(bg),
        child: Text(text, style: AppText.badge.copyWith(color: fg)),
      );

  Widget _positionCard(Holding h) {
    final long = h.quantity > 0;
    final tone = h.pnl >= 0 ? AppColors.bull : AppColors.bear;
    Widget cell(String label, String value, {Color? color, bool end = false}) => Expanded(
          child: Column(crossAxisAlignment: end ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
            Text(label, style: AppFonts.sans(size: 11, color: AppColors.ink4)),
            Text(value, style: AppFonts.mono(size: 14, weight: FontWeight.w600, color: color ?? AppColors.ink)),
          ]),
        );
    return _card(
      child: Column(children: [
        Row(children: [
          Expanded(child: Text('YOUR POSITION', style: AppText.sectionLabel)),
          long ? _tag('LONG', AppColors.bull, AppColors.bullLight) : _tag('SHORT', AppColors.bear, AppColors.bearLight),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          cell('Qty', h.quantity.abs().toStringAsFixed(MarketHours.isFractional(h.market) ? 4 : 0)),
          cell('Avg', Money.instrument(h.displayAvgPrice, market: h.market)),
          cell('P&L', '${h.pnl >= 0 ? '+' : '−'}${Money.wallet(h.pnl.abs(), decimals: 2)}', color: tone, end: true),
        ]),
      ]),
    );
  }

  Widget _keyStats(Quote q) {
    final stats = <(String, String)>[
      if (q.open != null) ('Open', _px(q.open!)),
      ('Prev close', _px(q.previousClose)),
      if (_yearRange != null) ...[('52W high', _px(_yearRange!.high)), ('52W low', _px(_yearRange!.low))],
      if (q.volume != null && q.volume! > 0) ('Volume', compactVolume(q.volume!)),
      if (q.avgTradePrice != null && q.avgTradePrice! > 0) ('Avg trade price', _px(q.avgTradePrice!)),
      if (q.upperCircuit != null && q.upperCircuit! > 0) ('Upper circuit', _px(q.upperCircuit!)),
      if (q.lowerCircuit != null && q.lowerCircuit! > 0) ('Lower circuit', _px(q.lowerCircuit!)),
      if (_lotSize != null) ('Lot size (F&O)', '$_lotSize'),
      ('Currency', q.currency),
    ];
    final low = q.dayLow, high = q.dayHigh;
    final pos = low != null && high != null && high > low ? ((q.price - low) / (high - low)).clamp(0.0, 1.0) : null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('KEY STATS', style: AppText.sectionLabel),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: AppColors.pureWhite,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppColors.birch),
          ),
          child: LayoutBuilder(
            builder: (_, c) => Wrap(children: [
              for (final (k, v) in stats)
                Container(
                  width: c.maxWidth / 2,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.birch))),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(k, style: AppFonts.sans(size: 11, color: AppColors.ink4)),
                    const SizedBox(height: 2),
                    Text(v, style: AppFonts.mono(size: 14, weight: FontWeight.w500, color: AppColors.ink)),
                  ]),
                ),
            ]),
          ),
        ),
        if (pos != null) ...[
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: Text.rich(TextSpan(style: AppFonts.sans(size: 11, color: AppColors.ink4), children: [
                const TextSpan(text: 'Day low '),
                TextSpan(text: _px(low!), style: AppFonts.mono(size: 11, color: AppColors.ink4)),
              ])),
            ),
            Text.rich(TextSpan(style: AppFonts.sans(size: 11, color: AppColors.ink4), children: [
              const TextSpan(text: 'Day high '),
              TextSpan(text: _px(high!), style: AppFonts.mono(size: 11, color: AppColors.ink4)),
            ])),
          ]),
          const SizedBox(height: 6),
          Semantics(
            label: 'Price is ${(pos * 100).round()}% of the way from day low to day high',
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(value: pos, minHeight: 6, color: _changeColor, backgroundColor: AppColors.cream),
            ),
          ),
        ],
      ]),
    );
  }

  Widget _alertsCard() => _card(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text('PRICE ALERTS', style: AppText.sectionLabel)),
            _chip('+ Set alert', true, _showPriceAlertSheet),
          ]),
          if (_alerts.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text('Get a notification when $_displaySymbol crosses a price.', style: AppFonts.sans(size: 13, color: AppColors.ink4)),
            ),
          for (final a in _alerts)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(children: [
                Expanded(
                  child: Text.rich(TextSpan(style: AppFonts.sans(size: 13, color: AppColors.ink), children: [
                    TextSpan(text: a.isAbove ? 'Crosses above ' : 'Falls below '),
                    TextSpan(text: _px(a.targetPrice), style: AppFonts.mono(size: 13, color: AppColors.ink)),
                  ])),
                ),
                _tag('ACTIVE', AppColors.ink3, AppColors.cream),
              ]),
            ),
        ]),
      );

  /// Sell left, Buy right, as in the design. Both open the order ticket on a side.
  Widget _bottomBar() => Container(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 12, AppSpacing.lg, 16),
        decoration: BoxDecoration(color: AppColors.pureWhite, border: Border(top: BorderSide(color: AppColors.birch))),
        child: Row(children: [
          Expanded(child: _sideButton(isBuy: false)),
          const SizedBox(width: 10),
          Expanded(child: _sideButton(isBuy: true)),
        ]),
      );

  Widget _sideButton({required bool isBuy}) => SizedBox(
        height: 48,
        child: ElevatedButton(
          onPressed: _quote == null ? null : () => _openOrder(isBuy),
          style: ElevatedButton.styleFrom(
            backgroundColor: isBuy ? AppColors.bull : AppColors.bear,
            foregroundColor: isBuy && AppColors.isDark ? const Color(0xFF04140B) : Colors.white,
          ),
          child: Text(isBuy ? 'Buy' : 'Sell'),
        ),
      );

  Future<void> _openOrder(bool isBuy) async {
    ChurnTelemetryService.instance.recordButtonTap(isBuy ? 'stock_detail_bottom_buy_cta' : 'stock_detail_bottom_sell_short_cta', extra: {'sym': widget.symbol});
    final sym = widget.symbol.toUpperCase();
    final isOption = sym.contains('-CE') || sym.contains('-PE');
    final isFuture = sym.contains('FUT') || sym.contains('FUTURE');
    await _push(OrderEntryScreen(quote: _quote!, isBuy: isBuy, instrumentType: isOption ? 'OPTION' : (isFuture ? 'FUTURE' : 'EQUITY')));
  }
}

/// Line with a soft fill under it, scaled to the series; optional dashed baseline.
class _AreaChart extends CustomPainter {
  _AreaChart(this.values, this.color, {this.baseline, required this.baselineColor});
  final List<double> values;
  final Color color;
  final double? baseline;
  final Color baselineColor;

  @override
  void paint(Canvas canvas, Size size) {
    var lo = values.reduce((a, b) => a < b ? a : b), hi = values.reduce((a, b) => a > b ? a : b);
    if (baseline != null && baseline! > 0) {
      lo = lo < baseline! ? lo : baseline!;
      hi = hi > baseline! ? hi : baseline!;
    }
    final span = hi == lo ? 1.0 : hi - lo;
    double y(double v) => 16 + (size.height - 32) * (1 - (v - lo) / span);
    Offset at(int i) => Offset(size.width * i / (values.length - 1), y(values[i]));

    if (baseline != null && baseline! > 0) {
      final by = y(baseline!);
      final dash = Paint()
        ..color = baselineColor
        ..strokeWidth = 1;
      for (var x = 0.0; x < size.width; x += 7) {
        canvas.drawLine(Offset(x, by), Offset((x + 3).clamp(0, size.width), by), dash);
      }
    }
    final line = Path()..moveTo(at(0).dx, at(0).dy);
    for (var i = 1; i < values.length; i++) {
      line.lineTo(at(i).dx, at(i).dy);
    }
    final fill = Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(fill, Paint()..color = color.withValues(alpha: 0.14));
    canvas.drawPath(line, Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeJoin = StrokeJoin.round);
    canvas.drawCircle(at(values.length - 1), 4, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_AreaChart old) => old.values != values || old.color != color || old.baseline != baseline;
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
    ChurnTelemetryService.instance.recordSymbolChartView(widget.symbol);
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
    ChurnTelemetryService.instance.recordButtonTap('stock_detail_price_alert_save_btn');
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
      if (mounted && await handlePlanLimitError(context, e, source: 'price_alert')) return;
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
    ChurnTelemetryService.instance.recordButtonTap('stock_detail_price_alert_delete_btn');
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
