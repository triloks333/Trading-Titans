import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../models/quote.dart';
import '../../models/portfolio.dart';
import '../../services/market_service.dart';
import '../../services/supabase_service.dart';
import 'fullscreen_chart_screen.dart';
import 'package:google_fonts/google_fonts.dart';
import 'order_entry_screen.dart';
import '../../widgets/tradingview_chart.dart';

class OptionDetailScreen extends StatefulWidget {
  final Map<String, dynamic> optionData; // The CE or PE option object from option chain response
  final String underlyingSymbol;
  final double underlyingSpotPrice;
  final String market;

  const OptionDetailScreen({
    super.key,
    required this.optionData,
    required this.underlyingSymbol,
    required this.underlyingSpotPrice,
    this.market = 'stock',
  });

  @override
  State<OptionDetailScreen> createState() => _OptionDetailScreenState();
}

class _OptionDetailScreenState extends State<OptionDetailScreen> {
  Quote? _quote;
  Holding? _holding;
  Timer? _pollTimer;
  Timer? _expiryTimer;
  bool _loading = true;

  // Expiry countdown state
  String _expiryCountdownText = '';
  Color _expiryCountdownColor = AppColors.ink4;

  @override
  void initState() {
    super.initState();
    _initQuote();
    _loadUserData();
    _updateExpiryCountdown();
    // Poll updates if desired
    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) => _refreshData());
    // Update expiry countdown every minute
    _expiryTimer = Timer.periodic(const Duration(minutes: 1), (_) => _updateExpiryCountdown());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _expiryTimer?.cancel();
    super.dispose();
  }

  void _initQuote() {
    final opt = widget.optionData;
    final optSymbol = opt['symbol'] as String? ?? widget.underlyingSymbol;
    final optPrice = (opt['price'] as num?)?.toDouble()
        ?? (opt['ltp'] as num?)?.toDouble()
        ?? widget.underlyingSpotPrice;
    final optPrevClose = (opt['previous_close'] as num?)?.toDouble() ?? optPrice;
    final optChange = (opt['change'] as num?)?.toDouble() ?? 0.0;
    final optChangePct = (opt['change_pct'] as num?)?.toDouble() ?? 0.0;

    _quote = Quote(
      symbol: optSymbol,
      yfSymbol: optSymbol,
      name: opt['name'] as String? ?? optSymbol,
      price: optPrice,
      previousClose: optPrevClose,
      change: optChange,
      changePct: optChangePct,
      currency: 'INR',
      market: widget.market,
    );
    _loading = false;
  }

  Future<void> _refreshData() async {
    try {
      final data = await MarketService.getOptionChain(widget.underlyingSymbol, market: widget.market);
      if (data != null && mounted) {
        final chains = data['chains'] as List<dynamic>? ?? [];
        for (var expiryChain in chains) {
          final strikes = expiryChain['strikes'] as List<dynamic>? ?? [];
          for (var strikeRow in strikes) {
            final call = strikeRow['call'] as Map<String, dynamic>?;
            final put = strikeRow['put'] as Map<String, dynamic>?;
            
            if (call != null && call['symbol'] == widget.optionData['symbol']) {
              _updateQuoteFromMap(call);
              break;
            }
            if (put != null && put['symbol'] == widget.optionData['symbol']) {
              _updateQuoteFromMap(put);
              break;
            }
          }
        }
      }
    } catch (_) {}
    await _loadUserData();
  }

  void _updateQuoteFromMap(Map<String, dynamic> opt) {
    if (!mounted) return;
    final price = (opt['price'] as num?)?.toDouble() ?? (opt['ltp'] as num?)?.toDouble() ?? 0.0;
    setState(() {
      _quote = Quote(
        symbol: opt['symbol'] as String? ?? '',
        yfSymbol: opt['symbol'] as String? ?? '',
        name: opt['name'] as String? ?? opt['symbol'] as String? ?? '',
        price: price,
        previousClose: (opt['previous_close'] as num?)?.toDouble() ?? price,
        change: (opt['change'] as num?)?.toDouble() ?? 0.0,
        changePct: (opt['change_pct'] as num?)?.toDouble() ?? 0.0,
        currency: 'INR',
        market: widget.market,
      );
    });
  }

  Future<void> _loadUserData() async {
    try {
      final holdings = await SupabaseService().getHoldings();
      final holding = holdings.where((h) => h.symbol == widget.optionData['symbol'] && h.market == widget.market).firstOrNull;
      if (mounted) {
        setState(() {
          _holding = holding;
        });
      }
    } catch (_) {}
  }

  bool get _isUp => (_quote?.change ?? 0) >= 0;
  Color get _changeColor => _isUp ? AppColors.bull : AppColors.bear;

  // --- Expiry Countdown ---
  void _updateExpiryCountdown() {
    final expiryStr = widget.optionData['expiry_date'] as String?;
    if (expiryStr == null) {
      _expiryCountdownText = '';
      return;
    }
    final expiry = DateTime.tryParse(expiryStr);
    if (expiry == null) {
      _expiryCountdownText = '';
      return;
    }

    final now = DateTime.now();
    // Set expiry to end of day (15:30 IST market close)
    final expiryEod = DateTime(expiry.year, expiry.month, expiry.day, 15, 30);
    final diff = expiryEod.difference(now);

    if (mounted) {
      setState(() {
        if (diff.isNegative) {
          _expiryCountdownText = 'Expired';
          _expiryCountdownColor = AppColors.bear;
        } else if (diff.inDays == 0 && diff.inHours < 24) {
          if (diff.inHours > 0) {
            _expiryCountdownText = 'Expires Today (${diff.inHours}h ${diff.inMinutes % 60}m)';
          } else {
            _expiryCountdownText = 'Expires Today (${diff.inMinutes}m)';
          }
          _expiryCountdownColor = const Color(0xFFE65100); // deep orange
        } else if (diff.inHours < 24) {
          _expiryCountdownText = 'Expires in ${diff.inHours}h ${diff.inMinutes % 60}m';
          _expiryCountdownColor = const Color(0xFFE65100);
        } else {
          _expiryCountdownText = 'Expires in ${diff.inDays}d ${diff.inHours % 24}h';
          _expiryCountdownColor = AppColors.ink4;
        }
      });
    }
  }

  // --- Moneyness Calculation ---
  String _getMoneyness(double spot, double strike, String optionType) {
    final diff = (spot - strike).abs();
    final threshold = spot * 0.01; // 1% of spot

    if (diff < threshold) return 'ATM';
    if (optionType == 'CE') {
      return spot > strike ? 'ITM' : 'OTM';
    } else {
      return spot < strike ? 'ITM' : 'OTM';
    }
  }

  Color _getMoneynessColor(String moneyness) {
    switch (moneyness) {
      case 'ITM':
        return AppColors.bull;
      case 'ATM':
        return const Color(0xFFD4A017); // gold
      case 'OTM':
        return AppColors.bear;
      default:
        return AppColors.ink4;
    }
  }

  Color _getMoneynessBgColor(String moneyness) {
    switch (moneyness) {
      case 'ITM':
        return AppColors.bullLight;
      case 'ATM':
        return const Color(0xFFFFF8E1); // light gold
      case 'OTM':
        return AppColors.bearLight;
      default:
        return AppColors.cream;
    }
  }

  double _calcIntrinsicValue(double spot, double strike, String optionType) {
    if (optionType == 'CE') {
      return math.max(0, spot - strike);
    } else {
      return math.max(0, strike - spot);
    }
  }

  // --- Black-Scholes Greeks Estimation ---
  Map<String, double> _estimateGreeks() {
    final opt = widget.optionData;

    // Try to get from API data first
    final apiDelta = (opt['delta'] as num?)?.toDouble();
    final apiGamma = (opt['gamma'] as num?)?.toDouble();
    final apiTheta = (opt['theta'] as num?)?.toDouble();
    final apiVega = (opt['vega'] as num?)?.toDouble();
    final apiIV = (opt['iv'] as num?)?.toDouble();

    // If all Greeks are available from API, use them
    if (apiDelta != null && apiGamma != null && apiTheta != null && apiVega != null && apiIV != null) {
      return {
        'delta': apiDelta,
        'gamma': apiGamma,
        'theta': apiTheta,
        'vega': apiVega,
        'iv': apiIV,
      };
    }

    // Otherwise, estimate using Black-Scholes
    final spot = widget.underlyingSpotPrice;
    final strike = (opt['strike_price'] as num?)?.toDouble() ?? 0.0;
    final optionType = opt['option_type'] as String? ?? 'CE';
    final expiryStr = opt['expiry_date'] as String?;
    final premium = (_quote?.price ?? (opt['price'] as num?)?.toDouble() ?? (opt['ltp'] as num?)?.toDouble() ?? 0.0);

    // Time to expiry in years
    double T = 30 / 365.0; // default 30 days
    if (expiryStr != null) {
      final expiry = DateTime.tryParse(expiryStr);
      if (expiry != null) {
        final now = DateTime.now();
        final daysToExpiry = expiry.difference(now).inDays;
        T = math.max(daysToExpiry, 1) / 365.0;
      }
    }

    const double r = 0.065; // Risk-free rate ~6.5% (Indian 10Y bond)

    // Estimate IV from premium using Newton-Raphson (simplified)
    double sigma = apiIV != null ? apiIV / 100.0 : _estimateIV(spot, strike, T, r, premium, optionType == 'CE');
    sigma = sigma.clamp(0.05, 3.0);

    // Black-Scholes calculations
    final sqrtT = math.sqrt(T);
    final d1 = (math.log(spot / strike) + (r + 0.5 * sigma * sigma) * T) / (sigma * sqrtT);
    final d2 = d1 - sigma * sqrtT;

    final nd1 = _normalCDF(d1);
    final nd2 = _normalCDF(d2);
    final npd1 = _normalPDF(d1);

    double delta;
    double theta;

    if (optionType == 'CE') {
      delta = apiDelta ?? nd1;
      theta = apiTheta ?? (-(spot * npd1 * sigma) / (2 * sqrtT) - r * strike * math.exp(-r * T) * nd2) / 365.0;
    } else {
      delta = apiDelta ?? (nd1 - 1);
      theta = apiTheta ?? (-(spot * npd1 * sigma) / (2 * sqrtT) + r * strike * math.exp(-r * T) * _normalCDF(-d2)) / 365.0;
    }

    final gamma = apiGamma ?? (npd1 / (spot * sigma * sqrtT));
    final vega = apiVega ?? (spot * npd1 * sqrtT / 100.0);
    final iv = apiIV ?? (sigma * 100);

    return {
      'delta': delta,
      'gamma': gamma,
      'theta': theta,
      'vega': vega,
      'iv': iv,
    };
  }

  double _estimateIV(double S, double K, double T, double r, double marketPrice, bool isCall) {
    // Newton-Raphson method to find implied volatility
    double sigma = 0.3; // initial guess
    for (int i = 0; i < 50; i++) {
      final sqrtT = math.sqrt(T);
      final d1 = (math.log(S / K) + (r + 0.5 * sigma * sigma) * T) / (sigma * sqrtT);
      final d2 = d1 - sigma * sqrtT;

      double bsPrice;
      if (isCall) {
        bsPrice = S * _normalCDF(d1) - K * math.exp(-r * T) * _normalCDF(d2);
      } else {
        bsPrice = K * math.exp(-r * T) * _normalCDF(-d2) - S * _normalCDF(-d1);
      }

      final vega = S * _normalPDF(d1) * sqrtT;
      if (vega.abs() < 1e-10) break;

      final diff = bsPrice - marketPrice;
      sigma = sigma - diff / vega;
      if (diff.abs() < 0.01) break;
      sigma = sigma.clamp(0.01, 5.0);
    }
    return sigma;
  }

  double _normalCDF(double x) {
    return 0.5 * (1.0 + _erf(x / math.sqrt(2)));
  }

  double _normalPDF(double x) {
    return math.exp(-0.5 * x * x) / math.sqrt(2 * math.pi);
  }

  double _erf(double x) {
    // Abramowitz and Stegun approximation
    final a1 = 0.254829592;
    final a2 = -0.284496736;
    final a3 = 1.421413741;
    final a4 = -1.453152027;
    final a5 = 1.061405429;
    final p = 0.3275911;

    final sign = x < 0 ? -1.0 : 1.0;
    final absX = x.abs();
    final t = 1.0 / (1.0 + p * absX);
    final y = 1.0 - (((((a5 * t + a4) * t) + a3) * t + a2) * t + a1) * t * math.exp(-absX * absX);
    return sign * y;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _quote == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final q = _quote!;
    final opt = widget.optionData;
    final strikePrice = (opt['strike_price'] as num?)?.toDouble() ?? 0.0;
    final optionType = opt['option_type'] as String? ?? 'CE';
    final expiryDate = opt['expiry_date'] as String? ?? '';
    final openInterest = opt['open_interest'] ?? 0;
    final volume = opt['volume'] ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: Text(q.symbol),
        backgroundColor: AppColors.parchment,
      ),
      body: SafeArea(
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
                    if (_expiryCountdownText.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.sm),
                      _buildExpiryCountdown(),
                    ],
                    const SizedBox(height: AppSpacing.lg),
                    _buildChartCard(q),
                    const SizedBox(height: AppSpacing.lg),
                    _buildViewChartButton(q),
                    const SizedBox(height: AppSpacing.lg),
                    _buildStatsCard(strikePrice, optionType, expiryDate, openInterest, volume),
                    const SizedBox(height: AppSpacing.lg),
                    _buildGreeksCard(),
                    if (_holding != null) ...[
                      const SizedBox(height: AppSpacing.lg),
                      _buildPositionCard(strikePrice, optionType, expiryDate),
                    ],
                    const SizedBox(height: AppSpacing.lg),
                  ],
                ),
              ),
            ),
            _buildBottomBar(strikePrice, optionType, expiryDate),
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
          Text(q.name, style:       TextStyle(color: AppColors.ink4, fontSize: 13)),
          const SizedBox(height: AppSpacing.sm),
          Text('₹${q.price.toStringAsFixed(2)}',
              style:       TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: AppColors.ink)),
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
            Text('UNDERLYING: ${widget.underlyingSymbol} (₹${widget.underlyingSpotPrice.toStringAsFixed(2)})', style:       TextStyle(color: AppColors.ink4, fontSize: 11)),
          ]),
        ],
      ),
    );
  }

  // --- Expiry Countdown Widget ---
  Widget _buildExpiryCountdown() {
    final isUrgent = _expiryCountdownColor != AppColors.ink4;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
      decoration: BoxDecoration(
        color: isUrgent
            ? _expiryCountdownColor.withValues(alpha: 0.08)
            : AppColors.cream,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: isUrgent
              ? _expiryCountdownColor.withValues(alpha: 0.3)
              : AppColors.birch,
        ),
      ),
      child: Row(
        children: [
          Icon(
            _expiryCountdownText == 'Expired'
                ? Icons.error_outline_rounded
                : Icons.timer_outlined,
            color: _expiryCountdownColor,
            size: 18,
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            _expiryCountdownText,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: _expiryCountdownColor,
            ),
          ),
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
              symbol: q.symbol,
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
                          symbol: q.symbol,
                          market: widget.market,
                          name: q.name,
                          quote: q,
                        ),
                      ),
                    );
                    _refreshData();
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildViewChartButton(Quote q) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        icon:       Icon(Icons.bar_chart_rounded, color: AppColors.pureWhite),
        label: Text('VIEW CHART', style: GoogleFonts.inter(fontWeight: FontWeight.bold, letterSpacing: 0.5)),
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => FullscreenChartScreen(
                symbol: q.symbol,
                market: widget.market,
                name: q.name,
                quote: q,
              ),
            ),
          );
          _refreshData();
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

  Widget _buildStatsCard(double strike, String optionType, String expiry, dynamic openInterest, dynamic volume) {
    final spot = widget.underlyingSpotPrice;
    final moneyness = _getMoneyness(spot, strike, optionType);
    final moneynessColor = _getMoneynessColor(moneyness);
    final moneynessBg = _getMoneynessBgColor(moneyness);
    final intrinsic = _calcIntrinsicValue(spot, strike, optionType);
    final premium = _quote?.price ?? 0.0;
    final timeValue = math.max(0, premium - intrinsic);

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
          Row(
            children: [
                    Expanded(
                child: Text('Contract Details',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.ink)),
              ),
              // Moneyness Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: moneynessBg,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  border: Border.all(color: moneynessColor.withValues(alpha: 0.3)),
                ),
                child: Text(
                  moneyness,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: moneynessColor,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _statRow('Strike Price', '₹${strike.toStringAsFixed(0)}'),
          _divider(),
          _statRow('Option Type', optionType == 'CE' ? 'Call Option (CE)' : 'Put Option (PE)'),
          _divider(),
          _statRow('Expiry Date', expiry),
          _divider(),
          _statRow('Open Interest', openInterest.toString()),
          _divider(),
          _statRow('Volume', volume.toString()),
          _divider(),
          // Intrinsic & Time Value breakdown
          _statRow('Intrinsic Value', '₹${intrinsic.toStringAsFixed(2)}',
              valueColor: intrinsic > 0 ? AppColors.bull : AppColors.ink4),
          _divider(),
          _statRow('Time Value', '₹${timeValue.toStringAsFixed(2)}',
              valueColor: AppColors.ink3),
        ],
      ),
    );
  }

  // --- Greeks Card ---
  Widget _buildGreeksCard() {
    final greeks = _estimateGreeks();
    final hasApiGreeks = widget.optionData['delta'] != null;

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
          Row(
            children: [
                    Expanded(
                child: Text('Option Greeks',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.ink)),
              ),
              if (!hasApiGreeks)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.blueLight,
                    borderRadius: BorderRadius.circular(AppRadius.tag),
                  ),
                  child: Text(
                    'ESTIMATED',
                    style: GoogleFonts.inter(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: AppColors.blue,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          // 2-column grid layout for Greeks
          Row(
            children: [
              Expanded(child: _greekTile('Delta', greeks['delta']!, 4, _getDeltaColor(greeks['delta']!))),
              const SizedBox(width: AppSpacing.md),
              Expanded(child: _greekTile('Gamma', greeks['gamma']!, 6, AppColors.violet)),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(child: _greekTile('Theta', greeks['theta']!, 4, AppColors.bear)),
              const SizedBox(width: AppSpacing.md),
              Expanded(child: _greekTile('Vega', greeks['vega']!, 4, AppColors.blue)),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(child: _greekTile('IV', greeks['iv']!, 2, const Color(0xFFD4A017), suffix: '%')),
              const Expanded(child: SizedBox()), // keep grid balanced
            ],
          ),
        ],
      ),
    );
  }

  Color _getDeltaColor(double delta) {
    if (delta > 0) return AppColors.bull;
    if (delta < 0) return AppColors.bear;
    return AppColors.ink4;
  }

  Widget _greekTile(String label, double value, int decimals, Color accentColor, {String suffix = ''}) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: accentColor.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.ink4,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${value.toStringAsFixed(decimals)}$suffix',
            style: GoogleFonts.inter(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: accentColor,
            ),
          ),
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
          Text(label, style:       TextStyle(color: AppColors.ink4, fontSize: 13)),
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

  Widget _buildPositionCard(double strike, String optionType, String expiry) {
    final isShort = _holding!.quantity < 0;
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
          Row(
            children: [
                    Expanded(
                child: Text('Your Position',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.ink)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isShort ? AppColors.bearLight : AppColors.bullLight,
                  borderRadius: BorderRadius.circular(AppRadius.tag),
                ),
                child: Text(
                  _holding!.positionTag,
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: isShort ? AppColors.bear : AppColors.bull,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text('Quantity: ${_holding!.quantity.toStringAsFixed(4)} (${isShort ? 'SHORT' : 'LONG'})',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isShort ? AppColors.bear : AppColors.bull,
              )),
          const SizedBox(height: AppSpacing.xs),
          Text('Avg price: ₹${_holding!.avgPrice.toStringAsFixed(2)}',
              style:       TextStyle(color: AppColors.ink4)),
          // P&L display
          if (_quote != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Builder(builder: (_) {
              final currentVal = _holding!.quantity.abs() * _quote!.price;
              final investedVal = _holding!.quantity.abs() * _holding!.avgPrice;
              final positionPnl = isShort
                  ? investedVal - currentVal
                  : currentVal - investedVal;
              final pnlPct = investedVal > 0 ? (positionPnl / investedVal) * 100 : 0.0;
              final pnlUp = positionPnl >= 0;
              return Text(
                'P&L: ${pnlUp ? '+' : ''}₹${positionPnl.toStringAsFixed(2)} (${pnlPct.toStringAsFixed(2)}%)',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: pnlUp ? AppColors.bull : AppColors.bear,
                ),
              );
            }),
          ],
          const SizedBox(height: AppSpacing.lg),
          // EXIT Button
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton.icon(
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => OrderEntryScreen(
                      quote: _quote!,
                      isBuy: _holding!.isShort, // buy to close if short, sell to close if long
                      instrumentType: 'OPTION',
                      strikePrice: strike,
                      optionType: optionType,
                      expiryDate: expiry,
                    ),
                  ),
                );
                _refreshData();
              },
              icon: const Icon(Icons.logout_rounded, size: 18),
              label: Text(
                'EXIT POSITION',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE65100), // deep orange for urgency
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(double strike, String optionType, String expiry) {
    return Container(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.warmWhite,
        border:       Border(top: BorderSide(color: AppColors.birch)),
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
                  onPressed: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => OrderEntryScreen(
                          quote: _quote!,
                          isBuy: true,
                          instrumentType: 'OPTION',
                          strikePrice: strike,
                          optionType: optionType,
                          expiryDate: expiry,
                        ),
                      ),
                    );
                    _refreshData();
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
                  onPressed: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => OrderEntryScreen(
                          quote: _quote!,
                          isBuy: false,
                          instrumentType: 'OPTION',
                          strikePrice: strike,
                          optionType: optionType,
                          expiryDate: expiry,
                        ),
                      ),
                    );
                    _refreshData();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.bear,
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
