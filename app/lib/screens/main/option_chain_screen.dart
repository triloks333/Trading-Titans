import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../core/money.dart';
import '../../core/theme.dart';
import '../../models/quote.dart';
import '../../services/fo_instruments_service.dart';
import '../../services/market_service.dart';
import '../../services/theme_service.dart';
import '../../widgets/auth_kit.dart';

import 'option_detail_screen.dart';
import 'order_entry_screen.dart';
import '../../services/churn_telemetry_service.dart';
import '../../services/supabase_service.dart';
import 'dart:async';
import '../../services/action_reaction_engine.dart';
import 'glossary_screen.dart';
import 'strategy_builder_screen.dart';

/// Black-Scholes delta from implied volatility in percent (r = 6.5%, as the
/// strike detail uses). Calls are 0..1, puts -1..0.
double bsDelta({required double spot, required double strike, required double years, required double ivPct, required bool isCall}) {
  if (spot <= 0 || strike <= 0 || years <= 0 || ivPct <= 0) return isCall ? (spot > strike ? 1 : 0) : (spot < strike ? -1 : 0);
  final sigma = ivPct / 100, sqrtT = math.sqrt(years);
  final d1 = (math.log(spot / strike) + (0.065 + sigma * sigma / 2) * years) / (sigma * sqrtT);
  // Abramowitz-Stegun normal CDF, accurate to ~1e-7.
  double cdf(double x) {
    final t = 1 / (1 + 0.2316419 * x.abs());
    final poly = t * (0.319381530 + t * (-0.356563782 + t * (1.781477937 + t * (-1.821255978 + t * 1.330274429))));
    final tail = math.exp(-x * x / 2) / math.sqrt(2 * math.pi) * poly;
    return x >= 0 ? 1 - tail : tail;
  }

  return isCall ? cdf(d1) : cdf(d1) - 1;
}

class OptionChainScreen extends StatefulWidget {
  final String underlyingSymbol;
  final double spotPrice;
  final String market;

  /// A chain to show instead of fetching one (used by tests).
  final Map<String, dynamic>? data;

  const OptionChainScreen({
    super.key,
    required this.underlyingSymbol,
    required this.spotPrice,
    this.market = 'stock',
    this.data,
  });

  @override
  State<OptionChainScreen> createState() => _OptionChainScreenState();
}

class _OptionChainScreenState extends State<OptionChainScreen> {
  bool _loading = true;
  String? _error;
  List<String> _expiries = [];
  String? _selectedExpiry;
  List<dynamic> _allChains = [];
  List<dynamic> _currentStrikes = [];
  List<dynamic> _futures = [];
  String _derivativeType = 'options';
  double _spotPrice = 0.0;

  /// Strike list scroll; opens centred on the spot line (rows are 46 px).
  final _strikesScroll = ScrollController();
  static const _rowHeight = 46.0;
  double _change = 0.0;
  double _changePct = 0.0;
  bool _greeks = false;
  int? _lotSize;

  @override
  void initState() {
    super.initState();
    _openedAt = DateTime.now();
    _helperTimer = Timer(const Duration(seconds: 8), _maybeShowHelper);
    _loadOptionChain();
    _spotPrice = widget.spotPrice;
    if (widget.market == 'stock') {
      FoInstrumentsService().getLotSize(widget.underlyingSymbol).then((l) {
        if (mounted && l > 1) setState(() => _lotSize = l);
      }).catchError((_) {});
    }
  }

  @override
  void dispose() {
    _helperTimer?.cancel();
    _strikesScroll.dispose();
    super.dispose();
  }

  late final DateTime _openedAt;
  Timer? _helperTimer;

  /// Scrolled the chain for 8s without tapping a strike: explain how to read it.
  Future<void> _maybeShowHelper() async {
    final t = ChurnTelemetryService.instance;
    final tapped = t.intel.events.any((e) =>
        e.name == 'tap' && !e.ts.isBefore(_openedAt) && '${e.props['button']}'.endsWith('_cell_tap'));
    if (!mounted || tapped || t.currentScrollPct <= 0) return;
    if (!await ActionReactionEngine.instance.optionChainHelper(widget.underlyingSymbol) || !mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Reading the option chain', style: AppText.cardTitle),
            const SizedBox(height: 10),
            for (final line in const [
              'Calls (CE) are on the left, puts (PE) on the right, strike prices in the middle.',
              'ATM is the strike nearest the current price. Calls below it are in the money (ITM), above it out of the money (OTM). Puts are the reverse.',
              'LTP is the premium for one unit. One lot costs premium × lot size.',
              'A bought call gains if the price ends above strike + premium; a bought put if it ends below strike − premium.',
            ])
              Padding(padding: const EdgeInsets.only(bottom: 8), child: Text('• $line', style: AppText.body)),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const GlossaryScreen()));
                },
                child: const Text('Open glossary'),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _loadOptionChain() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // Prefer real NSE strikes from our DB (priced with the same estimator as
      // the fill engine). Fall back to the live providers / mock chain.
      Map<String, dynamic>? data = widget.data;
      if (data == null) {
        try {
          data = await SupabaseService().getOptionChainFromDb(widget.underlyingSymbol, market: widget.market);
        } catch (_) {
          data = null;
        }
      }
      data ??= await MarketService.getOptionChain(
        widget.underlyingSymbol,
        market: widget.market,
      );
      if (data == null) {
        throw Exception('Failed to load option chain');
      }

      // Check if API returned an error with derivative_type info
      if (data['error'] != null) {
        throw Exception(data['error'] as String);
      }

      final expiries = List<String>.from(data['expiries'] ?? []);
      final chains = data['chains'] as List<dynamic>? ?? [];
      final futures = data['futures'] as List<dynamic>? ?? [];
      final derivativeType = data['derivative_type'] as String? ?? 'options';
      final spot = (data['spot_price'] as num?)?.toDouble() ?? widget.spotPrice;
      final change = (data['change'] as num?)?.toDouble() ?? 0.0;
      final changePct = (data['change_pct'] as num?)?.toDouble() ?? 0.0;

      setState(() {
        _expiries = expiries;
        _allChains = chains;
        _futures = futures;
        _derivativeType = derivativeType;
        _spotPrice = spot;
        _change = change;
        _changePct = changePct;

        // For crypto, auto-switch to futures since options aren't available
        if (widget.market == 'crypto' && chains.isEmpty && futures.isNotEmpty) {
          _derivativeType = 'futures';
        }

        if (_expiries.isNotEmpty) {
          _selectedExpiry ??= _expiries.first;
          _updateStrikesForExpiry(_selectedExpiry!);
        }
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
        _loading = false;
      });
    }
  }

  void _updateStrikesForExpiry(String expiry) {
    final chain = _allChains.where((c) => c['expiry_date'] == expiry).firstOrNull;
    setState(() {
      _currentStrikes = chain != null
          ? (chain['strikes'] as List<dynamic>? ?? [])
          : [];
    });
    // Strikes run low to high, so without this the list opened deep in the money.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_strikesScroll.hasClients) return;
      final below = _currentStrikes.where((s) => ((s as Map)['strike_price'] as num) <= _spotPrice).length;
      final pos = _strikesScroll.position;
      _strikesScroll.jumpTo((below * _rowHeight - pos.viewportDimension / 2).clamp(0.0, pos.maxScrollExtent));
    });
  }

  /// Multi-leg strategy builder on this chain's strikes and expiry (Titan).
  Future<void> _openStrategyBuilder() async {
    ChurnTelemetryService.instance.recordButtonTap('option_chain_strategy_builder_btn', extra: {'sym': widget.underlyingSymbol});
    var lot = _lotSize;
    if (lot == null || lot <= 1) {
      try {
        lot = await FoInstrumentsService().getLotSize(widget.underlyingSymbol);
      } catch (_) {}
    }
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StrategyBuilderScreen(
          underlying: widget.underlyingSymbol,
          spot: _spotPrice,
          expiry: _selectedExpiry!,
          lotSize: (lot == null || lot < 1) ? 1 : lot,
          chain: [for (final r in _currentStrikes) Map<String, dynamic>.from(r as Map)],
          market: widget.market,
        ),
      ),
    );
    _loadOptionChain();
  }

  void _openOptionDetail(Map<String, dynamic> option, bool isCall) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => OptionDetailScreen(
          optionData: option,
          underlyingSymbol: widget.underlyingSymbol,
          underlyingSpotPrice: _spotPrice,
          market: widget.market,
        ),
      ),
    );
    _loadOptionChain();
  }

  Future<void> _openFutureOrder(Map<String, dynamic> future, bool isBuy) async {
    final price = (future['price'] as num?)?.toDouble() ?? 0.0;
    final prev = (future['previous_close'] as num?)?.toDouble() ?? price;
    final change = (future['change'] as num?)?.toDouble() ?? 0.0;
    final changePct = (future['change_pct'] as num?)?.toDouble() ?? 0.0;
    final symbol = future['symbol'] as String? ?? '';
    final quote = Quote(
      symbol: symbol,
      yfSymbol: future['provider_symbol'] as String? ?? symbol,
      name: future['name'] as String? ?? symbol,
      price: price,
      previousClose: prev,
      change: change,
      changePct: changePct,
      currency: future['currency'] as String? ?? 'USDT',
      market: widget.market,
      source: future['source'] as String?,
      category: 'crypto_futures',
      dayLow: (future['low'] as num?)?.toDouble(),
      dayHigh: (future['high'] as num?)?.toDouble(),
      volume: (future['volume'] as num?)?.toInt(),
    );

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => OrderEntryScreen(
          quote: quote,
          isBuy: isBuy,
          instrumentType: 'FUTURE',
          expiryDate: future['expiry_date'] as String? ?? 'PERPETUAL',
        ),
      ),
    );
    _loadOptionChain();
  }

  String _formatOi(num value) {
    if (value >= 100000) {
      return '${(value / 100000).toStringAsFixed(1)}L';
    } else if (value >= 1000) {
      return '${(value / 1000).toStringAsFixed(1)}k';
    }
    return value.toString();
  }

  String _formatVolume(int value) {
    if (value >= 10000000) {
      return '${(value / 10000000).toStringAsFixed(1)}Cr';
    } else if (value >= 100000) {
      return '${(value / 100000).toStringAsFixed(1)}L';
    } else if (value >= 1000) {
      return '${(value / 1000).toStringAsFixed(1)}K';
    }
    return value.toString();
  }

  // ── Summary metric helpers ──────────────────────────────────────────

  double _computePCR() {
    double totalCallOi = 0;
    double totalPutOi = 0;
    for (final s in _currentStrikes) {
      totalCallOi += ((s['call'] as Map?)?['open_interest'] as num?)?.toDouble() ?? 0;
      totalPutOi += ((s['put'] as Map?)?['open_interest'] as num?)?.toDouble() ?? 0;
    }
    return totalCallOi > 0 ? totalPutOi / totalCallOi : 0;
  }

  double _computeMaxPain() {
    if (_currentStrikes.isEmpty) return 0;
    double minPain = double.infinity;
    double maxPainStrike = 0;
    for (final s in _currentStrikes) {
      final expiryStrike = (s['strike_price'] as num).toDouble();
      double pain = 0;
      for (final other in _currentStrikes) {
        final otherStrike = (other['strike_price'] as num).toDouble();
        final cOi = ((other['call'] as Map?)?['open_interest'] as num?)?.toDouble() ?? 0;
        final pOi = ((other['put'] as Map?)?['open_interest'] as num?)?.toDouble() ?? 0;
        pain += cOi * (expiryStrike - otherStrike > 0 ? expiryStrike - otherStrike : 0);
        pain += pOi * (otherStrike - expiryStrike > 0 ? otherStrike - expiryStrike : 0);
      }
      if (pain < minPain) {
        minPain = pain;
        maxPainStrike = expiryStrike;
      }
    }
    return maxPainStrike;
  }

  String _computeAtmIV() {
    if (_currentStrikes.isEmpty) return 'N/A';
    double closest = double.infinity;
    Map<String, dynamic>? atmStrike;
    for (final s in _currentStrikes) {
      final dist = ((s['strike_price'] as num).toDouble() - _spotPrice).abs();
      if (dist < closest) {
        closest = dist;
        atmStrike = s as Map<String, dynamic>;
      }
    }
    if (atmStrike == null) return 'N/A';
    final callIV = (atmStrike['call'] as Map?)?['implied_volatility'];
    final putIV = (atmStrike['put'] as Map?)?['implied_volatility'];
    if (callIV != null) return '${(callIV as num).toStringAsFixed(1)}%';
    if (putIV != null) return '${(putIV as num).toStringAsFixed(1)}%';
    return 'N/A';
  }

  /// Says out loud that the premiums in the table are modelled, not quoted.
  ///
  /// The app has no live options feed, so every premium shown here is a
  /// Black-Scholes estimate off the live spot. That is a deliberate design
  /// choice — it keeps the chain price identical to the price the fill engine
  /// uses, so a limit order cannot fill at a number the user never saw — but it
  /// does mean the figure can sit some way from the exchange's own. Users were
  /// reporting that gap as a bug, so the screen now states it and points at the
  /// real closing price, which the strike detail carries per contract.
  ///
  /// Open interest, by contrast, IS real market data from the daily NSE
  /// bhavcopy, so the notice is careful not to tar it with the same brush.
  Widget _buildEstimateNotice() {
    if (_derivativeType != 'options' || _currentStrikes.isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      color: AppColors.goldPale.withValues(alpha: 0.35),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 13, color: AppColors.goldDeep),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Premiums are estimated from the live spot price and may differ from '
              'the exchange. Open interest is real NSE data. Tap a strike for its '
              'last traded close.',
              style: GoogleFonts.ibmPlexSans(
                fontSize: 10,
                height: 1.35,
                fontWeight: FontWeight.w500,
                color: AppColors.ink3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Layout ──────────────────────────────────────────────────────────

  /// "W" for a weekly expiry, "M" for the last expiry of its month.
  String _expiryTag(String expiry) {
    final d = DateTime.tryParse(expiry);
    if (d == null) return '';
    final laterSameMonth = _expiries.any((e) {
      final o = DateTime.tryParse(e);
      return o != null && o.year == d.year && o.month == d.month && o.isAfter(d);
    });
    return laterSameMonth ? 'W' : 'M';
  }

  bool _expired(String expiry) {
    final exp = DateTime.tryParse(expiry);
    return exp != null && DateTime.now().isAfter(DateTime(exp.year, exp.month, exp.day, 15, 30));
  }

  /// Delta for one side of a strike: the feed's own if it sent one, else
  /// Black-Scholes from the contract's implied volatility.
  double? _delta(Map<String, dynamic> opt, double strike, bool isCall) {
    final api = (opt['delta'] as num?)?.toDouble();
    if (api != null) return api;
    final iv = (opt['implied_volatility'] as num?)?.toDouble();
    final exp = DateTime.tryParse(_selectedExpiry ?? '');
    if (iv == null || exp == null) return null;
    final days = exp.difference(DateTime.now()).inHours / 24;
    return bsDelta(spot: _spotPrice, strike: strike, years: (days < 1 ? 1 : days) / 365, ivPct: iv, isCall: isCall);
  }

  Widget _header() {
    final isUp = _change >= 0;
    return Container(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 10, AppSpacing.lg, 10),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.birch))),
      child: Row(children: [
        AuthIconButton(icon: Icons.arrow_back_rounded, label: 'Back', onTap: () => Navigator.of(context).maybePop()),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              _derivativeType == 'futures' ? '${widget.underlyingSymbol} futures' : '${widget.underlyingSymbol} option chain',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppFonts.sans(size: 16, weight: FontWeight.w700, color: AppColors.ink),
            ),
            Text.rich(
              TextSpan(style: AppFonts.mono(size: 12, color: AppColors.ink3), children: [
                TextSpan(text: 'Spot ${Money.bare(_spotPrice, from: Money.sourceFor(widget.market))} '),
                TextSpan(
                    text: '${isUp ? '▲' : '▼'}${_changePct.abs().toStringAsFixed(2)}%',
                    style: TextStyle(color: isUp ? AppColors.bull : AppColors.bear)),
                if (_derivativeType == 'options' && _currentStrikes.isNotEmpty) TextSpan(text: ' · PCR ${_computePCR().toStringAsFixed(2)}'),
              ]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ]),
        ),
        if (_derivativeType == 'options' && _currentStrikes.isNotEmpty && _selectedExpiry != null) ...[
          AuthIconButton(icon: Icons.auto_graph_rounded, label: 'Strategy builder', onTap: _openStrategyBuilder),
          const SizedBox(width: 8),
        ],
        AuthIconButton(icon: Icons.refresh_rounded, label: 'Refresh chain', onTap: _loadOptionChain),
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
  }

  /// The design's segmented control.
  Widget _segmented(List<(String, bool, VoidCallback)> items) => Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: AppColors.cream, borderRadius: BorderRadius.circular(AppRadius.md)),
        child: Row(children: [
          for (final (i, (label, on, tap)) in items.indexed) ...[
            if (i > 0) const SizedBox(width: 4),
            Expanded(
              child: Semantics(
                button: true,
                selected: on,
                label: label,
                excludeSemantics: true,
                child: GestureDetector(
                  onTap: tap,
                  child: Container(
                    height: 32,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: on ? AppColors.pureWhite : Colors.transparent,
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Text(label, style: AppFonts.sans(size: 12, weight: FontWeight.w600, color: on ? AppColors.ink : AppColors.ink3)),
                  ),
                ),
              ),
            ),
          ],
        ]),
      );

  Widget _expiryChips() => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (final e in _expiries)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Material(
                color: e == _selectedExpiry ? AppColors.goldPale : Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  side: BorderSide(color: e == _selectedExpiry ? AppColors.goldMid : AppColors.birch),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  onTap: () {
                    final i = _expiries.indexOf(e);
                    if (i >= 0 && i < 3) {
                      ChurnTelemetryService.instance.recordButtonTap(const ['option_chain_expiry_date_1_near', 'option_chain_expiry_date_2_next', 'option_chain_expiry_date_3_monthly'][i]);
                    }
                    setState(() => _selectedExpiry = e);
                    _updateStrikesForExpiry(e);
                  },
                  child: Container(
                    height: 32,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    alignment: Alignment.center,
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(
                        DateTime.tryParse(e) == null ? e : DateFormat('d MMM').format(DateTime.parse(e)),
                        style: AppFonts.sans(
                            size: 13, weight: FontWeight.w500, color: e == _selectedExpiry ? AppColors.goldMid : AppColors.ink3),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: AppCard.badge(_expired(e) ? AppColors.bearLight : AppColors.cream),
                        child: Text(_expired(e) ? 'EXP' : _expiryTag(e),
                            style: AppText.badge.copyWith(color: _expired(e) ? AppColors.bear : AppColors.ink3)),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
        ]),
      );

  /// One strike: [OI|Δ] · call LTP · strike · put LTP · [OI|Δ]. In-the-money
  /// cells are shaded; tapping a side opens that contract.
  Widget _strikeRow(Map<String, dynamic> row, double strike) {
    final call = Map<String, dynamic>.from(row['call'] as Map);
    final put = Map<String, dynamic>.from(row['put'] as Map);
    final itm = AppColors.isDark ? const Color(0xFF121B26) : const Color(0xFFFBF6EA);
    String outer(Map<String, dynamic> opt, bool isCall) {
      if (!_greeks) return _formatOi(opt['open_interest'] as num? ?? 0);
      final d = _delta(opt, strike, isCall);
      return d == null ? '—' : 'Δ ${d < 0 ? '−' : ''}${d.abs().toStringAsFixed(2)}';
    }

    Widget cell(String text, {required bool shade, bool strong = false, TextAlign align = TextAlign.left}) => Expanded(
          child: Container(
            color: shade ? itm : null,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            alignment: align == TextAlign.right ? Alignment.centerRight : Alignment.centerLeft,
            child: Text(text,
                maxLines: 1,
                overflow: TextOverflow.fade,
                softWrap: false,
                style: AppFonts.mono(
                    size: 13, weight: strong ? FontWeight.w500 : FontWeight.w400, color: strong ? AppColors.ink : AppColors.ink3)),
          ),
        );

    final callItm = strike < _spotPrice, putItm = strike > _spotPrice;
    String ltp(Map<String, dynamic> o) => Money.bare((o['price'] as num? ?? 0).toDouble(), from: Money.sourceFor(widget.market));
    return Container(
      height: _rowHeight,
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.birch))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(
          flex: 2,
          child: InkWell(
            onTap: () {
            ChurnTelemetryService.instance.recordButtonTap('option_chain_call_ce_cell_tap', extra: {'sym': widget.underlyingSymbol});
            _openOptionDetail(call, true);
          },
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              cell(outer(call, true), shade: callItm),
              cell(ltp(call), shade: callItm, strong: true, align: TextAlign.right),
            ]),
          ),
        ),
        Container(
          width: 84,
          color: AppColors.cream,
          alignment: Alignment.center,
          child: Text(strike.toStringAsFixed(strike % 1 == 0 ? 0 : 1),
              style: AppFonts.mono(size: 13, weight: FontWeight.w600, color: AppColors.ink)),
        ),
        Expanded(
          flex: 2,
          child: InkWell(
            onTap: () {
            ChurnTelemetryService.instance.recordButtonTap('option_chain_put_pe_cell_tap', extra: {'sym': widget.underlyingSymbol});
            _openOptionDetail(put, false);
          },
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              cell(ltp(put), shade: putItm, strong: true),
              cell(outer(put, false), shade: putItm, align: TextAlign.right),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _spotDivider() => Container(
        color: AppColors.goldPale,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 2),
        child: Row(children: [
          Expanded(child: Container(height: 1, color: AppColors.goldMid)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text('SPOT ${Money.bare(_spotPrice, from: Money.sourceFor(widget.market))}',
                style: AppFonts.mono(size: 11, weight: FontWeight.w600, color: AppColors.goldMid)),
          ),
          Expanded(child: Container(height: 1, color: AppColors.goldMid)),
        ]),
      );

  Widget _optionsTable() {
    final strikes = List<dynamic>.from(_currentStrikes)
      ..sort((a, b) => (a['strike_price'] as num).compareTo(b['strike_price'] as num));
    final head = _greeks ? 'DELTA' : 'OI';
    TextStyle cap = AppText.sectionLabel;
    return Column(children: [
      _buildEstimateNotice(),
      Container(
        height: 34,
        color: AppColors.pureWhite,
        child: Row(children: [
          Expanded(child: Padding(padding: const EdgeInsets.only(left: 8), child: Text(head, style: cap))),
          Expanded(child: Padding(padding: const EdgeInsets.only(right: 8), child: Text('CALL', textAlign: TextAlign.right, style: cap))),
          SizedBox(width: 84, child: Text('STRIKE', textAlign: TextAlign.center, style: cap)),
          Expanded(child: Padding(padding: const EdgeInsets.only(left: 8), child: Text('PUT', style: cap))),
          Expanded(child: Padding(padding: const EdgeInsets.only(right: 8), child: Text(head, textAlign: TextAlign.right, style: cap))),
        ]),
      ),
      Divider(height: 1, color: AppColors.birch),
      Expanded(
        child: strikes.isEmpty
            ? Center(child: Text('No strikes found for this expiry.', style: AppText.body))
            : ListView(controller: _strikesScroll, children: [
                for (final (i, s) in strikes.indexed) ...[
                  // Spot divider sits between the last strike below spot and the first above.
                  if (i > 0 && (strikes[i - 1]['strike_price'] as num) <= _spotPrice && (s['strike_price'] as num) > _spotPrice)
                    _spotDivider(),
                  _strikeRow(Map<String, dynamic>.from(s as Map), (s['strike_price'] as num).toDouble()),
                ],
              ]),
      ),
      Container(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 10, AppSpacing.lg, 14),
        decoration: BoxDecoration(color: AppColors.pureWhite, border: Border(top: BorderSide(color: AppColors.birch))),
        child: Text.rich(
          TextSpan(style: AppFonts.sans(size: 12, color: AppColors.ink4), children: [
            const TextSpan(text: 'Shaded = in the money'),
            if (_lotSize != null) TextSpan(text: ' · lot $_lotSize'),
            if (strikes.isNotEmpty) ...[
              const TextSpan(text: ' · Max pain '),
              TextSpan(text: _computeMaxPain().toStringAsFixed(0), style: AppFonts.mono(size: 12, color: AppColors.ink)),
              const TextSpan(text: ' · ATM IV '),
              TextSpan(text: _computeAtmIV(), style: AppFonts.mono(size: 12, color: AppColors.ink)),
            ],
          ]),
        ),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          _header(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? _errorView()
                    : Column(children: [
                        Container(
                          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 10, AppSpacing.lg, 10),
                          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.birch))),
                          child: Column(children: [
                            if (widget.market == 'stock') ...[
                              _segmented([
                                ('Options', _derivativeType == 'options', () {
                                  ChurnTelemetryService.instance.recordButtonTap('option_chain_tab_options_btn');
                                  setState(() => _derivativeType = 'options');
                                }),
                                ('Futures', _derivativeType == 'futures', () {
                                  ChurnTelemetryService.instance.recordButtonTap('option_chain_tab_futures_btn');
                                  setState(() => _derivativeType = 'futures');
                                }),
                              ]),
                              const SizedBox(height: 10),
                            ],
                            if (_derivativeType == 'options') ...[
                              _expiryChips(),
                              const SizedBox(height: 10),
                              _segmented([
                                ('LTP · OI', !_greeks, () {
                                  ChurnTelemetryService.instance.recordButtonTap('option_chain_greeks_delta_iv_toggle');
                                  setState(() => _greeks = false);
                                }),
                                ('Greeks', _greeks, () {
                                  ChurnTelemetryService.instance.recordButtonTap('option_chain_greeks_delta_iv_toggle');
                                  setState(() => _greeks = true);
                                }),
                              ]),
                            ],
                          ]),
                        ),
                        Expanded(child: _derivativeType == 'futures' ? _buildFuturesList() : _optionsTable()),
                      ]),
          ),
        ]),
      ),
    );
  }

  Widget _errorView() => Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(widget.market == 'crypto' ? Icons.currency_bitcoin : Icons.info_outline,
                size: 48, color: widget.market == 'crypto' ? AppColors.titanGold : AppColors.ink4),
            const SizedBox(height: 16),
            Text(widget.market == 'crypto' ? 'Options not available for crypto' : _error!,
                textAlign: TextAlign.center, style: AppFonts.sans(size: 15, weight: FontWeight.w600, color: AppColors.ink)),
            const SizedBox(height: 12),
            Text(
              widget.market == 'crypto'
                  ? 'Crypto markets only support perpetual futures contracts. You can trade futures from the stock detail screen.'
                  : 'Please check your connection or try again later.',
              textAlign: TextAlign.center,
              style: AppText.body,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: widget.market == 'crypto' ? () => Navigator.pop(context) : _loadOptionChain,
              child: Text(widget.market == 'crypto' ? 'Go back' : 'Retry'),
            ),
          ]),
        ),
      );

  Widget _buildFuturesList() {
    if (_futures.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Text(
            'No active futures contracts found for ${widget.underlyingSymbol}.',
            textAlign: TextAlign.center,
            style: GoogleFonts.ibmPlexSans(color: AppColors.ink4),
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(AppSpacing.lg),
      itemCount: _futures.length,
      separatorBuilder: (_, index) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (context, index) {
        final future = Map<String, dynamic>.from(_futures[index] as Map);
        final price = (future['price'] as num?)?.toDouble() ?? 0.0;
        final changePct = (future['change_pct'] as num?)?.toDouble() ?? 0.0;
        final markPrice = (future['mark_price'] as num?)?.toDouble();
        final funding = (future['funding_rate'] as num?)?.toDouble();
        final isUp = changePct >= 0;
        final expStr = future['expiry_date'] as String?;
        final expDate = expStr != null && expStr != 'PERPETUAL' ? DateTime.tryParse(expStr) : null;
        final isFutureExpired = expDate != null && DateTime.now().isAfter(DateTime(expDate.year, expDate.month, expDate.day, 15, 30));

        return Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: AppColors.pureWhite,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: AppColors.birch),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          future['symbol'] as String? ?? '',
                          style: GoogleFonts.ibmPlexSans(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.ink,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          future['name'] as String? ?? 'Futures Contract',
                          style: GoogleFonts.ibmPlexSans(
                            fontSize: 12,
                            color: AppColors.ink4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${future['currency'] == 'INR' ? '₹' : (future['currency'] as String? ?? 'USDT')} ${price.toStringAsFixed(price < 10 ? 4 : 2)}',
                        style: GoogleFonts.ibmPlexSans(fontFeatures: const [FontFeature.tabularFigures()], 
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${isUp ? '+' : ''}${changePct.toStringAsFixed(2)}%',
                        style: GoogleFonts.ibmPlexSans(fontFeatures: const [FontFeature.tabularFigures()], 
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: isUp ? AppColors.bull : AppColors.bear,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  if (widget.market == 'crypto') ...[
                    // Crypto futures: show mark price and funding rate
                    Expanded(
                      child: _futureMeta(
                        'Mark',
                        markPrice == null
                            ? '--'
                            : markPrice.toStringAsFixed(markPrice < 10 ? 4 : 2),
                      ),
                    ),
                    Expanded(
                      child: _futureMeta(
                        'Funding',
                        funding == null
                            ? '--'
                            : '${(funding * 100).toStringAsFixed(4)}%',
                      ),
                    ),
                  ] else ...[
                    // Stock futures: show volume and day range
                    Expanded(
                      child: _futureMeta(
                        'Volume',
                        future['volume'] != null
                            ? _formatVolume((future['volume'] as num).toInt())
                            : '--',
                      ),
                    ),
                    Expanded(
                      child: _futureMeta(
                        'Day Range',
                        future['low'] != null && future['high'] != null
                            ? '${Money.wallet((future['low'] as num), decimals: 0)} - ${Money.wallet((future['high'] as num), decimals: 0)}'
                            : '--',
                      ),
                    ),
                  ],
                  Expanded(
                    child: _futureMeta(
                      'Expiry',
                      future['expiry_date'] as String? ?? 'PERPETUAL',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: isFutureExpired
                          ? null
                          : () {
                              ChurnTelemetryService.instance.recordButtonTap('option_chain_future_contract_buy_btn', extra: {'sym': widget.underlyingSymbol});
                              _openFutureOrder(future, true);
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isFutureExpired ? AppColors.birch : AppColors.bull,
                        disabledBackgroundColor: AppColors.birch,
                        foregroundColor: isFutureExpired ? AppColors.ink4 : AppColors.pureWhite,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.md),
                        ),
                      ),
                      child: Text(
                        isFutureExpired ? 'EXPIRED' : 'BUY',
                        style: GoogleFonts.ibmPlexSans(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: isFutureExpired
                          ? null
                          : () {
                              ChurnTelemetryService.instance.recordButtonTap('option_chain_future_contract_sell_btn', extra: {'sym': widget.underlyingSymbol});
                              _openFutureOrder(future, false);
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isFutureExpired ? AppColors.birch : AppColors.bear,
                        disabledBackgroundColor: AppColors.birch,
                        foregroundColor: isFutureExpired ? AppColors.ink4 : AppColors.pureWhite,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.md),
                        ),
                      ),
                      child: Text(
                        isFutureExpired ? 'EXPIRED' : 'SELL',
                        style: GoogleFonts.ibmPlexSans(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _futureMeta(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.ibmPlexSans(
            fontSize: 10,
            color: AppColors.ink4,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: GoogleFonts.ibmPlexSans(fontFeatures: const [FontFeature.tabularFigures()], 
            fontSize: 12,
            color: AppColors.ink,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
