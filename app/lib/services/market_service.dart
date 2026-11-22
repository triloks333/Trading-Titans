import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/supabase_config.dart';
import '../core/option_pricing.dart';
import '../core/market_hours.dart';
import '../models/quote.dart';
import '../models/candle.dart';
import 'churn_telemetry_service.dart';
import 'diagnostics_service.dart';
import 'price_store.dart';

class MarketService {
  static final String _functionsBase =
      '${supabaseUrl.endsWith('/') ? supabaseUrl.substring(0, supabaseUrl.length - 1) : supabaseUrl}/functions/v1';
  static const Duration _timeout = Duration(seconds: 20);

  static Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer $supabaseAnonKey',
    'apikey': supabaseAnonKey,
  };

  /// The home screen's index and crypto strip.
  ///
  /// Served from pushed prices / `quotes_cache` (all six are always in the
  /// feed's universe), so the 4s dashboard poll no longer runs an edge function
  /// that made six sequential upstream calls. Falls back to `market-overview`
  /// only if the cache cannot price them.
  static const List<(String, String, String, String)> _overviewSymbols = [
    ('NIFTY', 'stock', 'NIFTY 50', 'index'),
    ('SENSEX', 'stock', 'SENSEX', 'index'),
    ('BANKNIFTY', 'stock', 'BANK NIFTY', 'index'),
    ('BTC', 'crypto', 'Bitcoin', 'crypto'),
    ('ETH', 'crypto', 'Ethereum', 'crypto'),
    ('SOL', 'crypto', 'Solana', 'crypto'),
  ];

  static Future<Map<String, Quote>> _cachedOnly(
          List<({String symbol, String market})> pairs) =>
      quotes(pairs, liveFallback: false);

  static Future<List<Quote>> getMarketOverview() async {
    try {
      final got = await _cachedOnly([
        for (final (s, m, _, _) in _overviewSymbols) (symbol: s, market: m),
      ]);
      final out = <Quote>[];
      for (final (s, m, display, category) in _overviewSymbols) {
        final q = got['$s\x1F$m'];
        if (q == null) continue;
        out.add(Quote(
          symbol: q.symbol,
          yfSymbol: q.yfSymbol,
          name: category == 'crypto' ? display : q.name,
          price: q.price,
          previousClose: q.previousClose,
          change: q.change,
          changePct: q.changePct,
          currency: q.currency,
          market: q.market,
          source: q.source,
          displayName: display,
          category: category,
          dayLow: q.dayLow,
          dayHigh: q.dayHigh,
          open: q.open,
        ));
      }
      if (out.length == _overviewSymbols.length) return out;
    } catch (_) {}
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

  /// How old a `quotes_cache` row may be and still be used instead of a live
  /// fetch.
  ///
  /// `price-feed` now rewrites every row every ~3s, and `refresh-quotes` picks
  /// up anything older than 30s one symbol at a time. So a row inside this
  /// window is as fresh as a live call would be, and a phone falling through to
  /// `market-quote` (one edge call plus two Yahoo requests) only happens for a
  /// symbol the server is not tracking yet. Was 10s when the cache was written
  /// once a minute, which sent most reads to the live path.
  static const Duration _serverCacheMaxAge = Duration(seconds: 30);

  /// Symbols already reported to the server as browsed, with when, so each is
  /// sent at most once every few minutes.
  static final Map<String, DateTime> _hotNoted = {};

  /// Tells `price-feed` to track a symbol nobody holds or watches, so it moves
  /// live from the next tick instead of costing a live fetch on every poll.
  static void _noteHotSymbol(String symbol, String market) {
    final key = cacheKeyFor(symbol, market);
    final k = '$key\x1F$market';
    final last = _hotNoted[k];
    if (last != null && DateTime.now().difference(last) < const Duration(minutes: 5)) return;
    _hotNoted[k] = DateTime.now();
    Supabase.instance.client
        .rpc('note_hot_symbol', params: {'p_symbol': key, 'p_market': market})
        .then((_) {}, onError: (_) {});
  }

  static ({bool isDerivative, String type, String underlying, String? expiryDate, double? strikePrice, String? optionType})? parseDerivative(String rawSymbol) {
    var s = rawSymbol.trim();
    if (s.startsWith('NSE:') || s.startsWith('BSE:')) {
      s = s.substring(4);
    }
    s = s.replaceAll(RegExp(r'-(EQ|SM|BE|BZ)$'), '');

    // 1. Compact NSE Future: RELIANCE26DECFUT, NIFTY26OCTFUT
    final compactFut = RegExp(r'^([A-Za-z&-]+)(\d{2})([A-Za-z]{3})FUT$', caseSensitive: false).firstMatch(s);
    if (compactFut != null) {
      final und = compactFut.group(1)!.toUpperCase();
      final yr = int.tryParse(compactFut.group(2)!) ?? 26;
      final mon = compactFut.group(3)!.toUpperCase();
      final expiry = _expiryDateFromMonth(2000 + yr, mon);
      return (
        isDerivative: true,
        type: 'FUTURE',
        underlying: und,
        expiryDate: expiry,
        strikePrice: null,
        optionType: null,
      );
    }

    // 2. Compact NSE Option: RELIANCE26DEC640CE, NIFTY26OCT24500PE
    final compactOpt = RegExp(r'^([A-Za-z&-]+)(\d{2})([A-Za-z]{3})(\d+(?:\.\d+)?)(CE|PE)$', caseSensitive: false).firstMatch(s);
    if (compactOpt != null) {
      final und = compactOpt.group(1)!.toUpperCase();
      final yr = int.tryParse(compactOpt.group(2)!) ?? 26;
      final mon = compactOpt.group(3)!.toUpperCase();
      final strike = double.tryParse(compactOpt.group(4)!) ?? 0.0;
      final optType = compactOpt.group(5)!.toUpperCase();
      final expiry = _expiryDateFromMonth(2000 + yr, mon);
      return (
        isDerivative: true,
        type: 'OPTION',
        underlying: und,
        expiryDate: expiry,
        strikePrice: strike,
        optionType: optType,
      );
    }

    // 3. Hyphenated Option: RELIANCE-2026-10-27-3125-CE
    final hypOpt = RegExp(r'^([A-Za-z&-]+)-(\d{4})-(\d{1,2})-(\d{1,2})-(\d+(?:\.\d+)?)-(CE|PE)$', caseSensitive: false).firstMatch(s);
    if (hypOpt != null) {
      final und = hypOpt.group(1)!.toUpperCase();
      final yyyy = hypOpt.group(2)!;
      final mm = hypOpt.group(3)!.padLeft(2, '0');
      final dd = hypOpt.group(4)!.padLeft(2, '0');
      final strike = double.tryParse(hypOpt.group(5)!) ?? 0.0;
      final optType = hypOpt.group(6)!.toUpperCase();
      return (
        isDerivative: true,
        type: 'OPTION',
        underlying: und,
        expiryDate: '$yyyy-$mm-$dd',
        strikePrice: strike,
        optionType: optType,
      );
    }

    // 4. Space-separated Future: RELIANCE OCT FUT, RELIANCE 29 Dec 26 FUT
    final spaceFut = RegExp(r'^([A-Za-z&-]+)\s+(?:(\d{1,2})\s+)?([A-Za-z]{3})(?:\s+(\d{2}))?\s+FUT$', caseSensitive: false).firstMatch(s);
    if (spaceFut != null) {
      final und = spaceFut.group(1)!.toUpperCase();
      final mon = spaceFut.group(3)!.toUpperCase();
      final yr = int.tryParse(spaceFut.group(4) ?? '') ?? DateTime.now().year;
      final expiry = _expiryDateFromMonth(yr < 100 ? 2000 + yr : yr, mon);
      return (
        isDerivative: true,
        type: 'FUTURE',
        underlying: und,
        expiryDate: expiry,
        strikePrice: null,
        optionType: null,
      );
    }

    // 5. Simple Future: RELIANCE-FUT or RELIANCE FUT
    if (s.endsWith('FUT') || s.endsWith('-FUT')) {
      final und = s.replaceAll(RegExp(r'[- ]?FUT$', caseSensitive: false), '').trim().toUpperCase();
      if (und.isNotEmpty) {
        return (
          isDerivative: true,
          type: 'FUTURE',
          underlying: und,
          expiryDate: null,
          strikePrice: null,
          optionType: null,
        );
      }
    }

    return null;
  }

  static String _expiryDateFromMonth(int year, String monthStr) {
    const months = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];
    final mIndex = months.indexOf(monthStr.toUpperCase());
    final month = mIndex >= 0 ? mIndex + 1 : 1;
    final lastDay = DateTime(year, month + 1, 0);
    var diff = lastDay.weekday - DateTime.thursday;
    if (diff < 0) diff += 7;
    final lastThu = lastDay.subtract(Duration(days: diff));
    final mm = month.toString().padLeft(2, '0');
    final dd = lastThu.day.toString().padLeft(2, '0');
    return '$year-$mm-$dd';
  }

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

    // Pushed price (Realtime): no network at all.
    if (!forceRefresh) {
      final pushed = PriceStore.instance
          .get(cacheKeyFor(symbol, market), market, requestedSymbol: symbol);
      if (pushed != null) {
        _quoteCache[cacheKey] = {'timestamp': now, 'quote': pushed};
        return pushed;
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

    // Derivative pricing fallback: if this is an F&O instrument, synthesize
    // its price from the underlying spot so users see prices immediately.
    if (market == 'stock') {
      final deriv = parseDerivative(symbol);
      if (deriv != null) {
        final spotQuote = await quote(deriv.underlying, 'stock');
        if (spotQuote != null && spotQuote.price > 0) {
          final daysToExpiry = MarketHours.daysToExpiry(
            deriv.expiryDate != null ? DateTime.tryParse(deriv.expiryDate!) : null,
            fallback: 15.0,
          );
          final double price;
          final double prevClose;
          if (deriv.type == 'FUTURE') {
            price = OptionPricing.futurePrice(spot: spotQuote.price, daysToExpiry: daysToExpiry);
            prevClose = OptionPricing.futurePrice(
              spot: spotQuote.previousClose > 0 ? spotQuote.previousClose : spotQuote.price,
              daysToExpiry: daysToExpiry + 1.0,
            );
          } else {
            price = OptionPricing.optionPremium(
              optionType: deriv.optionType ?? 'CE',
              spot: spotQuote.price,
              strike: deriv.strikePrice ?? spotQuote.price,
              daysToExpiry: daysToExpiry,
              symbol: deriv.underlying,
            );
            prevClose = OptionPricing.optionPremium(
              optionType: deriv.optionType ?? 'CE',
              spot: spotQuote.previousClose > 0 ? spotQuote.previousClose : spotQuote.price,
              strike: deriv.strikePrice ?? spotQuote.price,
              daysToExpiry: daysToExpiry + 1.0,
              symbol: deriv.underlying,
            );
          }
          final pRounded = (price * 100).round() / 100.0;
          final pcRounded = (prevClose * 100).round() / 100.0;
          final change = ((pRounded - pcRounded) * 100).round() / 100.0;
          final changePct = pcRounded > 0 ? ((pRounded - pcRounded) / pcRounded) * 100.0 : 0.0;
          final quoteVal = Quote(
            symbol: symbol,
            yfSymbol: symbol,
            name: symbol,
            price: pRounded,
            previousClose: pcRounded,
            change: change,
            changePct: (changePct * 100).round() / 100.0,
            currency: 'INR',
            market: 'stock',
            source: 'synthetic_fo',
            dayLow: ((pRounded * 0.985) * 100).round() / 100.0,
            dayHigh: ((pRounded * 1.015) * 100).round() / 100.0,
            open: pcRounded,
          );
          _quoteCache[cacheKey] = {
            'timestamp': now,
            'quote': quoteVal,
          };
          return quoteVal;
        }
      }
    }

    if (parseDerivative(symbol) == null) _noteHotSymbol(symbol, market);
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
    ChurnTelemetryService.instance.recordQuoteFail('market-quote');
    return null;
  }

  /// Live USD/INR rate, used to render the app in the user's chosen display
  /// currency. Returns null on any failure so callers keep their cached rate
  /// rather than formatting against zero.
  static Future<double?> fetchUsdInrRate() async {
    try {
      final response = await http
          .get(Uri.parse('$_functionsBase/market-quote?market=fx'), headers: _headers)
          .timeout(_timeout);
      if (response.statusCode != 200) return null;
      final body = jsonDecode(response.body);
      if (body is! Map) return null;
      final rate = (body['price'] as num?)?.toDouble();
      return (rate != null && rate > 0) ? rate : null;
    } catch (_) {
      return null;
    }
  }

  static Future<double?> fetchEurInrRate() async {
    try {
      final response = await http
          .get(Uri.parse('$_functionsBase/market-quote?market=fx&symbol=EURINR'), headers: _headers)
          .timeout(_timeout);
      if (response.statusCode != 200) return null;
      final body = jsonDecode(response.body);
      if (body is! Map) return null;
      final rate = (body['price'] as num?)?.toDouble();
      return (rate != null && rate > 0) ? rate : null;
    } catch (_) {
      return null;
    }
  }

  static Future<double?> fetchPkrInrRate() async {
    try {
      final response = await http
          .get(Uri.parse('$_functionsBase/market-quote?market=fx&symbol=PKRINR'), headers: _headers)
          .timeout(_timeout);
      if (response.statusCode != 200) return null;
      final body = jsonDecode(response.body);
      if (body is! Map) return null;
      final rate = (body['price'] as num?)?.toDouble();
      return (rate != null && rate > 0) ? rate : null;
    } catch (_) {
      return null;
    }
  }


  /// Batch variant of [quote]: resolves many symbols with a single server-cache
  /// read per market (collapsing an N-reads-per-list pattern into one), then
  /// falls back to the live per-symbol [quote] for anything not fresh in the
  /// cache. Result is identical to calling [quote] on each pair — just fewer
  /// round-trips. Returns a map keyed by `symbol\x1Fmarket`. Never throws.
  static Future<Map<String, Quote>> quotes(
    List<({String symbol, String market})> pairs, {
    bool liveFallback = true,
  }) async {
    final result = <String, Quote>{};
    if (pairs.isEmpty) return result;

    // Dedupe requested pairs.
    final unique = <String, ({String symbol, String market})>{};
    for (final p in pairs) {
      if (p.symbol.trim().isEmpty) continue;
      unique['${p.symbol}\x1F${p.market}'] = p;
    }

    // Group by market so we can batch the server-cache read into one IN query.
    final byMarket = <String, List<({String symbol, String market})>>{};
    for (final p in unique.values) {
      byMarket.putIfAbsent(p.market, () => []).add(p);
      // Pre-request underlying symbols for any Indian stock derivatives
      if (p.market == 'stock') {
        final d = parseDerivative(p.symbol);
        if (d != null) {
          byMarket['stock']!.add((symbol: d.underlying, market: 'stock'));
        }
      }
    }

    final resolved = <String>{};
    // Pushed prices first: anything the Realtime feed delivered recently needs
    // no query at all.
    for (final ps in byMarket.values) {
      for (final p in ps) {
        final reqKey = '${p.symbol}\x1F${p.market}';
        final pushed = PriceStore.instance
            .get(cacheKeyFor(p.symbol, p.market), p.market, requestedSymbol: p.symbol);
        if (pushed != null) {
          result[reqKey] = pushed;
          resolved.add(reqKey);
        }
      }
    }
    for (final entry in byMarket.entries) {
      final market = entry.key;
      final ps = entry.value
          .where((p) => !resolved.contains('${p.symbol}\x1F${p.market}'))
          .toList();
      final cacheKeys =
          ps.map((p) => cacheKeyFor(p.symbol, market)).toSet().toList();
      if (cacheKeys.isEmpty) continue;
      try {
        DiagnosticsService.noteDbCall('quotes_cache.select(batch:$market)');
        final rows = await Supabase.instance.client
            .from('quotes_cache')
            .select()
            .inFilter('symbol', cacheKeys)
            .eq('market', market);
        final rowByKey = <String, Map<String, dynamic>>{};
        for (final r in (rows as List)) {
          final m = Map<String, dynamic>.from(r as Map);
          rowByKey[m['symbol'] as String] = m;
        }
        final nowUtc = DateTime.now().toUtc();
        for (final p in ps) {
          final m = rowByKey[cacheKeyFor(p.symbol, market)];
          if (m == null) continue;
          final updatedAt = DateTime.tryParse(m['updated_at'] as String? ?? '');
          if (updatedAt == null) continue;
          if (nowUtc.difference(updatedAt.toUtc()) > _serverCacheMaxAge) {
            continue; // stale -> live fallback
          }
          final price = (m['price'] as num?)?.toDouble() ?? 0.0;
          if (price <= 0) continue;
          final reqKey = '${p.symbol}\x1F${p.market}';
          result[reqKey] = Quote(
            symbol: p.symbol,
            yfSymbol: p.symbol,
            name: m['name'] as String? ?? p.symbol,
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
          resolved.add(reqKey);
        }
      } catch (_) {
        // Ignore; unresolved pairs fall back to the live fetch below.
      }
    }

    // Synthesize derivative quotes from underlying spot prices loaded in this batch
    for (final p in unique.values) {
      final reqKey = '${p.symbol}\x1F${p.market}';
      if (resolved.contains(reqKey) || p.market != 'stock') continue;
      final d = parseDerivative(p.symbol);
      if (d == null) continue;
      final undKey = '${d.underlying}\x1Fstock';
      final spotQuote = result[undKey] ?? _quoteCache[undKey]?['quote'] as Quote?;
      if (spotQuote != null && spotQuote.price > 0) {
        final daysToExpiry = MarketHours.daysToExpiry(
          d.expiryDate != null ? DateTime.tryParse(d.expiryDate!) : null,
          fallback: 15.0,
        );
        final double price;
        final double prevClose;
        if (d.type == 'FUTURE') {
          price = OptionPricing.futurePrice(spot: spotQuote.price, daysToExpiry: daysToExpiry);
          prevClose = OptionPricing.futurePrice(
            spot: spotQuote.previousClose > 0 ? spotQuote.previousClose : spotQuote.price,
            daysToExpiry: daysToExpiry + 1.0,
          );
        } else {
          price = OptionPricing.optionPremium(
            optionType: d.optionType ?? 'CE',
            spot: spotQuote.price,
            strike: d.strikePrice ?? spotQuote.price,
            daysToExpiry: daysToExpiry,
            symbol: d.underlying,
          );
          prevClose = OptionPricing.optionPremium(
            optionType: d.optionType ?? 'CE',
            spot: spotQuote.previousClose > 0 ? spotQuote.previousClose : spotQuote.price,
            strike: d.strikePrice ?? spotQuote.price,
            daysToExpiry: daysToExpiry + 1.0,
            symbol: d.underlying,
          );
        }
        final pRounded = (price * 100).round() / 100.0;
        final pcRounded = (prevClose * 100).round() / 100.0;
        final change = ((pRounded - pcRounded) * 100).round() / 100.0;
        final changePct = pcRounded > 0 ? ((pRounded - pcRounded) / pcRounded) * 100.0 : 0.0;
        final q = Quote(
          symbol: p.symbol,
          yfSymbol: p.symbol,
          name: p.symbol,
          price: pRounded,
          previousClose: pcRounded,
          change: change,
          changePct: (changePct * 100).round() / 100.0,
          currency: 'INR',
          market: 'stock',
          source: 'synthetic_fo',
          dayLow: ((pRounded * 0.985) * 100).round() / 100.0,
          dayHigh: ((pRounded * 1.015) * 100).round() / 100.0,
          open: pcRounded,
        );
        result[reqKey] = q;
        resolved.add(reqKey);
      }
    }

    if (!liveFallback) return result;

    // Live fallback for anything not served fresh from cache (parallel — the
    // same behaviour as the previous per-symbol code path).
    final pending = unique.values
        .where((p) => !resolved.contains('${p.symbol}\x1F${p.market}'));
    await Future.wait(pending.map((p) async {
      try {
        final q = await quote(p.symbol, p.market, forceRefresh: true);
        if (q != null) result['${p.symbol}\x1F${p.market}'] = q;
      } catch (_) {}
    }));

    return result;
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

  /// Reads the server-side cached quote if present and fresh (within
  /// [_serverCacheMaxAge]). Returns null on any miss/stale/error so the caller
  /// falls back to the live fetch. Never throws.
  static Future<Quote?> _readServerCache(String symbol, String market) async {
    try {
      final key = cacheKeyFor(symbol, market);
      DiagnosticsService.noteDbCall('quotes_cache.select(one:$key)');
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
          _serverCacheMaxAge) {
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
    'POL': 'polygon-ecosystem-token', // MATIC was delisted after the Polygon rebrand
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

  /// Candles for the same symbol, fetched through our own `market-history`
  /// function instead of calling the upstream provider from the client.
  ///
  /// This is the only variant a browser can use. [_getYfCandles] and
  /// [_getCgCandles] talk to Yahoo/CoinGecko directly, and neither sends the
  /// CORS headers a browser demands; worse, they set a `User-Agent`, which a
  /// browser forbids scripts from setting at all. The edge function already
  /// proxies both providers, returns `{t,o,h,l,c}` verbatim, and answers with
  /// `corsHeaders`.
  ///
  /// Works on mobile too — it is simply one more hop there, which is why the
  /// phone keeps using the direct path.
  static Future<List<CandleData>> getCandlesViaFunction(
    String symbol,
    String market,
    String interval,
  ) async {
    try {
      final normSym = market == 'crypto' ? symbol.toUpperCase() : symbol;
      final response = await http
          .get(
            Uri.parse(
              '$_functionsBase/market-history'
              '?symbol=${Uri.encodeQueryComponent(normSym)}'
              '&market=${Uri.encodeQueryComponent(market)}'
              '&range=1mo'
              '&interval=${Uri.encodeQueryComponent(interval)}',
            ),
            headers: _headers,
          )
          .timeout(_timeout);

      if (response.statusCode != 200) return [];

      final body = jsonDecode(response.body);
      final raw = body is Map ? body['candles'] : null;
      if (raw is! List) return [];

      return raw
          .whereType<Map>()
          .map((c) => CandleData.fromJson(Map<String, dynamic>.from(c)))
          .toList();
    } catch (_) {
      // A chart is not worth an error dialog; the caller renders "no data".
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
