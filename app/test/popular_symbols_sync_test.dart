// The Trade screen's movers universe must all be in the refresh-quotes universe.
//
// This is the invariant that broke: the popular lists live in Dart, the refresh
// job's universe lives in TypeScript, and the job only collected symbols someone
// held or watched. Popular rows therefore missed `quotes_cache`, so each client
// fetched them live while their neighbours were served from cache — rows in one
// list moved at different rates, and US rows never refreshed at all.
//
// Rather than test the duplication away, this pins it: add a symbol to one side
// and this fails with the missing name. Cheaper than a `popular_symbols` table
// for three static lists.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Symbols in one market's list of `kMoverUniverse`, written as
/// `('RELIANCE', 'Reliance Industries')` tuples.
Set<String> dartPopular(String source, String market) {
  final universe = source.indexOf('kMoverUniverse');
  expect(universe, isNot(-1), reason: 'kMoverUniverse not found in trade_screen.dart');
  final start = source.indexOf("'$market': [", universe);
  expect(start, isNot(-1), reason: '$market list not found in kMoverUniverse');
  final end = source.indexOf('_s(s, n),', start);
  expect(end, isNot(-1), reason: '$market list is not a closed literal');
  return RegExp(r"\('([A-Z0-9]+)', '").allMatches(source.substring(start, end)).map((m) => m.group(1)!).toSet();
}

/// Symbols in one `[...].map((symbol) => ({ symbol, market: "x" }))` group of
/// the POPULAR constant.
Set<String> tsPopular(String source, String market) {
  final popularStart = source.indexOf('const POPULAR');
  expect(popularStart, isNot(-1), reason: 'POPULAR not found in quote_universe.ts');
  final popularEnd = source.indexOf('];', popularStart);
  final block = source.substring(popularStart, popularEnd);

  // Each group is an array literal followed by the market it maps to.
  final groups = RegExp(
    r'\.\.\.\[([^\]]+)\]\s*\.map\(\(symbol\)\s*=>\s*\(\{\s*symbol,\s*market:\s*([^}]+?)\s*\}\)\)',
    dotAll: true,
  ).allMatches(block);

  for (final g in groups) {
    final marketToken = g.group(2)!.trim();
    // Either a quoted literal ("stock") or the US_MARKET constant.
    final resolved = marketToken == 'US_MARKET'
        ? 'us_stock'
        : marketToken.replaceAll('"', '').replaceAll("'", '');
    if (resolved != market) continue;
    return RegExp(r'"([A-Z0-9]+)"')
        .allMatches(g.group(1)!)
        .map((m) => m.group(1)!)
        .toSet();
  }
  fail('no POPULAR group found for market "$market"');
}

void main() {
  late String dart;
  late String ts;

  setUpAll(() {
    // Tests run with the app package as cwd.
    dart = File('lib/screens/main/trade_screen.dart').readAsStringSync();
    // The universe (POPULAR and the session gate) is shared by refresh-quotes
    // and price-feed.
    ts = File('../supabase/functions/_shared/quote_universe.ts').readAsStringSync();
  });

  test('every popular Indian stock is in the refresh universe', () {
    expect(tsPopular(ts, 'stock'), dartPopular(dart, 'stock'));
  });

  test('every popular coin is in the refresh universe', () {
    expect(tsPopular(ts, 'crypto'), dartPopular(dart, 'crypto'));
  });

  test('every popular US stock is in the refresh universe', () {
    expect(tsPopular(ts, 'us_stock'), dartPopular(dart, 'us_stock'));
  });

  test('the lists are not accidentally empty', () {
    // Guards the parsers themselves: a regex that silently matches nothing would
    // make all three tests above pass trivially.
    expect(dartPopular(dart, 'stock').length, greaterThan(4));
    expect(dartPopular(dart, 'crypto').length, greaterThan(4));
    expect(dartPopular(dart, 'us_stock').length, greaterThan(4));
  });

  test('refresh-quotes gates US symbols on the US session, not the Indian one', () {
    // The other half of the same bug: US rows were refreshed while NSE was open
    // (US shut, so a stale close was restamped fresh) and skipped once the US
    // market opened.
    expect(ts, contains('if (market === US_MARKET) return usOpen;'));
    for (final fn in ['refresh-quotes', 'price-feed']) {
      final src = File('../supabase/functions/$fn/index.ts').readAsStringSync();
      expect(src, contains('isUsMarketOpen'), reason: fn);
    }
  });
}
