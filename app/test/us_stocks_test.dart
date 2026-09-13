// Checks for US equity support: session windows across daylight saving, and the
// currency rules that decide when a figure is dollars and when it is rupees.
//
// The DST boundary maths and the "which currency?" decision are the two things
// that fail silently and expensively — a wrong offset fills orders while the US
// market is shut, and a mixed-currency figure is off by ~88x. Both are pure
// functions, so both get pinned here.

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/market_hours.dart';
import 'package:mobile/core/money.dart';
import 'package:mobile/services/currency_service.dart';
import 'package:mobile/core/currency.dart';
import 'package:mobile/models/order.dart';
import 'package:mobile/models/portfolio.dart';


/// Minimal stand-in so formatting can be checked without network or storage.
class FakeCurrencyService extends CurrencyService {
  FakeCurrencyService(this._currency, this._rate) : super.forTesting();
  final Currency _currency;
  final double _rate;
  @override
  Currency get displayCurrency => _currency;
  @override
  double get usdInr => _rate;
}

/// A UTC instant, for readability at the call sites below.
DateTime utc(int y, int m, int d, [int h = 0, int min = 0]) =>
    DateTime.utc(y, m, d, h, min);

Holding _usHolding({
  double quantity = 10,
  double nativeAvg = 100,
  double nativeNow = 110,
  double nativePrev = 105,
  double fx = 88,
}) =>
    Holding(
      symbol: 'AAPL',
      name: 'Apple',
      market: MarketHours.usStock,
      quantity: quantity,
      // INR mirrors, as the engine would have stored them.
      avgPrice: nativeAvg * fx,
      currentPrice: nativeNow * fx,
      previousClose: nativePrev * fx,
      invested: nativeAvg * fx * quantity,
      current: nativeNow * fx * quantity,
      pnl: (nativeNow - nativeAvg) * fx * quantity,
      pnlPct: ((nativeNow - nativeAvg) / nativeAvg) * 100,
      dayPnl: (nativeNow - nativePrev) * fx * quantity,
      dayPnlPct: 0,
      nativeAvgPrice: nativeAvg,
      nativeCurrentPrice: nativeNow,
      nativePreviousClose: nativePrev,
      nativeCurrency: 'USD',
    );

Holding _inrHolding() => Holding(
      symbol: 'RELIANCE',
      name: 'Reliance',
      market: 'stock',
      quantity: 5,
      avgPrice: 1000,
      currentPrice: 1100,
      previousClose: 1050,
      invested: 5000,
      current: 5500,
      pnl: 500,
      pnlPct: 10,
      dayPnl: 250,
      dayPnlPct: 5,
    );

void main() {
  group('US daylight saving boundaries', () {
    test('2026: DST runs 8 March to 1 November', () {
      // Second Sunday of March 2026 is the 8th; switchover at 07:00 UTC.
      expect(MarketHours.isUsDst(utc(2026, 3, 8, 6, 59)), isFalse);
      expect(MarketHours.isUsDst(utc(2026, 3, 8, 7, 0)), isTrue);
      // First Sunday of November 2026 is the 1st; switchover at 06:00 UTC.
      expect(MarketHours.isUsDst(utc(2026, 11, 1, 5, 59)), isTrue);
      expect(MarketHours.isUsDst(utc(2026, 11, 1, 6, 0)), isFalse);
    });

    test('deep winter and deep summer land on the right side', () {
      expect(MarketHours.isUsDst(utc(2026, 1, 15, 12)), isFalse);
      expect(MarketHours.isUsDst(utc(2026, 7, 15, 12)), isTrue);
      expect(MarketHours.isUsDst(utc(2026, 12, 25, 12)), isFalse);
    });

    test('offset follows DST: EDT is UTC-4, EST is UTC-5', () {
      // 17:00 UTC in July is 13:00 EDT.
      expect(MarketHours.usEastern(utc(2026, 7, 15, 17)).hour, 13);
      // 17:00 UTC in January is 12:00 EST.
      expect(MarketHours.usEastern(utc(2026, 1, 15, 17)).hour, 12);
    });
  });

  group('US session window', () {
    test('EDT: open 13:30-20:00 UTC', () {
      // Wednesday 15 July 2026.
      expect(MarketHours.isOpen(MarketHours.usStock, at: utc(2026, 7, 15, 13, 29)), isFalse);
      expect(MarketHours.isOpen(MarketHours.usStock, at: utc(2026, 7, 15, 13, 30)), isTrue);
      expect(MarketHours.isOpen(MarketHours.usStock, at: utc(2026, 7, 15, 19, 59)), isTrue);
      expect(MarketHours.isOpen(MarketHours.usStock, at: utc(2026, 7, 15, 20, 0)), isFalse);
    });

    test('EST: open 14:30-21:00 UTC', () {
      // Thursday 15 January 2026.
      expect(MarketHours.isOpen(MarketHours.usStock, at: utc(2026, 1, 15, 14, 29)), isFalse);
      expect(MarketHours.isOpen(MarketHours.usStock, at: utc(2026, 1, 15, 14, 30)), isTrue);
      expect(MarketHours.isOpen(MarketHours.usStock, at: utc(2026, 1, 15, 20, 59)), isTrue);
      expect(MarketHours.isOpen(MarketHours.usStock, at: utc(2026, 1, 15, 21, 0)), isFalse);
    });

    test('closed at the weekend in US Eastern terms', () {
      // Saturday 18 July 2026, mid-session clock time.
      expect(MarketHours.isOpen(MarketHours.usStock, at: utc(2026, 7, 18, 15)), isFalse);
      expect(MarketHours.isOpen(MarketHours.usStock, at: utc(2026, 7, 19, 15)), isFalse);
    });

    test('Friday late session is still Friday in ET, not Saturday', () {
      // 19:00 UTC Friday = 15:00 EDT Friday, i.e. open. In IST it is already
      // past midnight on Saturday, which is exactly the trap this guards.
      final friday = utc(2026, 7, 17, 19);
      expect(friday.weekday, DateTime.friday);
      expect(MarketHours.isOpen(MarketHours.usStock, at: friday), isTrue);
    });

    test('does not disturb the Indian or crypto windows', () {
      // 10:00 UTC Wednesday = 15:30 IST, just after the Indian close.
      expect(MarketHours.isOpen('stock', at: utc(2026, 7, 15, 10)), isFalse);
      // 06:00 UTC = 11:30 IST, mid-session.
      expect(MarketHours.isOpen('stock', at: utc(2026, 7, 15, 6)), isTrue);
      expect(MarketHours.isOpen('crypto', at: utc(2026, 7, 19, 3)), isTrue);
    });

    test('session labels shift with DST', () {
      expect(MarketHours.sessionLabel(MarketHours.usStock, at: utc(2026, 7, 15)),
          contains('7:00 PM'));
      expect(MarketHours.sessionLabel(MarketHours.usStock, at: utc(2026, 1, 15)),
          contains('8:00 PM'));
      expect(MarketHours.sessionLabel('stock'), contains('9:15 AM'));
      expect(MarketHours.sessionLabel('crypto'), '24/7');
    });
  });

  group('Money with an INR display preference', () {
    setUp(() {
      // Default view: rupees, so nothing is converted.
      Money.serviceForTesting(FakeCurrencyService(Currency.inr, 88));
    });

    test('source currency follows the market, not the preference', () {
      expect(Money.sourceFor(MarketHours.usStock), Currency.usd);
      expect(Money.sourceFor('stock'), Currency.inr);
      expect(Money.sourceFor('crypto'), Currency.inr);
      expect(Money.sourceFor(null), Currency.inr);
    });

    test('an Indian price stays as-is', () {
      expect(Money.instrument(1234.5, market: 'stock'), '\u20b91234.50');
    });

    test('a US price is converted into rupees', () {
      // 100 USD at 88 -> 8800 INR.
      expect(Money.instrument(100, market: MarketHours.usStock), '\u20b98800.00');
    });

    test('wallet figures render in rupees unchanged', () {
      expect(Money.wallet(5000), '\u20b95000');
      expect(Money.signedWallet(-250.5), '-\u20b9250.50');
      expect(Money.signedWallet(250.5), '+\u20b9250.50');
    });

    test('nothing is flagged as converted', () {
      expect(Money.isConverted, isFalse);
      expect(Money.conversionNote(), isNull);
      // A US instrument still differs from the wallet currency.
      expect(Money.differsFromWallet('stock'), isFalse);
      expect(Money.differsFromWallet(MarketHours.usStock), isTrue);
    });
  });

  group('Money with a USD display preference', () {
    setUp(() {
      Money.serviceForTesting(FakeCurrencyService(Currency.usd, 88));
    });

    test('every market renders in dollars', () {
      // This is the whole point of the preference: an Indian stock shows in USD.
      expect(Money.instrument(8800, market: 'stock'), '\u0024100.00');
      expect(Money.instrument(8800, market: 'crypto'), '\u0024100.00');
      // A US price is already USD, so it passes through untouched.
      expect(Money.instrument(100, market: MarketHours.usStock), '\u0024100.00');
    });

    test('the wallet is converted too', () {
      expect(Money.wallet(8800, decimals: 2), '\u0024100.00');
      expect(Money.signedWallet(-8800), '-\u0024100.00');
    });

    test('reports that figures are converted, and at what rate', () {
      expect(Money.isConverted, isTrue);
      expect(Money.rate, 88);
      expect(Money.conversionNote(), contains('88.00'));
      expect(Money.differsFromWallet('stock'), isTrue);
    });

    test('the real rupee charge is recoverable for any market', () {
      // An Indian stock priced 8800 INR costs 8800 INR whatever we display.
      expect(Money.inrValueOf(8800, market: 'stock'), closeTo(8800, 1e-9));
      // A US stock priced 100 USD costs 8800 INR.
      expect(Money.inrValueOf(100, market: MarketHours.usStock), closeTo(8800, 1e-9));
      expect(Money.walletChargeInr(8800), '\u20b98800.00');
    });

    test('quantity precision is unaffected by currency', () {
      expect(Money.quantity(1.23456789, market: 'crypto'), '1.2346');
      expect(Money.quantity(10, market: MarketHours.usStock), '10');
    });
  });

  group('FxConverter', () {
    test('round-trips a value', () {
      const fx = FxConverter(usdInr: 88);
      final usd = fx.convert(8800, from: Currency.inr, to: Currency.usd);
      expect(usd, closeTo(100, 1e-9));
      expect(fx.convert(usd, from: Currency.usd, to: Currency.inr), closeTo(8800, 1e-9));
    });

    test('same currency is a no-op', () {
      const fx = FxConverter(usdInr: 88);
      expect(fx.convert(123.45, from: Currency.inr, to: Currency.inr), 123.45);
    });

    test('an unusable rate leaves the value alone rather than zeroing it', () {
      for (final bad in [0.0, -1.0, double.nan, double.infinity]) {
        final fx = FxConverter(usdInr: bad);
        expect(fx.isUsable, isFalse, reason: 'rate $bad should be unusable');
        expect(fx.convert(500, from: Currency.inr, to: Currency.usd), 500);
      }
    });
  });

  group('Currency', () {
    test('parses codes and defaults to rupees', () {
      expect(Currency.fromCode('USD'), Currency.usd);
      expect(Currency.fromCode('usd'), Currency.usd);
      expect(Currency.fromCode('INR'), Currency.inr);
      expect(Currency.fromCode(null), Currency.inr);
      expect(Currency.fromCode('GBP'), Currency.inr);
    });
  });


  group('Typed input converts back to the instrument currency', () {
    // The dangerous direction: a figure the user typed must reach the order
    // engine in the instrument's own currency, never in the display currency.
    test('viewing rupees leaves everything alone', () {
      Money.serviceForTesting(FakeCurrencyService(Currency.inr, 88));
      expect(Money.fromDisplay(1500, market: 'stock'), closeTo(1500, 1e-9));
      expect(Money.fromDisplay(1500, market: 'crypto'), closeTo(1500, 1e-9));
      // A US instrument is still dollars, so a rupee-typed figure converts.
      expect(Money.fromDisplay(8800, market: MarketHours.usStock), closeTo(100, 1e-9));
      expect(Money.typedToInr(1500), closeTo(1500, 1e-9));
    });

    test('viewing dollars converts a typed figure into the native currency', () {
      Money.serviceForTesting(FakeCurrencyService(Currency.usd, 88));
      // Typed \$100 on an Indian stock is Rs 8800 to the engine.
      expect(Money.fromDisplay(100, market: 'stock'), closeTo(8800, 1e-9));
      expect(Money.fromDisplay(100, market: 'crypto'), closeTo(8800, 1e-9));
      // Typed \$100 on a US stock is already dollars.
      expect(Money.fromDisplay(100, market: MarketHours.usStock), closeTo(100, 1e-9));
      // Wallet comparisons are always rupees.
      expect(Money.typedToInr(100), closeTo(8800, 1e-9));
    });

    test('display and typed conversions are exact inverses', () {
      for (final currency in Currency.values) {
        Money.serviceForTesting(FakeCurrencyService(currency, 88));
        for (final market in ['stock', 'crypto', MarketHours.usStock]) {
          const native = 1234.56;
          final shown = Money.toDisplay(native, from: Money.sourceFor(market));
          final back = Money.fromDisplay(shown, market: market);
          expect(back, closeTo(native, 1e-6),
              reason: 'round trip failed for \$currency / \$market');
        }
      }
    });

    test('an amount-to-invest yields the same quantity in either currency', () {
      // Buying "100 dollars worth" and "8800 rupees worth" of the same coin must
      // produce the same quantity, or order sizing depends on a display setting.
      Money.serviceForTesting(FakeCurrencyService(Currency.inr, 88));
      final priceInr = 8800.0; // 1 unit costs Rs 8800
      final qtyFromInr = Money.fromDisplay(8800, market: 'crypto') / priceInr;

      Money.serviceForTesting(FakeCurrencyService(Currency.usd, 88));
      final qtyFromUsd = Money.fromDisplay(100, market: 'crypto') / priceInr;

      expect(qtyFromUsd, closeTo(qtyFromInr, 1e-9));
      expect(qtyFromUsd, closeTo(1.0, 1e-9));
    });

    test('no rate means a typed figure passes through untouched', () {
      // Better to treat the input as native than to multiply by zero.
      Money.serviceForTesting(FakeCurrencyService(Currency.usd, 0));
      expect(Money.fromDisplay(100, market: 'stock'), 100);
      expect(Money.typedToInr(100), 100);
    });
  });


  group('Alert target round-trips through the display currency', () {
    // Regression: the alert sheet typed in the display currency but saved the
    // raw number, so a dollar-viewing user set a target ~88x too low, and the
    // above/below direction flipped the wrong way.
    test('a typed target is stored in the instrument currency', () {
      Money.serviceForTesting(FakeCurrencyService(Currency.usd, 88));
      // User views dollars and types 20 for an Indian stock trading at Rs 1310.
      final stored = Money.fromDisplay(20, market: 'stock');
      expect(stored, closeTo(1760, 1e-9));
      // Stored value compares sensibly against the native price.
      expect(stored > 1310, isTrue, reason: 'should be an "above" alert');
      // And reads back as the same dollar figure the user entered.
      expect(Money.instrument(stored, market: 'stock'), '\u002420.00');
    });

    test('direction is decided on like-for-like currencies', () {
      Money.serviceForTesting(FakeCurrencyService(Currency.usd, 88));
      const nativePrice = 1310.0; // Rs 1310
      // Typing 10 dollars = Rs 880, which is BELOW the current price.
      expect(Money.fromDisplay(10, market: 'stock') >= nativePrice, isFalse);
      // Typing 20 dollars = Rs 1760, which is ABOVE it.
      expect(Money.fromDisplay(20, market: 'stock') >= nativePrice, isTrue);
    });

    test('a prefilled limit price survives a round trip', () {
      // The field is written with Money.bare and read with Money.fromDisplay;
      // those two must cancel out or the prefill becomes a wrong order.
      for (final currency in Currency.values) {
        Money.serviceForTesting(FakeCurrencyService(currency, 88));
        for (final market in ['stock', 'crypto', MarketHours.usStock]) {
          const native = 1310.45;
          final shown = Money.bare(native, from: Money.sourceFor(market));
          final back = Money.fromDisplay(double.parse(shown), market: market);
          expect(back, closeTo(native, 0.5),
              reason: 'prefill round trip broke for \$currency / \$market');
        }
      }
    });
  });

  group('Holding native-currency view', () {
    setUp(() => Money.serviceForTesting(FakeCurrencyService(Currency.inr, 88)));

    test('a US position reports cost, value and P&L in dollars', () {
      final h = _usHolding(quantity: 10, nativeAvg: 100, nativeNow: 110);
      expect(h.isNativeCurrency, isTrue);
      expect(h.displayAvgPrice, 100);
      expect(h.displayCurrentPrice, 110);
      expect(h.displayInvested, 1000);
      expect(h.displayCurrent, 1100);
      expect(h.displayPnl, 100);
      expect(h.displayPnlPct, closeTo(10, 0.001));
    });

    test('day P&L uses the native previous close', () {
      final h = _usHolding(quantity: 10, nativeNow: 110, nativePrev: 105);
      expect(h.displayDayPnl, closeTo(50, 0.001));
    });

    test('a short US position reports a loss when price rises', () {
      final h = _usHolding(quantity: -10, nativeAvg: 100, nativeNow: 110);
      expect(h.displayPnl, closeTo(-100, 0.001));
      // Invested is always a positive basis figure.
      expect(h.displayInvested, 1000);
    });

    test('percentage is currency independent', () {
      final h = _usHolding(nativeAvg: 100, nativeNow: 110, fx: 88);
      final other = _usHolding(nativeAvg: 100, nativeNow: 110, fx: 70);
      expect(h.displayPnlPct, closeTo(other.displayPnlPct, 1e-9));
    });

    test('INR holdings keep using the rupee figures unchanged', () {
      final h = _inrHolding();
      expect(h.isNativeCurrency, isFalse);
      expect(h.displayAvgPrice, 1000);
      expect(h.displayCurrentPrice, 1100);
      expect(h.displayInvested, 5000);
      expect(h.displayCurrent, 5500);
      expect(h.displayPnl, 500);
      expect(h.displayPnlPct, 10);
      expect(h.displayDayPnl, 250);
    });

    test('survives a missing quote without inventing a rate', () {
      final h = Holding(
        symbol: 'AAPL',
        name: 'Apple',
        market: MarketHours.usStock,
        quantity: 4,
        avgPrice: 8800,
        currentPrice: 8800,
        previousClose: 8800,
        invested: 35200,
        current: 35200,
        pnl: 0,
        pnlPct: 0,
        dayPnl: 0,
        dayPnlPct: 0,
        nativeAvgPrice: 100,
        nativeCurrency: 'USD',
      );
      // No native current price: falls back to the INR field rather than
      // throwing, and the position reads flat.
      expect(h.displayCurrentPrice, 8800);
      expect(h.displayDayPnl, 0);
    });
  });

  group('Order native-currency view', () {
    Order order({double? nativePrice, String? nativeCurrency, double price = 8800}) => Order(
          id: 'o1',
          symbol: 'AAPL',
          name: 'Apple',
          market: MarketHours.usStock,
          side: 'buy',
          quantity: 3,
          price: price,
          total: price * 3,
          nativePrice: nativePrice,
          nativeCurrency: nativeCurrency,
        );

    test('executed US order shows the dollar price, not the rupee one', () {
      final o = order(nativePrice: 100, nativeCurrency: 'USD', price: 8800);
      expect(o.isNativeCurrency, isTrue);
      expect(o.displayPrice, 100);
      expect(o.displayTotal, 300);
      // The INR figures remain available for the wallet view.
      expect(o.price, 8800);
      expect(o.total, 26400);
    });

    test('pending US order reads its USD price straight from price', () {
      // Before the fill the engine has not converted, so price is already USD
      // and native_price is set at placement to the same value.
      final o = order(nativePrice: 100, nativeCurrency: 'USD', price: 100);
      expect(o.displayPrice, 100);
      expect(o.displayTotal, 300);
    });

    test('INR order is unaffected', () {
      final o = Order(
        id: 'o2',
        symbol: 'RELIANCE',
        name: 'Reliance',
        market: 'stock',
        side: 'buy',
        quantity: 2,
        price: 1500,
        total: 3000,
      );
      expect(o.isNativeCurrency, isFalse);
      expect(o.displayPrice, 1500);
      expect(o.displayTotal, 3000);
    });

    test('parses the new columns from a database row', () {
      final o = Order.fromJson({
        'id': 'x',
        'symbol': 'AAPL',
        'market': 'us_stock',
        'side': 'buy',
        'quantity': 2,
        'price': 17600,
        'total': 35200,
        'native_price': 200,
        'native_currency': 'USD',
        'fx_rate': 88,
      });
      expect(o.nativePrice, 200);
      expect(o.fxRate, 88);
      expect(o.displayPrice, 200);
      expect(o.displayTotal, 400);
      // Sanity: the INR total really is the native total times the rate.
      expect(o.total, closeTo(o.displayTotal * o.fxRate!, 0.01));
    });
  });
}
