// Full-coverage tests for the TRADE MONEY MECHANICS that must never regress:
// long & short for equity, crypto, futures and options — opening, adding,
// reducing, closing/exiting, and reversing — checking the exact wallet impact
// (money in vs out), margin block/release, average price, and realised P&L.
//
// Following this project's pattern, the production money rules are ported here
// EXACTLY as they exist in supabase_service.dart (_placeOrderLocal) and the
// execute-pending-orders engine, then exercised deterministically and with
// property-based invariants. If a future edit flips a sign or breaks the margin
// model (e.g. shorting credits instead of debits), a test here fails and names
// the broken case.
//
// Key model (matches the implementation):
//  • Equity/Crypto margin = 100% of notional (marginPct = 1.0).
//    - OPEN long  : wallet -= qty*price            (money OUT)
//    - OPEN short : wallet -= qty*price (margin)    (money OUT)  ← regressed before
//    - CLOSE long : wallet += qty*price             (money IN)
//    - COVER short: wallet += releasedMargin + pnl  (money IN, never blocked)
//      releasedMargin = coverQty*avg ; pnl = (avg - price)*coverQty
//  • Futures/Options margin = 15% of notional; option BUYER pays full premium,
//    option SELLER blocks 15% margin and receives premium.

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:glados/glados.dart' hide test, group, expect;

// ── Reference account state ─────────────────────────────────────────────────
class Pos {
  double qty;
  double avg;
  Pos(this.qty, this.avg);
}

class FoPos {
  double netQty; // in lots
  double avg;
  double margin;
  FoPos(this.netQty, this.avg, this.margin);
}

class Acct {
  double wallet;
  double realized = 0;
  final Map<String, Pos> eq = {};
  final Map<String, FoPos> fo = {};
  Acct(this.wallet);
}

// ── Equity/Crypto engine (faithful port of the fixed margin model) ──────────
void equityTrade(Acct a, String key, String side, double qty, double price,
    {double charges = 0}) {
  final total = price * qty;
  final ex = a.eq[key];
  final oq = ex?.qty ?? 0.0;
  final oa = ex?.avg ?? 0.0;

  if (side == 'buy') {
    if (oq < 0) {
      // Cover short (+ optionally open a long with the surplus).
      final coverQty = qty > -oq ? -oq : qty;
      final remainingBuy = qty - coverQty;
      final releasedMargin = coverQty * oa;
      final pnl = (oa - price) * coverQty;
      a.wallet += releasedMargin + pnl - charges; // money IN
      a.realized += pnl - charges;
      final newQty = oq + coverQty;
      if (newQty.abs() < 1e-9) {
        a.eq.remove(key);
      } else {
        a.eq[key] = Pos(newQty, oa);
      }
      if (remainingBuy > 0) {
        a.wallet -= remainingBuy * price;
        a.eq[key] = Pos(remainingBuy, price);
      }
    } else {
      // New long or add to long.
      a.wallet -= total + charges; // money OUT
      final newQty = oq + qty;
      final newAvg = oq > 0 ? (oa * oq + price * qty) / newQty : price;
      a.eq[key] = Pos(newQty, newAvg);
    }
  } else {
    if (oq > 0) {
      // Close/reduce long (+ optionally open a short with the surplus).
      final sellQty = qty > oq ? oq : qty;
      final remainingSell = qty - sellQty;
      final pnl = (price - oa) * sellQty;
      a.wallet += sellQty * price - charges; // money IN
      a.realized += pnl - charges;
      final newQty = oq - sellQty;
      if (newQty.abs() < 1e-9) {
        a.eq.remove(key);
      } else {
        a.eq[key] = Pos(newQty, oa);
      }
      if (remainingSell > 0) {
        a.wallet -= remainingSell * price; // margin for the new short
        a.eq[key] = Pos(-remainingSell, price);
      }
    } else {
      // New short or add to short — BLOCK margin (money OUT).
      a.wallet -= total + charges;
      final newQty = oq - qty;
      final oqAbs = oq.abs();
      final newAvg =
          (oqAbs + qty) > 0 ? (oa * oqAbs + price * qty) / (oqAbs + qty) : price;
      a.eq[key] = Pos(newQty, newAvg);
    }
  }
}

// ── F&O engine (faithful port; 15% margin; option buyer pays premium) ───────
void foTrade(Acct a, String key, String itype, String side, double lots,
    double price, double lotSize,
    {double charges = 0}) {
  final sign = side == 'buy' ? 1.0 : -1.0;
  final ex = a.fo[key];
  final existingQty = ex?.netQty ?? 0.0;
  final existingAvg = ex?.avg ?? 0.0;
  final oldMargin = ex?.margin ?? 0.0;
  final newNetQty = existingQty + lots * sign;
  final isOption = itype == 'OPTION';
  double newAvg = 0, walletDebit = 0, walletCredit = 0, marginBlocked = 0, realizedPnl = 0;

  if (existingQty == 0 || existingQty * sign > 0) {
    newAvg = existingQty == 0
        ? price
        : (existingAvg * existingQty.abs() + price * lots) / (existingQty.abs() + lots);
    if (isOption && newNetQty > 0) {
      marginBlocked = 0;
      walletDebit = price * lots * lotSize;
    } else if (isOption && newNetQty < 0) {
      marginBlocked = newAvg * newNetQty.abs() * lotSize * 0.15;
      final delta = marginBlocked - oldMargin;
      final prem = price * lots * lotSize;
      if (prem >= delta) {
        walletCredit = prem - delta;
      } else {
        walletDebit = delta - prem;
      }
    } else {
      marginBlocked = newAvg * newNetQty.abs() * lotSize * 0.15;
      walletDebit = marginBlocked - oldMargin;
    }
  } else {
    newAvg = existingAvg;
    final closedLots = lots.abs() > existingQty.abs() ? existingQty.abs() : lots.abs();
    final remainingLots = lots.abs() - closedLots;
    realizedPnl =
        (existingQty > 0 ? (price - existingAvg) : (existingAvg - price)) * closedLots * lotSize;
    if (newNetQty == 0) {
      marginBlocked = 0;
      if (isOption && existingQty > 0) {
        walletCredit = price * closedLots * lotSize;
      } else if (isOption && existingQty < 0) {
        final ni = oldMargin - price * closedLots * lotSize;
        if (ni >= 0) {
          walletCredit = ni;
        } else {
          walletDebit = ni.abs();
        }
      } else {
        final ni = oldMargin + realizedPnl;
        if (ni >= 0) {
          walletCredit = ni;
        } else {
          walletDebit = ni.abs();
        }
      }
    } else if (newNetQty * existingQty > 0) {
      if (isOption && existingQty > 0) {
        marginBlocked = 0;
        walletCredit = price * closedLots * lotSize;
      } else if (isOption && existingQty < 0) {
        marginBlocked = newAvg * newNetQty.abs() * lotSize * 0.15;
        final rel = oldMargin - marginBlocked;
        final ni = rel - price * closedLots * lotSize;
        if (ni >= 0) {
          walletCredit = ni;
        } else {
          walletDebit = ni.abs();
        }
      } else {
        marginBlocked = newAvg * newNetQty.abs() * lotSize * 0.15;
        final rel = oldMargin - marginBlocked;
        final ni = rel + realizedPnl;
        if (ni >= 0) {
          walletCredit = ni;
        } else {
          walletDebit = ni.abs();
        }
      }
    } else {
      double closedNI;
      if (isOption && existingQty > 0) {
        closedNI = price * closedLots * lotSize;
      } else if (isOption && existingQty < 0) {
        closedNI = oldMargin - price * closedLots * lotSize;
      } else {
        closedNI = oldMargin + realizedPnl;
      }
      newAvg = price;
      double openD = 0, openC = 0;
      if (isOption && newNetQty > 0) {
        marginBlocked = 0;
        openD = price * remainingLots * lotSize;
      } else if (isOption && newNetQty < 0) {
        marginBlocked = newAvg * newNetQty.abs() * lotSize * 0.15;
        final prem = price * remainingLots * lotSize;
        if (prem >= marginBlocked) {
          openC = prem - marginBlocked;
        } else {
          openD = marginBlocked - prem;
        }
      } else {
        marginBlocked = newAvg * newNetQty.abs() * lotSize * 0.15;
        openD = marginBlocked;
      }
      final ni = closedNI + openC - openD;
      if (ni >= 0) {
        walletCredit = ni;
      } else {
        walletDebit = ni.abs();
      }
    }
  }

  double finalDebit = walletDebit, finalCredit = walletCredit;
  if (charges > 0) {
    if (walletCredit >= charges) {
      finalCredit = walletCredit - charges;
    } else {
      finalCredit = 0;
      finalDebit = walletDebit + (charges - walletCredit);
    }
  }
  a.wallet += finalCredit - finalDebit;
  a.realized += realizedPnl - charges;
  if (newNetQty.abs() < 1e-9) {
    a.fo.remove(key);
  } else {
    a.fo[key] = FoPos(newNetQty, newAvg, marginBlocked);
  }
}

const double _eps = 1e-6;

void main() {
  group('EQUITY/CRYPTO — long lifecycle', () {
    test('buy long: money OUT, position opened', () {
      final a = Acct(100000);
      equityTrade(a, 'RELI', 'buy', 10, 100); // -1000
      expect(a.wallet, closeTo(99000, _eps));
      expect(a.eq['RELI']!.qty, 10);
      expect(a.eq['RELI']!.avg, closeTo(100, _eps));
    });

    test('add to long: weighted average, more money OUT', () {
      final a = Acct(100000);
      equityTrade(a, 'RELI', 'buy', 10, 100); // 99000, avg 100
      equityTrade(a, 'RELI', 'buy', 10, 120); // -1200 -> 97800, avg 110
      expect(a.wallet, closeTo(97800, _eps));
      expect(a.eq['RELI']!.qty, 20);
      expect(a.eq['RELI']!.avg, closeTo(110, _eps));
    });

    test('sell to close long at PROFIT: money IN, pnl positive, position gone', () {
      final a = Acct(100000);
      equityTrade(a, 'RELI', 'buy', 10, 100); // 99000
      equityTrade(a, 'RELI', 'sell', 10, 130); // +1300 -> 100300
      expect(a.wallet, closeTo(100300, _eps));
      expect(a.realized, closeTo(300, _eps)); // (130-100)*10
      expect(a.eq.containsKey('RELI'), false);
    });

    test('partial sell long: reduces qty, keeps avg', () {
      final a = Acct(100000);
      equityTrade(a, 'RELI', 'buy', 10, 100); // 99000
      equityTrade(a, 'RELI', 'sell', 4, 110); // +440 -> 99440
      expect(a.wallet, closeTo(99440, _eps));
      expect(a.eq['RELI']!.qty, 6);
      expect(a.eq['RELI']!.avg, closeTo(100, _eps));
      expect(a.realized, closeTo(40, _eps)); // (110-100)*4
    });

    test('long round-trip at same price returns wallet exactly (no charges)', () {
      final a = Acct(100000);
      equityTrade(a, 'X', 'buy', 7, 250);
      equityTrade(a, 'X', 'sell', 7, 250);
      expect(a.wallet, closeTo(100000, _eps));
      expect(a.eq.isEmpty, true);
    });
  });

  group('EQUITY/CRYPTO — short lifecycle (the regression area)', () {
    test('open short: money OUT (margin blocked), NOT credited', () {
      final a = Acct(100000);
      equityTrade(a, 'BNB', 'sell', 1, 55000); // short -> -55000 margin
      expect(a.wallet, closeTo(45000, _eps)); // money went OUT
      expect(a.eq['BNB']!.qty, -1);
      expect(a.eq['BNB']!.avg, closeTo(55000, _eps));
    });

    test('add to short: blocks more margin, weighted avg', () {
      final a = Acct(200000);
      equityTrade(a, 'BNB', 'sell', 1, 50000); // 150000
      equityTrade(a, 'BNB', 'sell', 1, 60000); // 90000, avg 55000
      expect(a.wallet, closeTo(90000, _eps));
      expect(a.eq['BNB']!.qty, -2);
      expect(a.eq['BNB']!.avg, closeTo(55000, _eps));
    });

    test('cover short at LOWER price = PROFIT (money back + gain)', () {
      final a = Acct(100000);
      equityTrade(a, 'BNB', 'sell', 1, 55000); // 45000
      equityTrade(a, 'BNB', 'buy', 1, 50000); // released 55000 + pnl 5000
      expect(a.wallet, closeTo(105000, _eps));
      expect(a.realized, closeTo(5000, _eps)); // (55000-50000)*1
      expect(a.eq.containsKey('BNB'), false);
    });

    test('cover short at HIGHER price = LOSS', () {
      final a = Acct(100000);
      equityTrade(a, 'BNB', 'sell', 1, 50000); // 50000
      equityTrade(a, 'BNB', 'buy', 1, 60000); // released 50000 + pnl -10000
      expect(a.wallet, closeTo(90000, _eps)); // net -10000 from start
      expect(a.realized, closeTo(-10000, _eps));
      expect(a.eq.containsKey('BNB'), false);
    });

    test('partial cover: reduces short, keeps avg', () {
      final a = Acct(300000);
      equityTrade(a, 'SOL', 'sell', 20, 6000); // -120000 -> 180000
      equityTrade(a, 'SOL', 'buy', 5, 5000); // released 5*6000=30000 + pnl (6000-5000)*5=5000
      expect(a.wallet, closeTo(215000, _eps));
      expect(a.eq['SOL']!.qty, -15);
      expect(a.eq['SOL']!.avg, closeTo(6000, _eps));
      expect(a.realized, closeTo(5000, _eps));
    });

    test('short round-trip at same price returns wallet exactly', () {
      final a = Acct(100000);
      equityTrade(a, 'X', 'sell', 3, 200); // -600
      equityTrade(a, 'X', 'buy', 3, 200); // +600
      expect(a.wallet, closeTo(100000, _eps));
      expect(a.eq.isEmpty, true);
    });

    test('crypto fractional short works', () {
      final a = Acct(100000);
      equityTrade(a, 'ETH', 'sell', 0.5, 200000); // -100000
      expect(a.wallet, closeTo(0, _eps));
      expect(a.eq['ETH']!.qty, closeTo(-0.5, _eps));
    });
  });

  group('EQUITY/CRYPTO — reversal (over-close) paths', () {
    test('sell more than long: closes long then opens short', () {
      final a = Acct(100000);
      equityTrade(a, 'X', 'buy', 10, 100); // long 10 @100, wallet 99000
      equityTrade(a, 'X', 'sell', 15, 120); // close 10 (+1200), open short 5 @120 (-600)
      expect(a.wallet, closeTo(99000 + 1200 - 600, _eps)); // 99600
      expect(a.eq['X']!.qty, -5);
      expect(a.eq['X']!.avg, closeTo(120, _eps));
      expect(a.realized, closeTo(200, _eps)); // (120-100)*10
    });

    test('buy more than short: covers short then opens long', () {
      final a = Acct(100000);
      equityTrade(a, 'X', 'sell', 10, 100); // short 10 @100, wallet 99000... (-1000)
      equityTrade(a, 'X', 'buy', 15, 90); // cover 10: released 1000 + pnl 100; open long 5 @90 (-450)
      // wallet: 99000 + 1000 + 100 - 450 = 99650
      expect(a.wallet, closeTo(99650, _eps));
      expect(a.eq['X']!.qty, 5);
      expect(a.eq['X']!.avg, closeTo(90, _eps));
      expect(a.realized, closeTo(100, _eps));
    });
  });

  group('EQUITY — charges direction', () {
    test('buy deducts charges on top of cost', () {
      final a = Acct(100000);
      equityTrade(a, 'R', 'buy', 10, 100, charges: 5);
      expect(a.wallet, closeTo(100000 - 1000 - 5, _eps));
    });
    test('open short deducts charges on top of margin', () {
      final a = Acct(100000);
      equityTrade(a, 'R', 'sell', 10, 100, charges: 5);
      expect(a.wallet, closeTo(100000 - 1000 - 5, _eps));
    });
    test('close long: charges reduce proceeds', () {
      final a = Acct(100000);
      equityTrade(a, 'R', 'buy', 10, 100);
      equityTrade(a, 'R', 'sell', 10, 110, charges: 5);
      expect(a.wallet, closeTo(99000 + 1100 - 5, _eps));
    });
  });

  group('FUTURES — long & short lifecycle (15% margin)', () {
    // lotSize 50, price 100 => notional 5000/lot, margin 750/lot
    test('buy future: blocks 15% margin (money OUT)', () {
      final a = Acct(100000);
      foTrade(a, 'NIFTYFUT', 'FUTURE', 'buy', 1, 100, 50); // margin 750
      expect(a.wallet, closeTo(99250, _eps));
      expect(a.fo['NIFTYFUT']!.netQty, 1);
      expect(a.fo['NIFTYFUT']!.margin, closeTo(750, _eps));
    });

    test('close long future at PROFIT: release margin + pnl', () {
      final a = Acct(100000);
      foTrade(a, 'F', 'FUTURE', 'buy', 1, 100, 50); // -750 -> 99250
      foTrade(a, 'F', 'FUTURE', 'sell', 1, 120, 50); // release 750 + pnl (120-100)*50=1000
      expect(a.wallet, closeTo(101000, _eps));
      expect(a.realized, closeTo(1000, _eps));
      expect(a.fo.containsKey('F'), false);
    });

    test('short future: blocks margin (money OUT); cover at lower = profit', () {
      final a = Acct(100000);
      foTrade(a, 'F', 'FUTURE', 'sell', 1, 100, 50); // margin 750 -> 99250
      expect(a.wallet, closeTo(99250, _eps));
      expect(a.fo['F']!.netQty, -1);
      foTrade(a, 'F', 'FUTURE', 'buy', 1, 90, 50); // release 750 + pnl (100-90)*50=500
      expect(a.wallet, closeTo(100500, _eps));
      expect(a.realized, closeTo(500, _eps));
    });

    test('future round-trip at same price returns wallet exactly', () {
      final a = Acct(100000);
      foTrade(a, 'F', 'FUTURE', 'buy', 2, 100, 50);
      foTrade(a, 'F', 'FUTURE', 'sell', 2, 100, 50);
      expect(a.wallet, closeTo(100000, _eps));
      expect(a.fo.isEmpty, true);
    });
  });

  group('OPTIONS — buyer (long) lifecycle', () {
    // lotSize 50, premium 20 => cost 1000/lot
    test('buy option: pays full premium (money OUT), no margin', () {
      final a = Acct(100000);
      foTrade(a, 'CE', 'OPTION', 'buy', 1, 20, 50); // -1000
      expect(a.wallet, closeTo(99000, _eps));
      expect(a.fo['CE']!.netQty, 1);
      expect(a.fo['CE']!.margin, closeTo(0, _eps));
    });

    test('sell-to-close long option at PROFIT: receive premium value', () {
      final a = Acct(100000);
      foTrade(a, 'CE', 'OPTION', 'buy', 1, 20, 50); // -1000 -> 99000
      foTrade(a, 'CE', 'OPTION', 'sell', 1, 35, 50); // +35*50=1750 (premium value back)
      expect(a.wallet, closeTo(100750, _eps));
      expect(a.realized, closeTo(750, _eps)); // (35-20)*50
      expect(a.fo.containsKey('CE'), false);
    });

    test('long option round-trip at same premium returns wallet exactly', () {
      final a = Acct(100000);
      foTrade(a, 'CE', 'OPTION', 'buy', 1, 20, 50);
      foTrade(a, 'CE', 'OPTION', 'sell', 1, 20, 50);
      expect(a.wallet, closeTo(100000, _eps));
    });
  });

  group('OPTIONS — seller (writer / short) lifecycle', () {
    // lotSize 50, premium 20, strike notionally => margin = avg*qty*lotSize*0.15
    test('sell option (write): receives premium, blocks 15% margin', () {
      final a = Acct(100000);
      foTrade(a, 'PE', 'OPTION', 'sell', 1, 20, 50);
      // margin = 20*1*50*0.15 = 150 ; premium = 1000 ; net credit = 1000-150 = 850
      expect(a.wallet, closeTo(100850, _eps));
      expect(a.fo['PE']!.netQty, -1);
      expect(a.fo['PE']!.margin, closeTo(150, _eps));
    });

    test('buy-to-close written option cheaper = PROFIT', () {
      final a = Acct(100000);
      foTrade(a, 'PE', 'OPTION', 'sell', 1, 20, 50); // +850, margin 150
      foTrade(a, 'PE', 'OPTION', 'buy', 1, 8, 50);
      // release margin 150, pay buyback 8*50=400 => ni = 150-400 = -250 debit
      // net from start: +850 - 250 = +600 ; pnl recorded (20-8)*50 = 600
      expect(a.wallet, closeTo(100600, _eps));
      expect(a.realized, closeTo(600, _eps));
      expect(a.fo.containsKey('PE'), false);
    });

    test('written option round-trip at same premium returns wallet exactly', () {
      final a = Acct(100000);
      foTrade(a, 'PE', 'OPTION', 'sell', 1, 20, 50);
      foTrade(a, 'PE', 'OPTION', 'buy', 1, 20, 50);
      expect(a.wallet, closeTo(100000, _eps));
    });
  });

  group('INVARIANTS (property-based, 100 random inputs each)', () {
    Glados2<int, int>(any.intInRange(1, 500), any.intInRange(1, 5000))
        .test('equity long round-trip nets to realised pnl', (qtyI, priceI) {
      final qty = qtyI.toDouble();
      final entry = priceI.toDouble();
      final exit = entry + 17; // arbitrary move
      final a = Acct(100000000);
      equityTrade(a, 'S', 'buy', qty, entry);
      equityTrade(a, 'S', 'sell', qty, exit);
      expect(a.wallet, closeTo(100000000 + (exit - entry) * qty, 1e-3));
      expect(a.eq.isEmpty, true);
    });

    Glados2<int, int>(any.intInRange(1, 500), any.intInRange(1, 5000))
        .test('equity SHORT round-trip nets to realised pnl (short profits when price falls)',
            (qtyI, priceI) {
      final qty = qtyI.toDouble();
      final entry = priceI.toDouble();
      final exit = math.max(1, entry - 13).toDouble();
      final a = Acct(100000000);
      equityTrade(a, 'S', 'sell', qty, entry); // open short (money OUT)
      final afterOpen = a.wallet;
      expect(afterOpen, lessThan(100000000)); // opening a short must reduce free cash
      equityTrade(a, 'S', 'buy', qty, exit); // cover
      expect(a.wallet, closeTo(100000000 + (entry - exit) * qty, 1e-3));
      expect(a.eq.isEmpty, true);
    });

    Glados2<int, int>(any.intInRange(1, 50), any.intInRange(10, 2000))
        .test('future round-trip nets to realised pnl', (lotsI, priceI) {
      final lots = lotsI.toDouble();
      final entry = priceI.toDouble();
      final exit = entry + 7;
      const lotSize = 50.0;
      final a = Acct(1000000000);
      foTrade(a, 'F', 'FUTURE', 'buy', lots, entry, lotSize);
      expect(a.wallet, lessThan(1000000000)); // margin blocked => money out
      foTrade(a, 'F', 'FUTURE', 'sell', lots, exit, lotSize);
      expect(a.wallet, closeTo(1000000000 + (exit - entry) * lots * lotSize, 1e-2));
      expect(a.fo.isEmpty, true);
    });

    Glados2<int, int>(any.intInRange(1, 50), any.intInRange(2, 500))
        .test('long option round-trip nets to premium change', (lotsI, premI) {
      final lots = lotsI.toDouble();
      final entry = premI.toDouble();
      final exit = entry + 4;
      const lotSize = 50.0;
      final a = Acct(1000000000);
      foTrade(a, 'CE', 'OPTION', 'buy', lots, entry, lotSize);
      expect(a.wallet, lessThan(1000000000)); // premium paid => money out
      foTrade(a, 'CE', 'OPTION', 'sell', lots, exit, lotSize);
      expect(a.wallet, closeTo(1000000000 + (exit - entry) * lots * lotSize, 1e-2));
      expect(a.fo.isEmpty, true);
    });
  });
}

