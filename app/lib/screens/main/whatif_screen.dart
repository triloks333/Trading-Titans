import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/money.dart';
import '../../core/theme.dart';
import '../../services/market_service.dart';
import '../../services/churn_telemetry_service.dart';
import '../../services/supabase_service.dart';
import '../../services/theme_service.dart';
import '../../widgets/auth_kit.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/upgrade_sheet.dart';
import '../../services/plan_service.dart';
import 'stock_detail_screen.dart';

/// Compound annual growth rate in percent.
double whatIfCagr(double invested, double value, int years) =>
    invested <= 0 || value <= 0 || years <= 0 ? 0 : (math.pow(value / invested, 1 / years) - 1) * 100;

/// The same money in a fixed deposit compounding yearly at [ratePct].
double fixedDepositValue(double amount, int years, {double ratePct = 7}) => amount * math.pow(1 + ratePct / 100, years);

typedef WhatIfSimulator = Future<Map<String, dynamic>?> Function(String symbol, String market, double amount, int years);

class WhatIfScreen extends StatefulWidget {
  const WhatIfScreen({super.key, this.simulate});

  /// Replaces the `whatif` function call (tests).
  final WhatIfSimulator? simulate;

  @override
  State<WhatIfScreen> createState() => _WhatIfScreenState();
}

class _WhatIfScreenState extends State<WhatIfScreen> {
  static const _years = [1, 3, 5, 7, 10];
  static const _picks = {'stock': ['RELIANCE', 'TCS', 'HDFCBANK', 'INFY'], 'crypto': ['BTC', 'ETH', 'SOL', 'XRP']};

  String _symbol = 'RELIANCE';
  String _market = 'stock';
  int _yearsAgo = 5;
  bool _busy = false;
  bool _lockedOut = false;
  Map<String, dynamic>? _result;
  List<double> _growth = const [];
  Timer? _debounce;
  final _amountController = TextEditingController(text: '10000');

  double get _amount => double.tryParse(_amountController.text.replaceAll(',', '')) ?? 0;

  @override
  void initState() {
    super.initState();
    _run();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  /// Re-runs on every change; a stale answer for a previous input is dropped.
  Future<void> _run() async {
    final amount = _amount, years = _yearsAgo, symbol = _symbol, market = _market;
    if (amount <= 0) {
      setState(() => _result = null);
      return;
    }
    setState(() => _busy = true);
    // Free accounts get one What-If a day. A "use" is one stock and period on one
    // day; changing only the amount re-scales the same answer, so it is free.
    if (widget.simulate == null && PlanService.instance.limitFor(PlanFeature.whatIf) != null) {
      final day = DateTime.now().toIso8601String().substring(0, 10);
      try {
        final res = await SupabaseService().client.rpc('use_feature', params: {'p_feature': PlanFeature.whatIf, 'p_ref': '$day:$market:$symbol:$years'});
        if (res is Map && res['allowed'] == false) {
          if (!mounted) return;
          setState(() {
            _busy = false;
            _lockedOut = true;
            _result = null;
          });
          return;
        }
      } catch (_) {/* fail open: a metering hiccup must not break the screen */}
      PlanService.instance.refreshUsage();
    }
    if (mounted && _lockedOut) setState(() => _lockedOut = false);
    final sim = widget.simulate ?? MarketService.simulateWhatIf;
    final result = await sim(symbol, market, amount, years);
    if (!mounted || symbol != _symbol || years != _yearsAgo || amount != _amount) return;
    setState(() {
      _result = result;
      _busy = false;
      _growth = const [];
    });
    if (result == null) return;
    // The history service reaches back five years; longer windows skip the chart.
    if (years <= 5 && widget.simulate == null) {
      final pts = await SupabaseService().getHistory(symbol, market, years == 1 ? '1y' : '5y').catchError((_) => <Map<String, dynamic>>[]);
      final from = DateTime.now().subtract(Duration(days: 365 * years)).millisecondsSinceEpoch;
      final closes = [for (final p in pts) if (p['v'] is num && (p['t'] as num? ?? 0) >= from) (p['v'] as num).toDouble()];
      if (mounted && symbol == _symbol && years == _yearsAgo && closes.length > 1) setState(() => _growth = closes);
    }
  }

  void _pick({String? symbol, String? market, int? years}) {
    setState(() {
      if (market != null && market != _market) {
        _market = market;
        _symbol = _picks[market]!.first;
      }
      if (symbol != null) _symbol = symbol;
      if (years != null) _yearsAgo = years;
    });
    // User-picked stock/period re-runs the simulation (there is no separate Run button).
    ChurnTelemetryService.instance.recordButtonTap('whatif_run_simulation_cta', extra: {'sym': _symbol});
    _run();
  }

  void _showAssetSearchSheet() => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => _AssetSearchBottomSheet(market: _market, onSelected: (symbol, name) => _pick(symbol: symbol)),
      );

  @override
  Widget build(BuildContext context) {
    final r = _result;
    final value = (r?['current_value'] as num?)?.toDouble() ?? 0;
    final invested = (r?['amount_invested'] as num?)?.toDouble() ?? _amount;
    final gain = value - invested;
    final up = gain >= 0;
    final cagr = whatIfCagr(invested, value, _yearsAgo);
    final picks = {..._picks[_market]!, _symbol};

    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 10, AppSpacing.lg, 10),
            child: Row(children: [
              AuthIconButton(icon: Icons.arrow_back_rounded, label: 'Back', onTap: () => Navigator.of(context).maybePop()),
              const SizedBox(width: 10),
              Expanded(child: Text('What-If simulator', style: AppFonts.sans(size: 20, weight: FontWeight.w700, color: AppColors.ink))),
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
            child: ListView(padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 4, AppSpacing.lg, AppSpacing.lg), children: [
              Text('See what a past investment would be worth today.', style: AppFonts.sans(size: 13, color: AppColors.ink3)),
              const SizedBox(height: 14),
              Row(children: [
                for (final (m, label) in const [('stock', 'Stocks'), ('crypto', 'Crypto')]) ...[
                  if (m == 'crypto') const SizedBox(width: 6),
                  Expanded(child: _chip(label, _market == m, () => _pick(market: m), mono: false)),
                ],
              ]),
              const SizedBox(height: 14),
              _label('Symbol'),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final s in picks) _chip(s, s == _symbol, () => _pick(symbol: s)),
                _chip('More…', false, _showAssetSearchSheet, mono: false),
              ]),
              const SizedBox(height: 14),
              _label('Investment amount (${Money.symbol})'),
              TextField(
                controller: _amountController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9,]'))],
                style: AppFonts.mono(size: 16, weight: FontWeight.w500, color: AppColors.ink),
                onChanged: (_) {
                  _debounce?.cancel();
                  _debounce = Timer(const Duration(milliseconds: 500), _run);
                },
              ),
              const SizedBox(height: 14),
              _label('Years ago'),
              Row(children: [
                for (final y in _years) ...[
                  if (y != 1) const SizedBox(width: 6),
                  Expanded(child: _chip('${y}Y', y == _yearsAgo, () => _pick(years: y))),
                ],
              ]),
              const SizedBox(height: 14),
              const UsageChip(feature: PlanFeature.whatIf, noun: 'simulations', period: 'today'),
              const SizedBox(height: 10),
              if (_lockedOut)
                const LockedFeatureCard(
                  title: 'Today\'s free simulation is used',
                  message: 'Free accounts get one What-If a day (changing the amount is free). Pro runs as many as you like.',
                  source: 'whatif_daily',
                )
              else
                _resultCard(r, value, invested, gain, up, cagr),
              if (r != null) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: _card,
                  child: Row(children: [
                    Text('vs. fixed deposit at 7%:', style: AppFonts.sans(size: 13, color: AppColors.ink3)),
                    const Spacer(),
                    Text(Money.wallet(fixedDepositValue(invested, _yearsAgo), decimals: 0), style: AppFonts.mono(size: 13, color: AppColors.ink)),
                  ]),
                ),
              ],
              const SizedBox(height: 14),
              Text(
                'Illustrative figures based on historical prices${_market == 'crypto' ? ' (the coin\'s INR pair)' : ''}. Past returns don\'t guarantee future returns.',
                style: AppFonts.sans(size: 11, color: AppColors.ink4),
              ),
              const SizedBox(height: 14),
              ElevatedButton(
                onPressed: () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => StockDetailScreen(symbol: _symbol, market: _market, name: _symbol))),
                child: Text('Practise trading $_symbol'),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  BoxDecoration get _card => BoxDecoration(
        color: AppColors.pureWhite,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.birch),
      );

  Widget _label(String text) =>
      Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(text, style: AppFonts.sans(size: 12, weight: FontWeight.w500, color: AppColors.ink3)));

  Widget _chip(String label, bool on, VoidCallback onTap, {bool mono = true}) {
    final style = mono
        ? AppFonts.mono(size: 13, weight: FontWeight.w600, color: on ? AppColors.goldMid : AppColors.ink3)
        : AppFonts.sans(size: 13, weight: FontWeight.w600, color: on ? AppColors.goldMid : AppColors.ink3);
    return Material(
      color: on ? AppColors.goldPale : Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm), side: BorderSide(color: on ? AppColors.goldMid : AppColors.birch)),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        onTap: onTap,
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.center,
          child: Text(label, style: style),
        ),
      ),
    );
  }

  Widget _resultCard(Map<String, dynamic>? r, double value, double invested, double gain, bool up, double cagr) {
    if (r == null) {
      return Container(
        height: 160,
        alignment: Alignment.center,
        decoration: _card,
        child: _busy
            ? const CircularProgressIndicator()
            : Text(_amount <= 0 ? 'Enter an amount to see the result.' : 'No price history for $_symbol. Try another symbol.',
                textAlign: TextAlign.center, style: AppText.body),
      );
    }
    final tone = up ? AppColors.bull : AppColors.bear;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _card,
      child: Column(children: [
        Text.rich(
          TextSpan(style: AppFonts.sans(size: 13, color: AppColors.ink3), children: [
            TextSpan(text: '${Money.wallet(invested, decimals: 0)} in '),
            TextSpan(text: _symbol, style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink)),
            TextSpan(text: ' $_yearsAgo year${_yearsAgo == 1 ? '' : 's'} ago is now'),
          ]),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(Money.wallet(value, decimals: 0), style: AppFonts.mono(size: 38, weight: FontWeight.w600, color: tone)),
        ),
        const SizedBox(height: 6),
        Text.rich(TextSpan(style: AppFonts.mono(size: 13), children: [
          TextSpan(
            text: '${up ? '+' : '−'}${Money.wallet(gain.abs(), decimals: 0)} (${up ? '+' : '−'}${invested > 0 ? (gain.abs() / invested * 100).round() : 0}%)',
            style: TextStyle(color: tone),
          ),
          TextSpan(text: ' · CAGR ${cagr.toStringAsFixed(1)}%', style: TextStyle(color: AppColors.ink4)),
        ])),
        if (_growth.length > 1) ...[
          const SizedBox(height: 12),
          Semantics(
            label: 'Growth of the investment over $_yearsAgo years',
            child: SizedBox(height: 90, child: CustomPaint(size: Size.infinite, painter: _GrowthPainter(_growth, tone))),
          ),
          Row(children: [
            Text('${DateTime.now().year - _yearsAgo}', style: AppFonts.mono(size: 11, color: AppColors.ink4)),
            const Spacer(),
            Text('${DateTime.now().year}', style: AppFonts.mono(size: 11, color: AppColors.ink4)),
          ]),
        ],
      ]),
    );
  }
}

/// Line with a soft fill, scaled to the series.
class _GrowthPainter extends CustomPainter {
  _GrowthPainter(this.values, this.color);
  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final lo = values.reduce((a, b) => a < b ? a : b), hi = values.reduce((a, b) => a > b ? a : b);
    final span = hi == lo ? 1.0 : hi - lo;
    Offset at(int i) => Offset(size.width * i / (values.length - 1), 4 + (size.height - 8) * (1 - (values[i] - lo) / span));
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
      ..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(_GrowthPainter old) => old.values != values || old.color != color;
}

class _AssetSearchBottomSheet extends StatefulWidget {
  final String market;
  final void Function(String symbol, String name) onSelected;

  const _AssetSearchBottomSheet({
    required this.market,
    required this.onSelected,
  });

  @override
  State<_AssetSearchBottomSheet> createState() => _AssetSearchBottomSheetState();
}

class _AssetSearchBottomSheetState extends State<_AssetSearchBottomSheet> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _results = [];
  bool _loading = false;
  Timer? _debounce;

  final List<Map<String, String>> _popularStocks = [
    {'symbol': 'RELIANCE', 'name': 'Reliance Industries'},
    {'symbol': 'TCS', 'name': 'Tata Consultancy Services'},
    {'symbol': 'HDFCBANK', 'name': 'HDFC Bank'},
    {'symbol': 'INFY', 'name': 'Infosys'},
    {'symbol': 'ICICIBANK', 'name': 'ICICI Bank'},
    {'symbol': 'TMCV', 'name': 'Tata Motors (Commercial)'},
    {'symbol': 'TMPV', 'name': 'Tata Motors (Passenger)'},
    {'symbol': 'ADANIENT', 'name': 'Adani Enterprises'},
    {'symbol': 'ZOMATO', 'name': 'Zomato'},
  ];

  final List<Map<String, String>> _popularCrypto = [
    {'symbol': 'BTC', 'name': 'Bitcoin'},
    {'symbol': 'ETH', 'name': 'Ethereum'},
    {'symbol': 'SOL', 'name': 'Solana'},
    {'symbol': 'BNB', 'name': 'BNB'},
    {'symbol': 'XRP', 'name': 'Ripple'},
    {'symbol': 'ADA', 'name': 'Cardano'},
    {'symbol': 'DOGE', 'name': 'Dogecoin'},
    {'symbol': 'POL', 'name': 'Polygon'},
  ];

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String val) {
    _debounce?.cancel();
    setState(() {
      _loading = val.trim().isNotEmpty;
    });
    if (val.trim().isEmpty) {
      setState(() => _results = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(val.trim()));
  }

  Future<void> _search(String query) async {
    setState(() => _loading = true);
    try {
      final results = await MarketService.search(query, widget.market);
      if (!mounted) return;
      setState(() {
        _results = results;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _results = [];
        _loading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Search failed. Check your connection and try again.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final popularList = widget.market == 'stock' ? _popularStocks : _popularCrypto;
    final displayList = _searchController.text.trim().isEmpty ? popularList : _results;

    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration:       BoxDecoration(
        color: AppColors.pureWhite,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        children: [
          const SizedBox(height: 8),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.birch,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Select ${widget.market == 'stock' ? 'Stock' : 'Crypto'}',
                  style: GoogleFonts.ibmPlexSans(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.ink),
                ),
                IconButton(
                  icon:       Icon(Icons.close, color: AppColors.ink3),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.cream,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.birch),
            ),
            child: Row(
              children: [
                      Icon(Icons.search, size: 18, color: AppColors.ink4),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onChanged: _onSearchChanged,
                    decoration: InputDecoration(
                      hintText: widget.market == 'stock' ? 'Search NSE stocks...' : 'Search crypto...',
                      hintStyle: GoogleFonts.ibmPlexSans(color: AppColors.ink5),
                      border: InputBorder.none,
                    ),
                    style: GoogleFonts.ibmPlexSans(fontSize: 15, color: AppColors.ink),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : (_searchController.text.trim().isNotEmpty && displayList.isEmpty)
                    ? EmptyState(
                        icon: Icons.search_off_rounded,
                        title: 'No results',
                        message: 'No matches for "${_searchController.text.trim()}". Try a different name or symbol.',
                      )
                    : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                    itemCount: displayList.length,
                    itemBuilder: (context, index) {
                      final item = displayList[index];
                      final symbol = item['symbol'] as String? ?? '';
                      final name = item['name'] as String? ?? '';
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(vertical: 4),
                        leading: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: AppColors.goldPale,
                            shape: BoxShape.circle,
                            border: Border.all(color: AppColors.goldBorder),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            symbol.length >= 2 ? symbol.substring(0, 2) : symbol,
                            style: GoogleFonts.ibmPlexSans(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.goldDeep),
                          ),
                        ),
                        title: Text(
                          symbol,
                          style: GoogleFonts.ibmPlexSans(fontWeight: FontWeight.bold, color: AppColors.ink),
                        ),
                        subtitle: Text(
                          name,
                          style: GoogleFonts.ibmPlexSans(fontSize: 12, color: AppColors.ink4),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () {
                          widget.onSelected(symbol, name);
                          Navigator.pop(context);
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
