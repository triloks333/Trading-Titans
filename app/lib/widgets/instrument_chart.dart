import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../core/theme.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/churn_telemetry_service.dart';

import 'native_candle_chart.dart';
import '../services/currency_service.dart';
import '../services/theme_service.dart';

/// The instrument chart: our own chart, drawn from our own prices.
///
/// WHAT THIS REPLACED
/// A WebView pointed at `tradingview.com/chart`. That meant downloading a whole
/// third-party web app on every open — no chart at all on a weak connection — and
/// when it did load it drew somebody else's feed, so the candles could disagree
/// with the price we fill orders at with nothing to explain the gap. It also
/// needed an ~80-entry hand-maintained table mapping our symbols onto TradingView
/// venues, and a spoofed user agent and injected CSS to hide the parts of their
/// site we did not want.
///
/// Now `assets/chart.html` is a single self-contained file: the charting library,
/// nineteen indicators, the saved-strategy sheet and the period selector, inlined
/// with no external request. It reads history from our `market-history` function
/// and the live bar from `quotes_cache`, which is the same table
/// `execute-pending-orders` prices fills from.
///
/// WHY SO LITTLE DART
/// Everything a user touches on the chart is rendered inside the page, from the
/// same indicator catalogue the web app reads. A Dart period selector and a Dart
/// indicator sheet would mean that catalogue existing twice, in two languages,
/// kept in step by hand — a mistake this codebase has already paid for once with
/// the price list. So this widget hosts the page, passes the symbol, and gets out
/// of the way.
class InstrumentChart extends StatefulWidget {
  /// The app's own symbol, exactly as `quotes_cache` knows it. No venue mapping
  /// needed: the page resolves indices and derivatives itself.
  final String symbol;

  /// 'stock' | 'us_stock' | 'crypto'.
  final String market;

  /// 'light' or 'dark' to pin the chart; null (the default) follows the app's
  /// light/dark setting live, so no host screen can forget to pass it.
  final String? theme;

  /// Optional live quote price pushed by the host screen to keep candle moving
  /// smoothly with every incoming tick.
  final double? livePrice;

  const InstrumentChart({
    super.key,
    required this.symbol,
    this.market = 'stock',
    this.theme,
    this.livePrice,
  });

  @override
  State<InstrumentChart> createState() => _InstrumentChartState();
}

enum _Phase { loading, ready, empty, failed }

class _InstrumentChartState extends State<InstrumentChart> {
  /// Left unset on the web, where webview_flutter has no implementation at all.
  WebViewController? _controller;

  _Phase _phase = _Phase.loading;
  String? _error;

  /// True once the page has announced itself. Commands sent before this would
  /// land on a `window.ttChart` that does not exist yet.
  bool _ready = false;

  Timer? _poll;

  final CurrencyService _currency = CurrencyService.instance;

  bool get _isDark => widget.theme == null ? AppColors.isDark : widget.theme != 'light';

  /// Pushes the current theme into the page and the WebView's pre-paint colour.
  void _applyTheme() {
    _controller?.setBackgroundColor(_surface);
    _call('window.ttChart.setTheme(${jsonEncode(_isDark ? 'dark' : 'light')})');
  }

  void _onAppThemeChanged() {
    if (widget.theme != null || !mounted) return;
    setState(() {}); // repaint the loading/notice overlays in the new surface
    _applyTheme();
  }

  /// Matches `--surface` in the chart page, so the gap before the first paint is
  /// not a different colour from the chart that replaces it.
  Color get _surface => _isDark ? AppColors.pureWhite : Colors.white;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) return;
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(_surface)
      ..addJavaScriptChannel('TitanChartHost', onMessageReceived: _onHostMessage)
      ..setNavigationDelegate(NavigationDelegate(
        // The page has no outbound links, and it should stay that way: loading
        // anyone else's site inside our chart is the thing this widget removed.
        onNavigationRequest: (request) =>
            request.url.startsWith('file:') ? NavigationDecision.navigate : NavigationDecision.prevent,
        onWebResourceError: (error) {
          // Only a failure to load the page itself. A single failed fetch inside
          // it is the page's own business — it reports those over the channel and
          // keeps drawing what it already has.
          if (error.isForMainFrame == false) return;
          debugPrint('chart: asset failed to load — ${error.description}');
          _fail("Couldn't open the chart.");
        },
      ))
      ..loadFlutterAsset('assets/chart.html');

    // The chart must read in whatever currency the rest of the app does. A header
    // showing $15.02 above a chart drawn in rupees is the same instrument quoted
    // two ways on one screen, which reads as a pricing bug rather than a display
    // setting. Listening rather than reading once: the setting lives in Settings,
    // and coming back from there changes nothing this widget's own fields would
    // notice.
    _currency.addListener(_onCurrencyChanged);
    ThemeService().addListener(_onAppThemeChanged);

    // Polls quote to keep live candle updating smoothly
    _poll = Timer.periodic(const Duration(seconds: 4), (_) {
      if (_ready) _call('window.ttChart.refreshQuote()');
    });
  }

  @override
  void didUpdateWidget(covariant InstrumentChart old) {
    super.didUpdateWidget(old);
    if (kIsWeb) return;
    if (old.theme != widget.theme) _applyTheme();
    if (old.symbol != widget.symbol || old.market != widget.market) {
      setState(() {
        _phase = _Phase.loading;
        _error = null;
      });
      // A new symbol, not a new page: the library and the indicators are already
      // parsed, so this is a fetch rather than a reload.
      _load();
    } else if (widget.livePrice != null &&
        widget.livePrice != old.livePrice &&
        widget.livePrice! > 0) {
      _call('window.ttChart.pushTick(${widget.livePrice})');
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    if (!kIsWeb) {
      _currency.removeListener(_onCurrencyChanged);
      ThemeService().removeListener(_onAppThemeChanged);
    }
    super.dispose();
  }

  /// Pushes the display currency and rate into the page.
  ///
  /// Sends both every time and lets the page decide whether anything moved: the
  /// rate refreshes on its own half-hourly timer, so a listener firing does not
  /// say which of the two changed.
  void _sendCurrency() {
    _call(
      'window.ttChart.setCurrency('
      '${jsonEncode(_currency.displayCurrency.code)}, '
      '${_currency.usdInr})',
    );
  }

  /// No spinner here on purpose. [CurrencyService] also notifies for preferred
  /// markets, residency and onboarding, none of which move a price, and the page
  /// ignores a `setCurrency` that changes nothing. Showing a spinner optimistically
  /// would leave one turning forever on those, because no reload — and so no
  /// `loaded` — ever follows. The page announces its own `loading` when it really
  /// does refetch, and that is already handled.
  void _onCurrencyChanged() => _sendCurrency();

  /// Runs an expression in the page, if it is up. Failures are swallowed: a
  /// disposed WebView rejects `runJavaScript`, and that is not worth a crash.
  void _call(String expression) {
    if (!_ready) return;
    _controller?.runJavaScript(expression).catchError((_) {});
  }

  void _load() {
    // jsonEncode, not string interpolation: this crosses into JavaScript as
    // source text, and a symbol arrives here from the database rather than from
    // a constant in this file.
    _call('window.ttChart.load(${jsonEncode(widget.symbol)}, ${jsonEncode(widget.market)})');
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _phase = _Phase.failed;
      _error = message;
    });
  }

  /// Everything the page has to say. Unknown types are ignored on purpose, so
  /// adding a message on the web side cannot break a shipped app.
  void _onHostMessage(JavaScriptMessage message) {
    Map<String, dynamic> data;
    try {
      final decoded = jsonDecode(message.message);
      if (decoded is! Map<String, dynamic>) return;
      data = decoded;
    } catch (_) {
      return;
    }

    switch (data['type']) {
      case 'tap':
        // Chart controls live in the page; record them under their catalogue ids.
        final id = data['control'] == 'timeframe'
            ? const {
                '1m': 'pro_chart_timeframe_1m_btn', '5m': 'pro_chart_timeframe_5m_btn', '15m': 'pro_chart_timeframe_15m_btn',
                '1h': 'pro_chart_timeframe_1h_btn', '1D': 'pro_chart_timeframe_1d_btn',
              }[data['id']]
            : 'pro_chart_indicator_toggle_btn';
        if (id != null) ChurnTelemetryService.instance.recordButtonTap(id, extra: {'sym': widget.symbol});
        break;
      case 'ready':
        _ready = true;
        _applyTheme();
        // Before the first load, so the very first paint is already in the right
        // currency rather than flashing rupees at someone who chose dollars.
        _sendCurrency();
        _load();
        break;
      case 'loading':
        if (mounted && _phase != _Phase.loading) {
          setState(() {
            _phase = _Phase.loading;
            _error = null;
          });
        }
        break;
      case 'loaded':
        if (!mounted) return;
        setState(() {
          _phase = data['empty'] == true ? _Phase.empty : _Phase.ready;
          _error = null;
        });
        break;
      case 'error':
        // The page's message is an HTTP status, not copy: `market-history`
        // answers `500` with an empty statusText over HTTP/2, so forwarding it
        // verbatim put "500 " on screen where a sentence belongs. Keep it in the
        // log, where it is actually useful.
        debugPrint('chart: load failed — ${data['message']}');
        _fail("Couldn't load price history for this instrument.");
        break;
      case 'warn':
        // An indicator that failed to build, or a bad payload from this file. The
        // chart is still drawing, so this is a log line rather than a failure.
        debugPrint('chart: ${data['message']} ${data['detail'] ?? ''}');
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Browsers draw the chart in Flutter instead: webview_flutter has no web
    // implementation, so constructing the controller above would throw the
    // moment someone opened a stock in a browser.
    if (kIsWeb) {
      return NativeCandleChart(
        symbol: widget.symbol,
        market: widget.market,
        resolvedLabel: widget.symbol,
      );
    }

    final controller = _controller;
    if (controller == null) return ColoredBox(color: _surface);

    return Stack(
      children: [
        WebViewWidget(
          controller: controller,
          // The chart owns pans and pinches inside its own bounds. Without this
          // the scroll view these screens sit in steals every vertical drag, so
          // the chart cannot be panned at all.
          gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
            Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer()),
          },
        ),
        if (_phase == _Phase.loading)
          ColoredBox(
            color: _surface,
            child: Center(
              child: CircularProgressIndicator(color: AppColors.imperialGold, strokeWidth: 2),
            ),
          ),
        if (_phase == _Phase.failed || _phase == _Phase.empty)
          _Notice(
            surface: _surface,
            dark: _isDark,
            message: _phase == _Phase.empty
                ? 'No price history for this instrument yet.'
                : (_error ?? "Couldn't load the chart."),
            // An empty result is an answer, not a fault: there is nothing to
            // retry until the instrument has history.
            onRetry: _phase == _Phase.failed
                ? () {
                    setState(() {
                      _phase = _Phase.loading;
                      _error = null;
                    });
                    _load();
                  }
                : null,
          ),
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  final Color surface;
  final bool dark;
  final String message;
  final VoidCallback? onRetry;

  const _Notice({
    required this.surface,
    required this.dark,
    required this.message,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final ink = dark ? Colors.white70 : Colors.black54;
    return ColoredBox(
      color: surface,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.show_chart_rounded, size: 30, color: ink),
              const SizedBox(height: 10),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: ink),
              ),
              if (onRetry != null) ...[
                const SizedBox(height: 12),
                TextButton(onPressed: onRetry, child: const Text('Try again')),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
