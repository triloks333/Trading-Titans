// The live price feed's message format, as `price-feed` broadcasts it.
//
// The server and the app agree on short keys (s, m, p, pc, c, cp, l, h, o, n)
// to keep each Realtime message small. This pins the app side of that contract.

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/services/price_store.dart';

void main() {
  final store = PriceStore.instance;

  setUp(store.debugReset);

  Map<String, dynamic> tick(List<dynamic> q) => {
        'event': 'tick',
        'payload': {'t': 0, 'q': q},
      };

  test('a pushed price is served under its cache key', () {
    store.debugIngest(tick([
      {'s': 'RELIANCE', 'm': 'stock', 'p': 1500.5, 'pc': 1490.0, 'c': 10.5, 'cp': 0.7, 'l': 1488.0, 'h': 1510.0, 'o': 1491.0, 'n': 'Reliance Industries'},
    ]));
    final q = store.get('RELIANCE', 'stock')!;
    expect(q.price, 1500.5);
    expect(q.previousClose, 1490.0);
    expect(q.changePct, 0.7);
    expect(q.dayHigh, 1510.0);
    expect(q.name, 'Reliance Industries');
    expect(q.currency, 'INR');
    expect(store.lastPushAt, isNotNull);
  });

  test('the caller keeps the symbol it asked for', () {
    store.debugIngest(tick([
      {'s': 'NIFTY', 'm': 'stock', 'p': 24000.0, 'pc': 23900.0},
    ]));
    expect(store.get('NIFTY', 'stock', requestedSymbol: '^NSEI')!.symbol, '^NSEI');
  });

  test('markets do not collide and carry their own currency', () {
    store.debugIngest(tick([
      {'s': 'AAPL', 'm': 'us_stock', 'p': 210.0, 'pc': 205.0},
    ]));
    expect(store.get('AAPL', 'stock'), isNull);
    expect(store.get('AAPL', 'us_stock')!.currency, 'USD');
  });

  test('rows without a usable price are ignored', () {
    store.debugIngest(tick([
      {'s': 'X', 'm': 'stock', 'p': 0},
      {'m': 'stock', 'p': 5},
      'garbage',
    ]));
    expect(store.get('X', 'stock'), isNull);
  });

  test('a bare body without the envelope is accepted too', () {
    store.debugIngest({'q': [{'s': 'BTC', 'm': 'crypto', 'p': 8000000.0}]});
    expect(store.get('BTC', 'crypto')!.price, 8000000.0);
  });
}
