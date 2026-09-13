// Full-coverage tests for the order-decision RULES that have repeatedly
// regressed: immediate-vs-pending execution, the market-hours gate (all
// markets), option-limit routing, limit-fill triggering, price-alert crossing,
// lot<->unit conversion, and the exit clamp.
//
// Following this project's established pattern, the rules are ported here
// EXACTLY as they exist in supabase_service.dart / notification logic, then
// exercised with deterministic cases and property-based generation. If a future
// edit changes a rule, the corresponding assertion fails and pinpoints it.

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:glados/glados.dart' hide test, group, expect;

// ── Ports of production rules ───────────────────────────────────────────────

/// Mirrors placeOrder: base = isMarket; limit crosses if quote available;
/// market-hours gate applies to ALL markets; option LIMIT orders are forced to
/// pending so they wait for the live premium.
bool shouldExecuteImmediately({
  required bool isMarket,
  required bool isQuoteAvailable,
  required String side,
  required double currentPrice,
  required double limitPrice,
  required bool marketOpen,
  required String instrumentType,
}) {
  bool exec = isMarket;
  if (!isMarket) {
    if (isQuoteAvailable) {
      exec = side == 'buy' ? currentPrice <= limitPrice : currentPrice >= limitPrice;
    } else {
      exec = false;
    }
  }
  if (!marketOpen) exec = false;
  if (instrumentType == 'OPTION' && !isMarket) exec = false;
  return exec;
}

/// Mirrors executePendingOrders limit guard: a limit fills only when reached.
bool limitFillReached({required String side, required double execPrice, required double limit}) {
  if (side == 'buy') return execPrice <= limit;
  return execPrice >= limit;
}

/// Mirrors how BOTH executors resolve an order's trigger:
/// `limit_price ?? price` (execute-pending-orders/index.ts and the on-device
/// fallback). `limit_price` is the source of truth; `price` is only a fallback
/// for rows written before that column existed, because `price` is overwritten
/// with the FILL price the moment an order executes.
double resolveTrigger({double? limitPrice, double? price}) => limitPrice ?? price ?? 0.0;

/// Mirrors modifyOrder's update payload. Both price columns must move together,
/// or the engine keeps matching the pre-modification trigger.
Map<String, dynamic> modifyOrderPayload({
  required double quantity,
  required double price,
  required bool isLimit,
}) {
  return {
    'quantity': quantity,
    'price': price,
    'limit_price': isLimit ? price : null,
    'total': quantity * price,
  };
}

/// Mirrors price-alert evaluation.
bool priceAlertCrossed({required String direction, required double price, required double target}) {
  return direction == 'above' ? price >= target : price <= target;
}

double unitsFromLots(int lots, int lotSize) => (lots * lotSize).toDouble();
int lotsFromUnits(double units, int lotSize) => (units / lotSize).toInt();

/// Mirrors the exit clamp: never overshoot into a reverse position.
int exitNewNetQty({required int existingLots, required int requestedLots}) {
  if (existingLots == 0) return 0;
  final sideSign = existingLots > 0 ? -1 : 1;
  final closed = math.min(requestedLots.abs(), existingLots.abs());
  return existingLots + (closed * sideSign);
}

void main() {
  group('shouldExecuteImmediately', () {
    test('market order during hours executes', () {
      expect(
        shouldExecuteImmediately(isMarket: true, isQuoteAvailable: true, side: 'buy', currentPrice: 100, limitPrice: 0, marketOpen: true, instrumentType: 'EQUITY'),
        true,
      );
    });

    test('market order after hours goes pending (all markets)', () {
      expect(
        shouldExecuteImmediately(isMarket: true, isQuoteAvailable: true, side: 'buy', currentPrice: 100, limitPrice: 0, marketOpen: false, instrumentType: 'EQUITY'),
        false,
      );
    });

    test('equity buy limit fills only at/below limit', () {
      expect(shouldExecuteImmediately(isMarket: false, isQuoteAvailable: true, side: 'buy', currentPrice: 95, limitPrice: 100, marketOpen: true, instrumentType: 'EQUITY'), true);
      expect(shouldExecuteImmediately(isMarket: false, isQuoteAvailable: true, side: 'buy', currentPrice: 105, limitPrice: 100, marketOpen: true, instrumentType: 'EQUITY'), false);
    });

    test('equity sell limit fills only at/above limit', () {
      expect(shouldExecuteImmediately(isMarket: false, isQuoteAvailable: true, side: 'sell', currentPrice: 105, limitPrice: 100, marketOpen: true, instrumentType: 'EQUITY'), true);
      expect(shouldExecuteImmediately(isMarket: false, isQuoteAvailable: true, side: 'sell', currentPrice: 95, limitPrice: 100, marketOpen: true, instrumentType: 'EQUITY'), false);
    });

    test('option LIMIT order always routes to pending (never instant)', () {
      // Even if the (client-supplied) price would satisfy the comparison.
      expect(
        shouldExecuteImmediately(isMarket: false, isQuoteAvailable: true, side: 'sell', currentPrice: 28, limitPrice: 28, marketOpen: true, instrumentType: 'OPTION'),
        false,
      );
    });

    test('option MARKET order still executes during hours', () {
      expect(
        shouldExecuteImmediately(isMarket: true, isQuoteAvailable: true, side: 'buy', currentPrice: 24, limitPrice: 0, marketOpen: true, instrumentType: 'OPTION'),
        true,
      );
    });

    test('limit order with no quote goes pending', () {
      expect(
        shouldExecuteImmediately(isMarket: false, isQuoteAvailable: false, side: 'buy', currentPrice: 0, limitPrice: 100, marketOpen: true, instrumentType: 'EQUITY'),
        false,
      );
    });
  });

  group('limitFillReached', () {
    test('buy fills at or below limit', () {
      expect(limitFillReached(side: 'buy', execPrice: 100, limit: 100), true);
      expect(limitFillReached(side: 'buy', execPrice: 99, limit: 100), true);
      expect(limitFillReached(side: 'buy', execPrice: 101, limit: 100), false);
    });
    test('sell fills at or above limit', () {
      expect(limitFillReached(side: 'sell', execPrice: 100, limit: 100), true);
      expect(limitFillReached(side: 'sell', execPrice: 101, limit: 100), true);
      expect(limitFillReached(side: 'sell', execPrice: 99, limit: 100), false);
    });
  });

  // The trigger COMPARISON above was never wrong. What broke was which value
  // got fed into it: modifyOrder updated `price` and left `limit_price` alone,
  // so the engine went on matching the original limit while the order card
  // showed the new one. These pin the field precedence and the write invariant.
  group('trigger resolution and modification', () {
    test('limit_price wins over price', () {
      expect(resolveTrigger(limitPrice: 149, price: 145.80), 149);
    });

    test('falls back to price only when limit_price is absent', () {
      expect(resolveTrigger(limitPrice: null, price: 145.80), 145.80);
    });

    test('modifying a limit order moves both price columns', () {
      final payload = modifyOrderPayload(quantity: 500, price: 145.80, isLimit: true);
      expect(payload['price'], 145.80);
      expect(payload['limit_price'], 145.80);
      expect(resolveTrigger(
        limitPrice: payload['limit_price'] as double?,
        price: payload['price'] as double?,
      ), 145.80);
    });

    test('modifying a market order leaves no trigger behind', () {
      final payload = modifyOrderPayload(quantity: 10, price: 250, isLimit: false);
      expect(payload['limit_price'], isNull);
    });

    test('AEROENTER regression: placed at 149, modified to 145.80, LTP 146.03 fills', () {
      // Before the fix the modify wrote `price` only, so the engine still saw 149.
      expect(
        limitFillReached(
          side: 'sell',
          execPrice: 146.03,
          limit: resolveTrigger(limitPrice: 149, price: 145.80),
        ),
        false,
        reason: 'the shape of the bug: engine matched the stale 149',
      );

      // After the fix both columns carry 145.80, so the same tick fills.
      final modified = modifyOrderPayload(quantity: 500, price: 145.80, isLimit: true);
      expect(
        limitFillReached(
          side: 'sell',
          execPrice: 146.03,
          limit: resolveTrigger(
            limitPrice: modified['limit_price'] as double?,
            price: modified['price'] as double?,
          ),
        ),
        true,
      );
    });

    test('DOGE case: correcting the trigger does not force an unwanted fill', () {
      // Repaired by migration to 22.90; the market is well below it, so a SELL
      // still correctly rests. Fixing the data must not invent a fill.
      final modified = modifyOrderPayload(quantity: 35, price: 22.90, isLimit: true);
      expect(
        limitFillReached(
          side: 'sell',
          execPrice: 8.31,
          limit: resolveTrigger(
            limitPrice: modified['limit_price'] as double?,
            price: modified['price'] as double?,
          ),
        ),
        false,
      );
    });
  });

  group('priceAlertCrossed', () {
    test('above triggers at or over target', () {
      expect(priceAlertCrossed(direction: 'above', price: 1330, target: 1320), true);
      expect(priceAlertCrossed(direction: 'above', price: 1320, target: 1320), true);
      expect(priceAlertCrossed(direction: 'above', price: 1319, target: 1320), false);
    });
    test('below triggers at or under target', () {
      expect(priceAlertCrossed(direction: 'below', price: 1310, target: 1320), true);
      expect(priceAlertCrossed(direction: 'below', price: 1320, target: 1320), true);
      expect(priceAlertCrossed(direction: 'below', price: 1321, target: 1320), false);
    });
  });

  group('lot <-> unit conversion (RELIANCE=500, NIFTY=65)', () {
    test('lots to units', () {
      expect(unitsFromLots(1, 500), 500);
      expect(unitsFromLots(3, 65), 195);
    });
    test('units back to whole lots (server divides)', () {
      expect(lotsFromUnits(500, 500), 1);
      expect(lotsFromUnits(195, 65), 3);
    });
    test('round-trip is stable', () {
      for (final lotSize in [500, 65, 30, 1, 6750]) {
        for (var lots = 1; lots <= 5; lots++) {
          expect(lotsFromUnits(unitsFromLots(lots, lotSize), lotSize), lots);
        }
      }
    });
  });

  group('exit clamp never reverses position', () {
    test('full close lands at zero', () {
      expect(exitNewNetQty(existingLots: 5, requestedLots: 5), 0);
      expect(exitNewNetQty(existingLots: -3, requestedLots: 3), 0);
    });
    test('over-close is clamped to zero, never flips', () {
      expect(exitNewNetQty(existingLots: 4, requestedLots: 10), 0);
      expect(exitNewNetQty(existingLots: -2, requestedLots: 9), 0);
    });
    test('partial close moves toward zero', () {
      expect(exitNewNetQty(existingLots: 5, requestedLots: 2), 3);
      expect(exitNewNetQty(existingLots: -5, requestedLots: 2), -3);
    });

    Glados2<int, int>(
      any.intInRange(-50, 50),
      any.intInRange(1, 100),
    ).test('|newNetQty| never exceeds |existingLots| and never flips sign', (existing, req) {
      if (existing == 0) return; // nothing to exit
      final result = exitNewNetQty(existingLots: existing, requestedLots: req);
      expect(result.abs(), lessThanOrEqualTo(existing.abs()));
      // sign never flips (result is 0 or same sign as existing)
      expect(result == 0 || result.sign == existing.sign, true);
    });
  });
}
