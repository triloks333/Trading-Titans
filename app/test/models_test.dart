// Full-coverage serialization & logic tests for every data model.
//
// These guard against the most common regression in this app: a field rename
// or a fromJson/toJson change silently breaking a screen. Each model is tested
// for: full parse, missing/null defaults, toJson round-trip, and all getters.

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/models/user.dart';
import 'package:mobile/models/order.dart';
import 'package:mobile/models/portfolio.dart';
import 'package:mobile/models/position_model.dart';
import 'package:mobile/models/candle.dart';
import 'package:mobile/models/quote.dart';

void main() {
  group('User', () {
    test('parses a full payload', () {
      final u = User.fromJson({
        'id': 'u1',
        'email': 'a@b.com',
        'name': 'Trilok',
        'wallet_balance': 120000,
        'subscription_active': true,
        'created_at': '2026-01-02T03:04:05.000Z',
        'total_realized_pnl': 4321.5,
        'referral_code': 'TT123',
        'referred_by': 'u0',
        'is_admin': true,
      });
      expect(u.id, 'u1');
      expect(u.email, 'a@b.com');
      expect(u.name, 'Trilok');
      expect(u.walletBalance, 120000);
      expect(u.subscriptionActive, true);
      expect(u.totalRealizedPnl, 4321.5);
      expect(u.referralCode, 'TT123');
      expect(u.referredBy, 'u0');
      expect(u.isAdmin, true);
    });

    test('applies defaults for missing optional fields', () {
      final u = User.fromJson({
        'id': 'u1',
        'email': 'a@b.com',
        'created_at': '2026-01-02T03:04:05.000Z',
      });
      expect(u.name, '');
      expect(u.walletBalance, 0.0);
      expect(u.subscriptionActive, false);
      expect(u.totalRealizedPnl, 0.0);
      expect(u.referralCode, '');
      expect(u.referredBy, isNull);
      expect(u.isAdmin, false);
    });

    test('toJson round-trips through fromJson', () {
      final u = User.fromJson({
        'id': 'u1',
        'email': 'a@b.com',
        'name': 'X',
        'wallet_balance': 5,
        'subscription_active': false,
        'created_at': '2026-01-02T03:04:05.000Z',
        'total_realized_pnl': 1,
        'referral_code': 'R',
        'is_admin': false,
      });
      final u2 = User.fromJson(u.toJson());
      expect(u2.id, u.id);
      expect(u2.walletBalance, u.walletBalance);
      expect(u2.createdAt, u.createdAt);
    });
  });

  group('Order', () {
    test('parses and computes status getters', () {
      final o = Order.fromJson({
        'id': 'o1',
        'symbol': 'NSE:RELIANCE',
        'name': 'Reliance',
        'market': 'stock',
        'side': 'buy',
        'quantity': 500,
        'price': 24.9,
        'total': 12450,
        'status': 'pending',
        'order_type': 'limit',
        'instrument_type': 'OPTION',
      });
      expect(o.isBuy, true);
      expect(o.isPending, true);
      expect(o.isExecuted, false);
      expect(o.isCancelled, false);
      expect(o.quantity, 500);
    });

    test('falls back across id aliases and defaults', () {
      final o = Order.fromJson({'order_id': 'fallback', 'symbol': 'X'});
      expect(o.id, 'fallback');
      expect(o.side, 'buy');
      expect(o.market, 'stock');
      expect(o.status, 'executed');
      expect(o.isExecuted, true);
      expect(o.brokerage, 0.0);
    });

    test('sell + cancelled getters', () {
      final o = Order.fromJson({'id': 'o', 'side': 'sell', 'status': 'cancelled'});
      expect(o.isBuy, false);
      expect(o.isCancelled, true);
    });
  });

  group('Holding', () {
    test('equity getters', () {
      final h = Holding.fromJson({
        'symbol': 'TCS',
        'name': 'Tata',
        'quantity': 10,
        'avg_price': 100,
      });
      expect(h.isEquity, true);
      expect(h.isOption, false);
      expect(h.isLong, true);
      expect(h.isShort, false);
      expect(h.positionTag, 'LONG');
      expect(h.displayName, 'Tata');
    });

    test('short option display name and tag', () {
      final h = Holding.fromJson({
        'symbol': 'RELIANCE',
        'quantity': -5,
        'instrument_type': 'OPTION',
        'option_type': 'CE',
        'strike_price': 1320,
      });
      expect(h.isOption, true);
      expect(h.isShort, true);
      expect(h.positionTag, 'SHORT');
      expect(h.displayName, 'RELIANCE 1320 CE');
    });

    test('expiryCountdown returns Expired for past dates', () {
      final h = Holding.fromJson({
        'symbol': 'X',
        'instrument_type': 'OPTION',
        'expiry_date': '2000-01-01',
      });
      expect(h.expiryCountdown, 'Expired');
    });

    test('expiryCountdown is null when no expiry', () {
      final h = Holding.fromJson({'symbol': 'X'});
      expect(h.expiryCountdown, isNull);
    });

    test('previous_close falls back to current_price', () {
      final h = Holding.fromJson({'symbol': 'X', 'current_price': 50});
      expect(h.previousClose, 50);
    });

    test('toJson round-trips', () {
      final h = Holding.fromJson({
        'symbol': 'X',
        'quantity': 3,
        'avg_price': 9,
        'instrument_type': 'OPTION',
        'option_type': 'PE',
        'strike_price': 100,
        'expiry_date': '2026-06-25',
      });
      final h2 = Holding.fromJson(h.toJson());
      expect(h2.symbol, 'X');
      expect(h2.optionType, 'PE');
      expect(h2.strikePrice, 100);
      expect(h2.expiryDate, '2026-06-25');
    });
  });

  group('Portfolio', () {
    test('filters equity vs option holdings', () {
      final p = Portfolio.fromJson({
        'wallet_balance': 1000,
        'holdings': [
          {'symbol': 'A', 'instrument_type': 'EQUITY'},
          {'symbol': 'B', 'instrument_type': 'OPTION'},
          {'symbol': 'C', 'instrument_type': 'EQUITY'},
        ],
      });
      expect(p.holdings.length, 3);
      expect(p.equityHoldings.length, 2);
      expect(p.optionPositions.length, 1);
    });

    test('empty holdings default', () {
      final p = Portfolio.fromJson({});
      expect(p.holdings, isEmpty);
      expect(p.walletBalance, 0.0);
    });
  });

  group('FoPosition', () {
    FoPosition pos({int netQty = 1, int lotSize = 500, double avg = 20, double margin = 0, String type = 'OPTION'}) {
      return FoPosition.fromJson({
        'id': 'p',
        'user_id': 'u',
        'symbol': 'RELIANCE-2026-06-25-1320-CE',
        'instrument_type': type,
        'option_type': 'CE',
        'strike_price': 1320,
        'expiry_date': '2026-06-25',
        'net_qty': netQty,
        'lot_size': lotSize,
        'avg_entry_price': avg,
        'margin_blocked': margin,
      });
    }

    test('long unrealized pnl = (current-avg) * units', () {
      final p = pos(netQty: 1, lotSize: 500, avg: 20);
      expect(p.unrealizedPnl(25), (25 - 20) * 500);
    });

    test('short unrealized pnl = (avg-current) * units', () {
      final p = pos(netQty: -2, lotSize: 50, avg: 30);
      expect(p.unrealizedPnl(20), (30 - 20) * 2 * 50);
    });

    test('long option pnl pct uses premium', () {
      final p = pos(netQty: 1, lotSize: 500, avg: 20);
      expect(p.unrealizedPnlPct(25), closeTo(((25 - 20) / 20) * 100, 1e-9));
    });

    test('pnl pct is 0 when no margin and not long option', () {
      final p = pos(netQty: -1, lotSize: 50, avg: 30, margin: 0);
      expect(p.unrealizedPnlPct(25), 0.0);
    });

    test('toJson round-trips, expiry date only', () {
      final p = pos();
      final j = p.toJson();
      expect(j['expiry_date'], '2026-06-25');
      final p2 = FoPosition.fromJson(j);
      expect(p2.netQty, p.netQty);
      expect(p2.lotSize, p.lotSize);
    });

    test('lot_size defaults to 1 when missing', () {
      final p = FoPosition.fromJson({
        'id': 'p', 'user_id': 'u', 'symbol': 'X',
        'expiry_date': '2026-06-25',
      });
      expect(p.lotSize, 1);
      expect(p.netQty, 0);
    });
  });

  group('CandleData', () {
    test('parses and isUp', () {
      final c = CandleData.fromJson({'t': 1000, 'o': 10, 'h': 12, 'l': 9, 'c': 11});
      expect(c.timestamp, 1000);
      expect(c.isUp, true);
    });
    test('isUp false when close < open', () {
      final c = CandleData.fromJson({'t': 1, 'o': 11, 'h': 12, 'l': 9, 'c': 10});
      expect(c.isUp, false);
    });
  });

  group('Quote', () {
    test('parses full payload and round-trips', () {
      final q = Quote.fromJson({
        'symbol': 'RELIANCE',
        'price': 1330.1,
        'previous_close': 1320,
        'change': 10.1,
        'change_pct': 0.76,
        'market': 'stock',
      });
      expect(q.price, 1330.1);
      expect(q.previousClose, 1320);
      final q2 = Quote.fromJson(q.toJson());
      expect(q2.price, q.price);
      expect(q2.symbol, q.symbol);
    });

    test('defaults for missing fields', () {
      final q = Quote.fromJson({});
      expect(q.price, 0.0);
      expect(q.currency, 'INR');
      expect(q.market, 'stock');
    });
  });
}
