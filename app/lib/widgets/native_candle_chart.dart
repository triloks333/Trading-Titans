import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/theme.dart';
import '../models/candle.dart';
import '../services/market_service.dart';
import 'candle_chart.dart';

/// A candlestick chart drawn inside the app from our own market data.
///
/// Used on the web, where the TradingView WebView cannot run: webview_flutter
/// has no web implementation, and TradingView sends `X-Frame-Options` so it
/// cannot be embedded in an iframe either. Handing the user a link to another
/// site is not a chart — it drops them out of the app entirely.
///
/// Nothing here is new machinery. [CandleChart] (interactive_chart) already
/// existed in this repo unused, the `market-history` function already returns
/// `{t,o,h,l,c}`, and [CandleData.fromJson] already parses exactly that shape.
/// The pieces had simply never been connected to each other.
class NativeCandleChart extends StatefulWidget {
  /// Raw app symbol, as passed to the WebView chart.
  final String symbol;

  /// 'stock' | 'us_stock' | 'crypto'.
  final String market;

  /// Exchange-qualified symbol for the caption, e.g. `NSE:RELIANCE`.
  final String resolvedLabel;

  const NativeCandleChart({
    super.key,
    required this.symbol,
    required this.market,
    required this.resolvedLabel,
  });

  @override
  State<NativeCandleChart> createState() => _NativeCandleChartState();
}

class _NativeCandleChartState extends State<NativeCandleChart> {
  /// Daily to start: it is the one interval every market and every symbol has
  /// history for, so the first paint is never an empty chart.
  String _interval = '1d';

  List<CandleData> _candles = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant NativeCandleChart old) {
    super.didUpdateWidget(old);
    if (old.symbol != widget.symbol || old.market != widget.market) _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    // Via the edge function, not the provider directly: a browser cannot set the
    // User-Agent the direct path sends, and the provider sends no CORS headers.
    final candles = await MarketService.getCandlesViaFunction(
      widget.symbol,
      widget.market,
      _interval,
    );
    if (!mounted) return;
    setState(() {
      _candles = candles;
      _loading = false;
    });
  }

  void _onInterval(String next) {
    if (next == _interval) return;
    setState(() => _interval = next);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.pureWhite,
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.sm, AppSpacing.sm, AppSpacing.sm, AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                widget.resolvedLabel,
                style: GoogleFonts.ibmPlexSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink4,
                ),
              ),
              const Spacer(),
              if (_loading)
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.6,
                    color: AppColors.ink4,
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Expanded(
            child: SingleChildScrollView(
              child: CandleChart(
                candles: _candles,
                selectedInterval: _interval,
                onIntervalChanged: _onInterval,
                isPositive: _candles.isEmpty
                    ? true
                    : _candles.last.close >= _candles.first.close,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
