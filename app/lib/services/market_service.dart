import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/supabase_config.dart';
import '../models/quote.dart';
import '../models/candle.dart';

class MarketService {
  static final String _functionsBase =
      '${supabaseUrl.endsWith('/') ? supabaseUrl.substring(0, supabaseUrl.length - 1) : supabaseUrl}/functions/v1';
  static const Duration _timeout = Duration(seconds: 20);

  static Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer $supabaseAnonKey',
    'apikey': supabaseAnonKey,
  };

  static Future<List<Quote>> getMarketOverview() async {
    try {
      final response = await http
          .get(Uri.parse('$_functionsBase/market-overview'), headers: _headers)
          .timeout(_timeout);
      if (response.statusCode == 200) {
        final List data = jsonDecode(response.body);
        return data.map((e) => Quote.fromJson(e)).toList();
      }
    } catch (_) {}
    return [];
  }

  static final Map<String, Map<String, dynamic>> _quoteCache = {};

  static String normalizeSymbol(String sym, String market) {
    var s = sym.toUpperCase().trim();
    if (market == 'stock') {
      if (s.startsWith('NSE:') || s.startsWith('BSE:')) {
        s = s.substring(4);
      }
      s = s.replaceAll(RegExp(r'-(EQ|SM|BE|BZ)$'), '');
      
      // Do not split by space/hyphen if it's an F&O instrument
      final isFO = s.contains('FUT') || s.contains('CE') || s.contains('PE') || s.contains(RegExp(r'\d{2}[A-Z]{3}'));
      if (!s.startsWith('^') && !isFO) {
        if (s.contains('-')) {
          s = s.split('-')[0];
        } else if (s.contains(' ')) {
          s = s.split(' ')[0];
        }
      }
    }
    return s;
  }

  static Future<Quote?> quote(String symbol, String market, {bool forceRefresh = false}) async {
    final normSym = normalizeSymbol(symbol, market);
    final cacheKey = '$normSym\x1F$market';
    final now = DateTime.now();
    if (!forceRefresh && _quoteCache.containsKey(cacheKey)) {
      final cached = _quoteCache[cacheKey]!;
      final timestamp = cached['timestamp'] as DateTime;
      if (now.difference(timestamp) < const Duration(seconds: 3)) {
        return cached['quote'] as Quote?;
      }
    }

    // Server-side price cache: read the centrally-refreshed quote when it is
    // fresh. This collapses thousands of per-client upstream calls into one
    // server job and gives every user the SAME price. On a miss/stale entry we
    // fall through to the live fetch below, so behaviour is unchanged when the
    // cache is empty (e.g. browsing a symbol nobody holds).
    if (!forceRefresh) {
      final cachedQuote = await _readServerCache(symbol, market);
      if (cachedQuote != null) {
        _quoteCache[cacheKey] = {'timestamp': now, 'quote': cachedQuote};
        return cachedQuote;
      }
    }

    try {
      final response = await http
          .get(
            Uri.parse(
              '$_functionsBase/market-quote?symbol=${Uri.encodeQueryComponent(normSym)}&market=${Uri.encodeQueryComponent(market)}',
            ),
            headers: _headers,
          )
          .timeout(_timeout);
      if (response.statusCode == 200) {
        final quoteVal = Quote.fromJson(jsonDecode(response.body));
        _quoteCache[cacheKey] = {
          'timestamp': now,
          'quote': quoteVal,
        };
        return quoteVal;
      }
    } catch (_) {}
    return null;
  }

  /// Canonical key used to look a symbol up in the server `quotes_cache`,
  /// matching exactly how the `refresh-quotes` job stores rows (underlying
  /// symbol for derivatives, index aliases mapped to canonical names, crypto
  /// upper-cased).
  static String cacheKeyFor(String sym, String market) {
    if (market == 'crypto') return sym.toUpperCase().trim();
    final s = normalizeSymbol(sym, market);
    if (s == '^NSEI' || s == 'NSEI' || s == 'NIFTY50') return 'NIFTY';
    if (s == '^NSEBANK' || s == 'NSEBANK') return 'BANKNIFTY';
    if (s == '^BSESN' || s == 'SENSEX') return 'SENSEX';
    return s;
  }

  /// Reads the server-side cached quote if present and fresh (updated within
  /// the last 45s). Returns null on any miss/stale/error so the caller falls
  /// back to the live fetch. Never throws.
  static Future<Quote?> _readServerCache(String symbol, String market) async {
    try {
      final key = cacheKeyFor(symbol, market);
      final row = await Supabase.instance.client
          .from('quotes_cache')
          .select()
          .eq('symbol', key)
          .eq('market', market)
          .maybeSingle();
      if (row == null) return null;
      final m = Map<String, dynamic>.from(row as Map);
      final updatedAt = DateTime.tryParse(m['updated_at'] as String? ?? '');
      if (updatedAt == null) return null;
      if (DateTime.now().toUtc().difference(updatedAt.toUtc()) >
          const Duration(seconds: 45)) {
        return null; // stale -> fall through to a live fetch
      }
      final price = (m['price'] as num?)?.toDouble() ?? 0.0;
      if (price <= 0) return null;
      return Quote(
        symbol: symbol,
        yfSymbol: symbol,
        name: m['name'] as String? ?? symbol,
        price: price,
        previousClose: (m['previous_close'] as num?)?.toDouble() ?? price,
        change: (m['change'] as num?)?.toDouble() ?? 0.0,
        changePct: (m['change_pct'] as num?)?.toDouble() ?? 0.0,
        currency: 'INR',
        market: market,
        source: 'cache',
        dayLow: (m['day_low'] as num?)?.toDouble(),
        dayHigh: (m['day_high'] as num?)?.toDouble(),
        open: (m['open'] as num?)?.toDouble(),
      );
    } catch (_) {
      return null; // any failure -> live fallback, never breaks pricing
    }
  }

  static Future<List<Map<String, dynamic>>> search(
    String query,
    String market,
  ) async {
    try {
      final response = await http
          .get(
            Uri.parse(
              '$_functionsBase/market-search?q=${Uri.encodeQueryComponent(query)}&market=${Uri.encodeQueryComponent(market)}',
            ),
            headers: _headers,
          )
          .timeout(_timeout);
      if (response.statusCode == 200) {
        final List decoded = jsonDecode(response.body);
        return decoded.map((e) {
          final map = Map<String, dynamic>.from(e as Map);
          final sym = (map['symbol'] as String? ?? '').toUpperCase();
          if (sym == 'ZOMATO') {
            map['symbol'] = 'ETERNAL';
            map['name'] = 'Eternal (Zomato)';
          }
          return map;
        }).toList();
      }
    } catch (_) {}
    return [];
  }

  static Future<List<Map<String, dynamic>>> getHistory(
    String symbol,
    String market,
    String range,
  ) async {
    final normSym = normalizeSymbol(symbol, market);
    try {
      final response = await http
          .get(
            Uri.parse(
              '$_functionsBase/market-history?symbol=${Uri.encodeQueryComponent(normSym)}&market=${Uri.encodeQueryComponent(market)}&range=${Uri.encodeQueryComponent(range)}',
            ),
            headers: _headers,
          )
          .timeout(_timeout);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return List<Map<String, dynamic>>.from(data['points'] ?? []);
      }
    } catch (_) {}
    return [];
  }

  static const String _yahooBase =
      'https://query1.finance.yahoo.com/v8/finance/chart';
  static const String _cgBase = 'https://api.coingecko.com/api/v3';

  static String _yfSymbol(String sym) {
    var s = sym.toUpperCase().trim();

    // Strip exchange prefix (NSE:, BSE:)
    if (s.startsWith('NSE:') || s.startsWith('BSE:')) {
      s = s.substring(4);
    }

    // Strip Fyers equity suffixes (-EQ, -SM, -BE, -BZ)
    s = s.replaceAll(RegExp(r'-(EQ|SM|BE|BZ)$'), '');

    if (s.endsWith('.NS') ||
        s.endsWith('.BO') ||
        ['^NSEI', '^BSESN', '^NSEBANK'].contains(s)) {
      return s;
    }
    return '$s.NS';
  }

  static final Map<String, String> _cgIds = {
    'BTC': 'bitcoin',
    'ETH': 'ethereum',
    'SOL': 'solana',
    'ADA': 'cardano',
    'XRP': 'ripple',
    'DOGE': 'dogecoin',
    'BNB': 'binancecoin',
    'DOT': 'polkadot',
    'AVAX': 'avalanche-2',
    'MATIC': 'matic-network',
    'LTC': 'litecoin',
    'LINK': 'chainlink',
    'UNI': 'uniswap',
    'ATOM': 'cosmos',
    'TRX': 'tron',
    'VET': 'vechain',
    'FIL': 'filecoin',
    'ALGO': 'algorand',
    'NEAR': 'near-protocol',
    'APT': 'aptos',
  };

  static String? _cgId(String sym) => _cgIds[sym.toUpperCase()];

  static const Map<String, String> _intervalRanges = {
    '1m': '1d',
    '5m': '5d',
    '15m': '1mo',
    '30m': '1mo',
    '1h': '3mo',
    '4h': '1y',
    '1d': '1y',
    '1w': '5y',
  };

  static const Map<String, String> _intervalValues = {
    '1m': '1m',
    '5m': '5m',
    '15m': '15m',
    '30m': '30m',
    '1h': '1h',
    '4h': '1d',
    '1d': '1d',
    '1w': '1wk',
  };

  static const Map<String, int> _cgDays = {
    '1m': 1,
    '5m': 1,
    '15m': 1,
    '30m': 1,
    '1h': 7,
    '4h': 30,
    '1d': 90,
    '1w': 365,
  };

  static Future<List<CandleData>> getCandles(
    String symbol,
    String market,
    String interval,
  ) async {
    try {
      if (market == 'crypto') {
        return _getCgCandles(symbol, interval);
      }
      return _getYfCandles(symbol, interval);
    } catch (_) {
      return [];
    }
  }

  static Future<List<CandleData>> _getYfCandles(
    String symbol,
    String interval,
  ) async {
    final yfSym = _yfSymbol(symbol);
    final range = _intervalRanges[interval] ?? '1mo';
    final yfInterval = _intervalValues[interval] ?? '1d';

    final response = await http
        .get(
          Uri.parse(
            '$_yahooBase/${Uri.encodeComponent(yfSym)}?range=$range&interval=$yfInterval',
          ),
          headers: {'User-Agent': 'Mozilla/5.0'},
        )
        .timeout(_timeout);

    if (response.statusCode != 200) return [];

    final json = jsonDecode(response.body);
    final result = json['chart']?['result']?[0];
    if (result == null) return [];

    final timestamps = List<int>.from(result['timestamp'] ?? []);
    final quote = result['indicators']?['quote']?[0] ?? {};
    final opens = List<num?>.from(quote['open'] ?? []);
    final highs = List<num?>.from(quote['high'] ?? []);
    final lows = List<num?>.from(quote['low'] ?? []);
    final closes = List<num?>.from(quote['close'] ?? []);

    final candles = <CandleData>[];
    for (int i = 0; i < timestamps.length; i++) {
      if (opens[i] != null &&
          highs[i] != null &&
          lows[i] != null &&
          closes[i] != null) {
        candles.add(
          CandleData(
            timestamp: timestamps[i] * 1000,
            open: opens[i]!.toDouble(),
            high: highs[i]!.toDouble(),
            low: lows[i]!.toDouble(),
            close: closes[i]!.toDouble(),
          ),
        );
      }
    }
    return candles;
  }

  static Future<List<CandleData>> _getCgCandles(
    String symbol,
    String interval,
  ) async {
    final id = _cgId(symbol);
    if (id == null) return [];
    final days = _cgDays[interval] ?? 30;

    final response = await http
        .get(
          Uri.parse('$_cgBase/coins/$id/ohlc?vs_currency=inr&days=$days'),
          headers: {'Accept': 'application/json'},
        )
        .timeout(_timeout);

    if (response.statusCode != 200) return [];

    final json = jsonDecode(response.body) as List;
    return json.map((e) {
      final arr = e as List<num>;
      return CandleData(
        timestamp: arr[0].toInt(),
        open: arr[1].toDouble(),
        high: arr[2].toDouble(),
        low: arr[3].toDouble(),
        close: arr[4].toDouble(),
      );
    }).toList();
  }

  static Future<Map<String, dynamic>?> simulateWhatIf(
    String symbol,
    String market,
    double amount,
    int years,
  ) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_functionsBase/whatif'),
            headers: _headers,
            body: jsonEncode({
              'symbol': symbol,
              'market': market,
              'amount': amount,
              'years_ago': years,
            }),
          )
          .timeout(_timeout);
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (_) {}
    return null;
  }

  static Future<Map<String, dynamic>?> getOptionChain(
    String symbol, {
    String market = 'stock',
  }) async {
    final normSym = normalizeSymbol(symbol, market);
    try {
      final response = await http
          .get(
            Uri.parse(
              '$_functionsBase/market-options?symbol=${Uri.encodeQueryComponent(normSym)}&market=${Uri.encodeQueryComponent(market)}',
            ),
            headers: _headers,
          )
          .timeout(_timeout);

      final body = response.body;
      if (response.statusCode == 200) {
        return jsonDecode(body);
      }

      try {
        final decoded = jsonDecode(body);
        if (decoded is Map<String, dynamic>) {
          return decoded;
        }
        return {'error': decoded.toString(), 'status': response.statusCode};
      } catch (_) {
        return {
          'error': 'Option chain request failed',
          'status': response.statusCode,
        };
      }
    } catch (_) {}
    return null;
  }

  static Future<Map<String, dynamic>?> getUpstoxStatus() async {
    try {
      final response = await http
          .get(
            Uri.parse('$_functionsBase/upstox-auth/status'),
            headers: _headers,
          )
          .timeout(_timeout);
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (_) {}
    return null;
  }

  static Future<Map<String, dynamic>?> getUpstoxAuthUrl() async {
    try {
      final response = await http
          .get(
            Uri.parse('$_functionsBase/upstox-auth/authorize-url'),
            headers: _headers,
          )
          .timeout(_timeout);
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (_) {}
    return null;
  }
}
