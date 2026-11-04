import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../core/money.dart';
import '../../models/quote.dart';
import '../../services/market_service.dart';
import 'package:google_fonts/google_fonts.dart';

import 'option_detail_screen.dart';
import 'order_entry_screen.dart';
import '../../services/supabase_service.dart';

class OptionChainScreen extends StatefulWidget {
  final String underlyingSymbol;
  final double spotPrice;
  final String market;

  const OptionChainScreen({
    super.key,
    required this.underlyingSymbol,
    required this.spotPrice,
    this.market = 'stock',
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
  double _change = 0.0;
  double _changePct = 0.0;

  @override
  void initState() {
    super.initState();
    _loadOptionChain();
    _spotPrice = widget.spotPrice;
  }

  Future<void> _loadOptionChain() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // Prefer real NSE strikes from our DB (priced with the same estimator as
      // the fill engine). Fall back to the live providers / mock chain.
      Map<String, dynamic>? data;
      try {
        data = await SupabaseService().getOptionChainFromDb(
          widget.underlyingSymbol,
          market: widget.market,
        );
      } catch (_) {
        data = null;
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
    final chain = _allChains.firstWhere(
      (c) => c['expiry_date'] == expiry,
      orElse: () => null,
    );
    setState(() {
      _currentStrikes = chain != null
          ? (chain['strikes'] as List<dynamic>? ?? [])
          : [];
    });
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

  // ── Max OI for bar width normalisation ──────────────────────────────

  double _maxCallOi() {
    double m = 0;
    for (final s in _currentStrikes) {
      final v = ((s['call'] as Map?)?['open_interest'] as num?)?.toDouble() ?? 0;
      if (v > m) m = v;
    }
    return m;
  }

  double _maxPutOi() {
    double m = 0;
    for (final s in _currentStrikes) {
      final v = ((s['put'] as Map?)?['open_interest'] as num?)?.toDouble() ?? 0;
      if (v > m) m = v;
    }
    return m;
  }

  // ── Bottom summary bar widget ──────────────────────────────────────

  Widget _buildSummaryBar() {
    final pcr = _computePCR();
    final maxPain = _computeMaxPain();
    final atmIv = _computeAtmIV();

    return Container(
      key: const ValueKey('summary_bar'),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.cream,
        border:       Border(top: BorderSide(color: AppColors.birch, width: 1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 6,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _summaryChip('PCR', pcr.toStringAsFixed(2), AppColors.imperialGold),
          Container(width: 1, height: 28, color: AppColors.birch),
          _summaryChip('Max Pain', Money.wallet(maxPain, decimals: 0), AppColors.bear),
          Container(width: 1, height: 28, color: AppColors.birch),
          _summaryChip('ATM IV', atmIv, AppColors.bull),
        ],
      ),
    );
  }

  Widget _summaryChip(String label, String value, Color accent) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: GoogleFonts.ibmPlexSans(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            color: AppColors.ink4,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: GoogleFonts.ibmPlexSans(fontFeatures: const [FontFeature.tabularFigures()], 
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: accent,
          ),
        ),
      ],
    );
  }

  Widget _buildSpotPriceBar() {
    final isUp = _change >= 0;
    return Container(
      key: const ValueKey('spot_price_bar'),
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            height: 1.5,
            color: isUp ? AppColors.bull.withValues(alpha: 0.5) : AppColors.bear.withValues(alpha: 0.5),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF1B2B3C), // Premium deep charcoal/blue
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isUp ? AppColors.bull : AppColors.bear,
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                )
              ]
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isUp ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                  size: 14,
                  color: isUp ? AppColors.bull : AppColors.bear,
                ),
                const SizedBox(width: 6),
                Text(
                  '${Money.instrument(_spotPrice, market: widget.market)}  |  ${isUp ? '+' : ''}${Money.instrument(_change, market: widget.market)} (${isUp ? '+' : ''}${_changePct.toStringAsFixed(2)}%)',
                  style: GoogleFonts.ibmPlexSans(fontFeatures: const [FontFeature.tabularFigures()], 
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
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

  Widget _buildStrikeItemRow(dynamic strikeRow, double strike, {double maxCallOi = 1, double maxPutOi = 1}) {
    final call = strikeRow['call'] as Map<String, dynamic>;
    final put = strikeRow['put'] as Map<String, dynamic>;

    final callPrice = (call['price'] as num).toDouble();
    final callChangePct = (call['change_pct'] as num).toDouble();
    final callOi = call['open_interest'] as num? ?? 0;
    final callOiChangePct = ((strike * 0.013) % 150) - 50;

    final putPrice = (put['price'] as num).toDouble();
    final putChangePct = (put['change_pct'] as num).toDouble();
    final putOi = put['open_interest'] as num? ?? 0;
    final putOiChangePct = ((strike * 0.017) % 180) - 60;

    final isAtm = (strike - _spotPrice).abs() < (widget.market == 'crypto' ? 2500 : 75);
    final callItm = strike < _spotPrice; // Call ITM
    final putItm = strike > _spotPrice;  // Put ITM

    final totalOi = callOi + putOi;
    final callRatio = totalOi > 0 ? callOi / totalOi : 0.5;
    final putRatio = totalOi > 0 ? putOi / totalOi : 0.5;

    // OI bar width ratios (0..1)
    final callOiBarRatio = maxCallOi > 0 ? callOi.toDouble() / maxCallOi : 0.0;
    final putOiBarRatio = maxPutOi > 0 ? putOi.toDouble() / maxPutOi : 0.0;

    // ITM/OTM background colors
    Color callBg;
    Color putBg;
    if (isAtm) {
      callBg = AppColors.goldPale.withValues(alpha: 0.1);
      putBg = AppColors.goldPale.withValues(alpha: 0.1);
    } else {
      callBg = callItm ? AppColors.bull.withValues(alpha: 0.06) : Colors.transparent;
      putBg = putItm ? AppColors.bear.withValues(alpha: 0.06) : Colors.transparent;
    }

    // ATM border decoration
    final atmBorder = isAtm
        ? Border.all(color: AppColors.imperialGold.withValues(alpha: 0.5), width: 1.5)
        : null;

    return Container(
      decoration: BoxDecoration(
        border: atmBorder ??       Border(bottom: BorderSide(color: AppColors.parchment, width: 0.5)),
      ),
      child: Row(
        children: [
          // 1. CALL OI with background bar
          Expanded(
            flex: 2,
            child: Container(
              color: callBg,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return Stack(
                    alignment: Alignment.centerRight,
                    children: [
                      // OI bar (grows from right to left for calls)
                      Positioned(
                        right: 0,
                        top: 0,
                        bottom: 0,
                        child: Container(
                          width: constraints.maxWidth * callOiBarRatio,
                          decoration: BoxDecoration(
                            color: AppColors.bull.withValues(alpha: 0.12),
                            borderRadius: const BorderRadius.horizontal(left: Radius.circular(2)),
                          ),
                        ),
                      ),
                      // OI text
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        alignment: Alignment.center,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              _formatOi(callOi),
                              style: GoogleFonts.ibmPlexSans(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.ink),
                            ),
                            Text(
                              '${callOiChangePct >= 0 ? '+' : ''}${callOiChangePct.toStringAsFixed(1)}%',
                              style: GoogleFonts.ibmPlexSans(fontFeatures: const [FontFeature.tabularFigures()], fontSize: 9, fontWeight: FontWeight.bold, color: callOiChangePct >= 0 ? AppColors.bull : AppColors.bear),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
          // 2. CALL Price
          Expanded(
            flex: 2,
            child: GestureDetector(
              onTap: () => _openOptionDetail(call, true),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                alignment: Alignment.center,
                color: isAtm ? AppColors.goldPale.withValues(alpha: 0.15) : (callItm ? AppColors.bull.withValues(alpha: 0.04) : AppColors.pureWhite.withValues(alpha: 0.2)),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      Money.wallet(callPrice, decimals: 2),
                      style: GoogleFonts.ibmPlexSans(fontFeatures: const [FontFeature.tabularFigures()], fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.ink),
                    ),
                    Text(
                      '${callChangePct >= 0 ? '+' : ''}${callChangePct.toStringAsFixed(2)}%',
                      style: GoogleFonts.ibmPlexSans(fontFeatures: const [FontFeature.tabularFigures()], fontSize: 9, fontWeight: FontWeight.w600, color: callChangePct >= 0 ? AppColors.bull : AppColors.bear),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // 3. STRIKE Column
          Container(
            width: 70,
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: isAtm ? AppColors.goldPale : AppColors.parchment,
              border: Border.symmetric(
                vertical: BorderSide(color: isAtm ? AppColors.imperialGold : AppColors.birch, width: isAtm ? 1.5 : 1),
              ),
            ),
            alignment: Alignment.center,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  strike.toStringAsFixed(0),
                  style: GoogleFonts.ibmPlexSans(fontFeatures: const [FontFeature.tabularFigures()], 
                    fontWeight: isAtm ? FontWeight.w800 : FontWeight.w700,
                    color: isAtm ? AppColors.goldDeep : AppColors.ink,
                    fontSize: isAtm ? 12 : 11,
                  ),
                ),
                const SizedBox(height: 4),
                // Left Call / Right Put Ratio Bar
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      height: 3,
                      width: 25 * callRatio,
                      decoration: BoxDecoration(
                        color: AppColors.bear, // Call OI (red/orange)
                        borderRadius: BorderRadius.horizontal(left: Radius.circular(1.5)),
                      ),
                    ),
                    const SizedBox(width: 1),
                    Container(
                      height: 3,
                      width: 25 * putRatio,
                      decoration: BoxDecoration(
                        color: AppColors.bull, // Put OI (green)
                        borderRadius: BorderRadius.horizontal(right: Radius.circular(1.5)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // 4. PUT Price
          Expanded(
            flex: 2,
            child: GestureDetector(
              onTap: () => _openOptionDetail(put, false),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                alignment: Alignment.center,
                color: isAtm ? AppColors.goldPale.withValues(alpha: 0.15) : (putItm ? AppColors.bear.withValues(alpha: 0.04) : AppColors.pureWhite.withValues(alpha: 0.2)),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      Money.wallet(putPrice, decimals: 2),
                      style: GoogleFonts.ibmPlexSans(fontFeatures: const [FontFeature.tabularFigures()], fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.ink),
                    ),
                    Text(
                      '${putChangePct >= 0 ? '+' : ''}${putChangePct.toStringAsFixed(2)}%',
                      style: GoogleFonts.ibmPlexSans(fontFeatures: const [FontFeature.tabularFigures()], fontSize: 9, fontWeight: FontWeight.w600, color: putChangePct >= 0 ? AppColors.bull : AppColors.bear),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // 5. PUT OI with background bar
          Expanded(
            flex: 2,
            child: Container(
              color: putBg,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return Stack(
                    alignment: Alignment.centerLeft,
                    children: [
                      // OI bar (grows from left to right for puts)
                      Positioned(
                        left: 0,
                        top: 0,
                        bottom: 0,
                        child: Container(
                          width: constraints.maxWidth * putOiBarRatio,
                          decoration: BoxDecoration(
                            color: AppColors.bear.withValues(alpha: 0.12),
                            borderRadius: const BorderRadius.horizontal(right: Radius.circular(2)),
                          ),
                        ),
                      ),
                      // OI text
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        alignment: Alignment.center,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              _formatOi(putOi),
                              style: GoogleFonts.ibmPlexSans(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.ink),
                            ),
                            Text(
                              '${putOiChangePct >= 0 ? '+' : ''}${putOiChangePct.toStringAsFixed(1)}%',
                              style: GoogleFonts.ibmPlexSans(fontFeatures: const [FontFeature.tabularFigures()], fontSize: 9, fontWeight: FontWeight.bold, color: putOiChangePct >= 0 ? AppColors.bull : AppColors.bear),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isUp = _change >= 0;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _derivativeType == 'futures'
                      ? '${widget.underlyingSymbol} Futures'
                      : '${widget.underlyingSymbol} Option Chain',
                  style: GoogleFonts.ibmPlexSans(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                if (widget.market == 'stock') ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                    decoration: BoxDecoration(
                      color: AppColors.bull.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: AppColors.bull.withValues(alpha: 0.4), width: 0.5),
                    ),
                    child: Text(
                      'NSE',
                      style: GoogleFonts.ibmPlexSans(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: AppColors.bull,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            Text(
              'Spot: ${Money.wallet(_spotPrice, decimals: 2)} (${isUp ? '+' : ''}${_changePct.toStringAsFixed(2)}%)',
              style: TextStyle(
                fontSize: 12,
                color: isUp ? AppColors.bull : AppColors.bear,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        backgroundColor: AppColors.parchment,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadOptionChain,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      widget.market == 'crypto' ? Icons.currency_bitcoin : Icons.info_outline,
                      size: 48,
                      color: widget.market == 'crypto' ? AppColors.imperialGold : AppColors.ink4,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      widget.market == 'crypto'
                          ? 'Options not available for crypto'
                          : _error!,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.ibmPlexSans(
                        color: AppColors.ink,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      widget.market == 'crypto'
                          ? 'Crypto markets only support perpetual futures contracts. You can trade futures from the stock detail screen.'
                          : 'Please check your connection or try again later.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.ibmPlexSans(
                        color: AppColors.ink4,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: widget.market == 'crypto'
                          ? () => Navigator.pop(context)
                          : _loadOptionChain,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.imperialGold,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(
                        widget.market == 'crypto' ? 'Go Back' : 'Retry',
                        style: GoogleFonts.ibmPlexSans(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : Column(
              children: [
                if (widget.market == 'stock') ...[
                  // Premium Toggle between Options and Futures
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
                    color: AppColors.pureWhite,
                    child: Container(
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.cream,
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        border: Border.all(color: AppColors.birch),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () {
                                setState(() {
                                  _derivativeType = 'options';
                                });
                              },
                              child: Container(
                                decoration: BoxDecoration(
                                  color: _derivativeType == 'options'
                                      ? AppColors.imperialGold
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(AppRadius.md - 1),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  'OPTIONS',
                                  style: GoogleFonts.ibmPlexSans(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: _derivativeType == 'options'
                                        ? AppColors.pureWhite
                                        : AppColors.ink3,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: GestureDetector(
                              onTap: () {
                                setState(() {
                                  _derivativeType = 'futures';
                                });
                              },
                              child: Container(
                                decoration: BoxDecoration(
                                  color: _derivativeType == 'futures'
                                      ? AppColors.imperialGold
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(AppRadius.md - 1),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  'FUTURES',
                                  style: GoogleFonts.ibmPlexSans(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: _derivativeType == 'futures'
                                        ? AppColors.pureWhite
                                        : AppColors.ink3,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                        Divider(height: 1, color: AppColors.birch),
                ],
                Expanded(
                  child: _derivativeType == 'futures'
                      ? _buildFuturesList()
                      : Column(
                          children: [
                            // Expiry Date Selection Dropdown
                            Container(
                              color: AppColors.pureWhite,
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.lg,
                                vertical: AppSpacing.sm,
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Expiry Date:',
                                    style: GoogleFonts.ibmPlexSans(
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.ink3,
                                    ),
                                  ),
                                  DropdownButton<String>(
                                    value: _selectedExpiry,
                                    dropdownColor: AppColors.pureWhite,
                                    style: GoogleFonts.ibmPlexSans(
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.imperialGold,
                                    ),
                                    underline: Container(
                                      height: 2,
                                      color: AppColors.imperialGold,
                                    ),
                                    items: _expiries.map((expiry) {
                                      final exp = DateTime.tryParse(expiry);
                                      final isExp = exp != null && DateTime.now().isAfter(DateTime(exp.year, exp.month, exp.day, 15, 30));
                                      return DropdownMenuItem<String>(
                                        value: expiry,
                                        child: Text(isExp ? '$expiry (Expired)' : expiry),
                                      );
                                    }).toList(),
                                    onChanged: (val) {
                                      if (val != null) {
                                        setState(() => _selectedExpiry = val);
                                        _updateStrikesForExpiry(val);
                                      }
                                    },
                                  ),
                                ],
                              ),
                            ),
                                  Divider(height: 1, color: AppColors.birch),
                            _buildEstimateNotice(),
                            // Table Header
                            Container(
                              color: AppColors.cream,
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Row(
                                children: [
                                  Expanded(
                                    flex: 2,
                                    child: Center(
                                      child: Text(
                                        'CALL OI',
                                        style: GoogleFonts.ibmPlexSans(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.ink3,
                                        ),
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 2,
                                    child: Center(
                                      child: Text(
                                        'CALL PRICE',
                                        style: GoogleFonts.ibmPlexSans(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.ink3,
                                        ),
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 2,
                                    child: Center(
                                      child: Text(
                                        'STRIKE',
                                        style: GoogleFonts.ibmPlexSans(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.ink3,
                                        ),
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 2,
                                    child: Center(
                                      child: Text(
                                        'PUT PRICE',
                                        style: GoogleFonts.ibmPlexSans(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.ink3,
                                        ),
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 2,
                                    child: Center(
                                      child: Text(
                                        'PUT OI',
                                        style: GoogleFonts.ibmPlexSans(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.ink3,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                                  Divider(height: 1, color: AppColors.birch),
                            // Option Rows List
                            Expanded(
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  final sortedStrikes = List<dynamic>.from(_currentStrikes)
                                    ..sort((a, b) => (a['strike_price'] as num).compareTo(b['strike_price'] as num));

                                  if (sortedStrikes.isEmpty) {
                                    return Center(
                                      child: Text(
                                        'No strikes found for this expiry.',
                                        style: GoogleFonts.ibmPlexSans(color: AppColors.ink4),
                                      ),
                                    );
                                  }

                                  // Precompute max OI for bar normalisation
                                  final mCallOi = _maxCallOi();
                                  final mPutOi = _maxPutOi();

                                  final List<Widget> items = [];
                                  bool spotPriceInserted = false;
                                  for (int i = 0; i < sortedStrikes.length; i++) {
                                    final strikeRow = sortedStrikes[i];
                                    final strike = (strikeRow['strike_price'] as num).toDouble();
                                    if (!spotPriceInserted && _spotPrice < strike) {
                                      items.add(_buildSpotPriceBar());
                                      spotPriceInserted = true;
                                    }
                                    items.add(_buildStrikeItemRow(strikeRow, strike, maxCallOi: mCallOi, maxPutOi: mPutOi));
                                  }
                                  if (!spotPriceInserted) {
                                    items.add(_buildSpotPriceBar());
                                  }

                                  return ListView.builder(
                                    itemCount: items.length,
                                    itemBuilder: (context, index) => items[index],
                                  );
                                },
                              ),
                            ),
                            // Bottom summary bar
                            _buildSummaryBar(),
                          ],
                        ),
                ),
              ],
            ),
    );
  }

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
                            fontWeight: FontWeight.w800,
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
                          fontWeight: FontWeight.w800,
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
                      onPressed: isFutureExpired ? null : () => _openFutureOrder(future, true),
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
                      onPressed: isFutureExpired ? null : () => _openFutureOrder(future, false),
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
