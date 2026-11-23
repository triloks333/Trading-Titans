import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/quote.dart';
import 'app_flags_service.dart';

/// Live prices pushed by the server.
///
/// The `price-feed` edge function fetches every symbol in batches every few
/// seconds, writes `quotes_cache`, and broadcasts the prices that changed on the
/// public Realtime topic `prices` (event `tick`). This store keeps the latest
/// pushed price per symbol in memory, so [MarketService.quote] can answer from
/// here with no network call at all, and screens can redraw the moment a price
/// moves instead of waiting for their next poll.
///
/// Budget: Realtime bills per message delivered to each phone, and Supabase Pro
/// includes 5M a month. So the socket is open only while the app is in the
/// foreground, there is one combined message per server push (not one per
/// symbol), and the `realtime_prices_enabled` row in `app_flags` switches the
/// whole thing off without a release. When it is off, or the socket drops, the
/// app falls back to reading `quotes_cache`, which the same feed keeps fresh.
class PriceStore extends ChangeNotifier with WidgetsBindingObserver {
  PriceStore._internal();
  static final PriceStore instance = PriceStore._internal();

  static const String topic = 'prices';
  static const String flagKey = 'realtime_prices_enabled';

  /// A pushed price is served as current for this long. The server pushes every
  /// ~5s while prices move, so this covers a missed push or two.
  static const Duration maxAge = Duration(seconds: 20);

  final Map<String, ({Quote quote, DateTime at})> _prices = {};
  RealtimeChannel? _channel;
  bool _started = false;
  bool _foreground = true;
  DateTime? _lastPushAt;
  Timer? _notifyDebounce;

  /// When the last push arrived, or null if none has this session.
  DateTime? get lastPushAt => _lastPushAt;

  /// True while subscribed and pushes are arriving.
  bool get isLive =>
      _channel != null &&
      _lastPushAt != null &&
      DateTime.now().difference(_lastPushAt!) < const Duration(seconds: 30);

  static String keyFor(String cacheSymbol, String market) => '$cacheSymbol\x1F$market';

  /// Starts listening. Safe to call more than once.
  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    AppFlagsService.instance.addListener(_sync);
    _sync();
  }

  bool get _enabled =>
      AppFlagsService.instance.isEnabledOr(flagKey, defaultValue: true);

  void _sync() {
    final want = _foreground && _enabled;
    if (want && _channel == null) {
      _subscribe();
    } else if (!want && _channel != null) {
      _unsubscribe();
    }
  }

  void _subscribe() {
    try {
      final client = Supabase.instance.client;
      _channel = client
          .channel(topic)
          .onBroadcast(event: 'tick', callback: _onTick)
          .subscribe((status, [error]) {
        if (status == RealtimeSubscribeStatus.channelError ||
            status == RealtimeSubscribeStatus.timedOut) {
          debugPrint('PriceStore: realtime $status ${error ?? ''}');
        }
      });
    } catch (e) {
      debugPrint('PriceStore: subscribe failed: $e');
      _channel = null;
    }
  }

  void _unsubscribe() {
    final ch = _channel;
    _channel = null;
    if (ch != null) {
      try {
        Supabase.instance.client.removeChannel(ch);
      } catch (_) {}
    }
  }

  void _onTick(Map<String, dynamic> message) {
    // The client hands over the broadcast envelope; the server's body sits in
    // `payload`. Accept the bare body too, in case the client ever unwraps it.
    final body = message['payload'] is Map ? message['payload'] as Map : message;
    final rows = body['q'];
    if (rows is! List) return;
    final now = DateTime.now();
    for (final r in rows) {
      if (r is! Map) continue;
      final symbol = r['s'] as String?;
      final market = r['m'] as String?;
      final price = (r['p'] as num?)?.toDouble() ?? 0;
      if (symbol == null || market == null || price <= 0) continue;
      final prev = (r['pc'] as num?)?.toDouble() ?? price;
      _prices[keyFor(symbol, market)] = (
        quote: Quote(
          symbol: symbol,
          yfSymbol: symbol,
          name: r['n'] as String? ?? symbol,
          price: price,
          previousClose: prev,
          change: (r['c'] as num?)?.toDouble() ?? price - prev,
          changePct: (r['cp'] as num?)?.toDouble() ?? 0,
          currency: currencyFor(market),
          market: market,
          source: 'live',
          dayLow: (r['l'] as num?)?.toDouble(),
          dayHigh: (r['h'] as num?)?.toDouble(),
          open: (r['o'] as num?)?.toDouble(),
        ),
        at: now,
      );
    }
    _lastPushAt = now;
    // Many listeners redraw on this; coalesce bursts into one frame's work.
    _notifyDebounce ??= Timer(const Duration(milliseconds: 250), () {
      _notifyDebounce = null;
      notifyListeners();
    });
  }

  /// Native currency per market, as `market-quote` reports it.
  static String currencyFor(String market) {
    switch (market) {
      case 'us_stock':
      case 'commodity':
        return 'USD';
      case 'pakistan_stock':
        return 'PKR';
      case 'italy_stock':
        return 'EUR';
      default:
        return 'INR';
    }
  }

  /// The pushed quote for [cacheSymbol] (the `quotes_cache` key) if it is still
  /// current, re-labelled with the symbol the caller asked for.
  Quote? get(String cacheSymbol, String market, {String? requestedSymbol}) {
    final hit = _prices[keyFor(cacheSymbol, market)];
    if (hit == null || DateTime.now().difference(hit.at) > maxAge) return null;
    final q = hit.quote;
    if (requestedSymbol == null || requestedSymbol == q.symbol) return q;
    return Quote(
      symbol: requestedSymbol,
      yfSymbol: requestedSymbol,
      name: q.name,
      price: q.price,
      previousClose: q.previousClose,
      change: q.change,
      changePct: q.changePct,
      currency: q.currency,
      market: q.market,
      source: q.source,
      dayLow: q.dayLow,
      dayHigh: q.dayHigh,
      open: q.open,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final fg = state == AppLifecycleState.resumed;
    if (fg == _foreground) return;
    _foreground = fg;
    if (!fg) _prices.clear(); // stale the moment we stop listening
    _sync();
  }

  @visibleForTesting
  void debugIngest(Map<String, dynamic> message) => _onTick(message);

  @visibleForTesting
  void debugReset() {
    _prices.clear();
    _lastPushAt = null;
  }
}
