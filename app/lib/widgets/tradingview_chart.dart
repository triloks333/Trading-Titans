import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class TradingViewChart extends StatefulWidget {
  final String symbol;
  final String market;
  final bool isFullscreen;
  final String theme;

  const TradingViewChart({
    super.key,
    required this.symbol,
    this.market = 'stock',
    this.isFullscreen = false,
    this.theme = 'dark',
  });

  @override
  State<TradingViewChart> createState() => _TradingViewChartState();
}

class _TradingViewChartState extends State<TradingViewChart> {
  late final WebViewController _controller;
  bool _isLoading = true;

  static const _indexMap = <String, String>{
    '^NSEI': 'NSE:NIFTY',
    '^BSESN': 'BSE:SENSEX',
    '^NSEBANK': 'NSE:BANKNIFTY',
    '^CNXIT': 'NSE:CNXIT',
    '^CNXINFRA': 'NSE:NIFTYINFRA',
    'NIFTY': 'NSE:NIFTY',
    'NIFTY50': 'NSE:NIFTY',
    'BANKNIFTY': 'NSE:BANKNIFTY',
    'SENSEX': 'BSE:SENSEX',
  };

  static const _cryptoMap = <String, String>{
    'BTC': 'BINANCE:BTCUSDT',
    'ETH': 'BINANCE:ETHUSDT',
    'SOL': 'BINANCE:SOLUSDT',
    'ADA': 'BINANCE:ADAUSDT',
    'XRP': 'BINANCE:XRPUSDT',
    'DOGE': 'BINANCE:DOGEUSDT',
    'BNB': 'BINANCE:BNBUSDT',
    'MATIC': 'BINANCE:MATICUSDT',
    'DOT': 'BINANCE:DOTUSDT',
    'AVAX': 'BINANCE:AVAXUSDT',
    'SHIB': 'BINANCE:SHIBUSDT',
    'LINK': 'BINANCE:LINKUSDT',
    'LTC': 'BINANCE:LTCUSDT',
    'UNI': 'BINANCE:UNIUSDT',
    'ATOM': 'BINANCE:ATOMUSDT',
    'FIL': 'BINANCE:FILUSDT',
    'NEAR': 'BINANCE:NEARUSDT',
    'APT': 'BINANCE:APTUSDT',
    'ARB': 'BINANCE:ARBUSDT',
    'OP': 'BINANCE:OPUSDT',
    'PEPE': 'BINANCE:PEPEUSDT',
    'TRX': 'BINANCE:TRXUSDT',
    'SUI': 'BINANCE:SUIUSDT',
    'RENDER': 'BINANCE:RENDERUSDT',
    'INJ': 'BINANCE:INJUSDT',
    'FET': 'BINANCE:FETUSDT',
    'SAND': 'BINANCE:SANDUSDT',
    'MANA': 'BINANCE:MANAUSDT',
    'ALGO': 'BINANCE:ALGOUSDT',
    'HBAR': 'BINANCE:HBARUSDT',
    'VET': 'BINANCE:VETUSDT',
    'ICP': 'BINANCE:ICPUSDT',
    'EOS': 'BINANCE:EOSUSDT',
    'AAVE': 'BINANCE:AAVEUSDT',
    'MKR': 'BINANCE:MKRUSDT',
    'GRT': 'BINANCE:GRTUSDT',
    'IMX': 'BINANCE:IMXUSDT',
    'THETA': 'BINANCE:THETAUSDT',
    'RUNE': 'BINANCE:RUNEUSDT',
    'FTM': 'BINANCE:FTMUSDT',
    'CRV': 'BINANCE:CRVUSDT',
    'GALA': 'BINANCE:GALAUSDT',
    'APE': 'BINANCE:APEUSDT',
    'AXS': 'BINANCE:AXSUSDT',
    'FLOW': 'BINANCE:FLOWUSDT',
    'EGLD': 'BINANCE:EGLDUSDT',
    'KAVA': 'BINANCE:KAVAUSDT',
    'CHZ': 'BINANCE:CHZUSDT',
    'XLM': 'BINANCE:XLMUSDT',
    'ETC': 'BINANCE:ETCUSDT',
    'BCH': 'BINANCE:BCHUSDT',
    'COMP': 'BINANCE:COMPUSDT',
    'SNX': 'BINANCE:SNXUSDT',
    '1INCH': 'BINANCE:1INCHUSDT',
    'ENS': 'BINANCE:ENSUSDT',
    'LDO': 'BINANCE:LDOUSDT',
    'WLD': 'BINANCE:WLDUSDT',
    'TIA': 'BINANCE:TIAUSDT',
    'SEI': 'BINANCE:SEIUSDT',
    'JUP': 'BINANCE:JUPUSDT',
    'STX': 'BINANCE:STXUSDT',
    'BONK': 'BINANCE:BONKUSDT',
    'WIF': 'BINANCE:WIFUSDT',
    'FLOKI': 'BINANCE:FLOKIUSDT',
    'PYTH': 'BINANCE:PYTHUSDT',
    'JTO': 'BINANCE:JTOUSDT',
    'PENDLE': 'BINANCE:PENDLEUSDT',
    'W': 'BINANCE:WUSDT',
    'TON': 'OKX:TONUSDT',
    'TAO': 'BINANCE:TAOUSDT',
    'KAS': 'BYBIT:KASUSDT',
  };

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(widget.theme == 'light' ? Colors.white : const Color(0xFF131722))
      ..setUserAgent(
        'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/125.0.0.0 Mobile Safari/537.36',
      )
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) {
          final css = widget.isFullscreen ? '''
            .tv-site-header,
            .tv-header,
            .footer-chart-links,
            div[data-role="toast-container"] {
              display: none !important;
              height: 0 !important;
              overflow: hidden !important;
            }
          ''' : '''
            .header-chart-panel-header,
            .layout__area--top,
            .tv-header,
            .tv-main-panel__side-toolbar,
            .footer-chart-links,
            .layout__area--bottom,
            [class*="headerChartPanel"],
            [class*="topToolbar"],
            .tv-header__area,
            .tv-site-header,
            div[data-role="toast-container"] {
              display: none !important;
              height: 0 !important;
              overflow: hidden !important;
            }
            .chart-page { padding-top: 0 !important; }
            .layout__area--center { top: 0 !important; }
          ''';
          _controller.runJavaScript('''
            (function() {
              var style = document.createElement('style');
              style.textContent = `$css`;
              document.head.appendChild(style);
            })();
          ''');
          if (mounted) setState(() => _isLoading = false);
        },
      ));
    _loadChart();
  }

  @override
  void didUpdateWidget(covariant TradingViewChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.symbol != widget.symbol || oldWidget.theme != widget.theme || oldWidget.isFullscreen != widget.isFullscreen) {
      setState(() => _isLoading = true);
      _loadChart();
    }
  }

  String _resolveSymbol(String raw) {
    String sym = raw.trim().toUpperCase();

    // Extract underlying from option format: SYMBOL-YYYY-MM-DD-STRIKE-CE/PE
    if (sym.contains('-') && (sym.endsWith('-CE') || sym.endsWith('-PE'))) {
      sym = sym.split('-')[0];
    }

    if (sym == 'ZOMATO') {
      sym = 'ETERNAL';
    }

    // Strip Fyers equity suffixes (-EQ, -SM, -BE, -BZ) for TradingView
    // Fyers uses NSE:TATACHEM-EQ, TradingView uses NSE:TATACHEM
    final fyersSuffixPattern = RegExp(r'-(EQ|SM|BE|BZ)$');
    sym = sym.replaceAll(fyersSuffixPattern, '');

    // Normalize exchange prefixes
    final spaceMatch = RegExp(r'^(NSE|BSE)[\s\-](.+)$').firstMatch(sym);
    if (spaceMatch != null) {
      return '${spaceMatch.group(1)}:${spaceMatch.group(2)!.trim()}';
    }

    if (_indexMap.containsKey(sym)) return _indexMap[sym]!;

    final cleanCrypto = sym.replaceAll(RegExp(r'[-/]?(INR|USDT)$'), '');
    if (_cryptoMap.containsKey(cleanCrypto)) return _cryptoMap[cleanCrypto]!;

    if (sym.contains(':')) return sym;

    if (sym.endsWith('.NS')) return 'NSE:${sym.replaceAll('.NS', '')}';
    if (sym.endsWith('.BO')) return 'BSE:${sym.replaceAll('.BO', '')}';

    if (widget.market == 'crypto') {
      return 'BINANCE:${sym}USDT';
    }
    return 'NSE:$sym';
  }

  /// Loads the FULL TradingView website (not embed widget).
  /// The full site has complete data access for ALL exchanges including NSE/BSE.
  /// The embed widgets have licensing restrictions that block Indian exchange data,
  /// but the main website does not have these restrictions.
  void _loadChart() {
    final symbol = _resolveSymbol(widget.symbol);

    // Use the full TradingView chart page — NOT the embed widget
    // This has FULL data access for all symbols worldwide including NSE/BSE
    final uri = Uri.parse(
      'https://www.tradingview.com/chart/?symbol=${Uri.encodeComponent(symbol)}&interval=D&theme=${widget.theme}',
    );

    _controller.loadRequest(uri);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        WebViewWidget(
          controller: _controller,
          gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
            Factory<OneSequenceGestureRecognizer>(
              () => EagerGestureRecognizer(),
            ),
          },
        ),
        // Loading overlay
        if (_isLoading)
          Container(
            color: widget.theme == 'light' ? Colors.white : const Color(0xFF131722),
            child: const Center(
              child: CircularProgressIndicator(
                color: Color(0xFF2962FF),
                strokeWidth: 2,
              ),
            ),
          ),
      ],
    );
  }
}
