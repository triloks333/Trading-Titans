import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user.dart' as app_models;
import '../models/portfolio.dart';
import '../models/order.dart';
import '../models/quote.dart';
import '../core/market_hours.dart';
import 'market_service.dart';

class SupabaseService {
  static final SupabaseService _instance = SupabaseService._internal();
  factory SupabaseService() => _instance;
  SupabaseService._internal();

  final SupabaseClient client = Supabase.instance.client;

  Future<void> initialize() async {
    if (client.auth.currentSession == null) {
      return;
    }
    await getUserProfile();
  }

  Future<AuthResponse> signUp({required String email, required String password, required String name}) async {
    final response = await client.auth.signUp(
      email: email,
      password: password,
      data: {'name': name},
    );

    final user = response.user;
    if (user != null) {
      await client.from('profiles').insert({
        'id': user.id,
        'email': email,
        'name': name,
        'wallet_balance': 100000.0,
        'subscription_active': true,
        'plan': 'free_starter',
        'total_realized_pnl': 0.0,
      });
    }

    return response;
  }

  Future<AuthResponse> signIn({required String email, required String password}) async {
    return await client.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  Future<void> signOut() async {
    await client.auth.signOut();
  }

  User? get currentUser => client.auth.currentUser;

  Future<app_models.User?> getUserProfile() async {
    final user = currentUser;
    if (user == null) return null;

    final profile = await client.from('profiles').select().eq('id', user.id).maybeSingle();
    if (profile == null) {
      final email = user.email ?? '';
      final name = (user.userMetadata?['name'] as String?) ?? email.split('@').first;
      final created = DateTime.now().toUtc().toIso8601String();
      final inserted = await client.from('profiles').insert({
        'id': user.id,
        'email': email,
        'name': name,
        'wallet_balance': 100000.0,
        'subscription_active': true,
        'plan': 'free_starter',
        'total_realized_pnl': 0.0,
        'created_at': created,
      }).select().maybeSingle();
      if (inserted == null) return null;
      return app_models.User.fromJson(Map<String, dynamic>.from(inserted as Map));
    }

    return app_models.User.fromJson(Map<String, dynamic>.from(profile as Map));
  }

  Future<List<Order>> getOrders({int limit = 50}) async {
    await executePendingOrders();
    final user = currentUser;
    if (user == null) return [];

    final data = await client
        .from('orders')
        .select()
        .eq('user_id', user.id)
        .order('created_at', ascending: false)
        .limit(limit);

    return (data as List<dynamic>).map((e) => Order.fromJson(Map<String, dynamic>.from(e as Map))).toList();
  }

  Future<List<Holding>> getHoldings() async {
    await executePendingOrders();
    final user = currentUser;
    if (user == null) return [];

    final rows = await client.from('holdings').select().eq('user_id', user.id);
    final results = <Holding>[];
    for (final raw in (rows as List<dynamic>)) {
      final row = Map<String, dynamic>.from(raw as Map);
      final symbol = row['symbol'] as String? ?? '';
      final market = row['market'] as String? ?? 'stock';
      final quantity = (row['quantity'] as num?)?.toDouble() ?? 0.0;
      final avgPrice = (row['avg_price'] as num?)?.toDouble() ?? 0.0;
      final currentQuote = await MarketService.quote(symbol, market);
      final currentPrice = currentQuote?.price ?? avgPrice;
      final previousClose = currentQuote?.previousClose ?? currentPrice;
      final invested = avgPrice * quantity;
      final currentValue = currentPrice * quantity;
      final pnl = currentValue - invested;
      final pnlPct = invested != 0 ? (pnl / invested) * 100 : 0.0;
      final dayPnl = (currentPrice - previousClose) * quantity;
      final dayPnlPct = previousClose != 0 ? ((currentPrice - previousClose) / previousClose) * 100 : 0.0;

      results.add(Holding(
        symbol: symbol,
        name: row['name'] as String? ?? symbol,
        market: market,
        quantity: quantity,
        avgPrice: avgPrice,
        currentPrice: currentPrice,
        previousClose: previousClose,
        invested: invested,
        current: currentValue,
        pnl: pnl,
        pnlPct: pnlPct,
        dayPnl: dayPnl,
        dayPnlPct: dayPnlPct,
      ));
    }
    return results;
  }

  Future<List<Quote>> getWatchlist() async {
    final user = currentUser;
    if (user == null) return [];

    final rows = await client.from('watchlist').select().eq('user_id', user.id).order('created_at', ascending: false);
    final results = <Quote>[];
    for (final raw in (rows as List<dynamic>)) {
      final row = Map<String, dynamic>.from(raw as Map);
      final symbol = row['symbol'] as String? ?? '';
      final market = row['market'] as String? ?? 'stock';
      final quote = await MarketService.quote(symbol, market);
      if (quote != null) {
        results.add(quote);
      } else {
        results.add(Quote(
          symbol: symbol,
          yfSymbol: symbol,
          name: row['name'] as String? ?? symbol,
          price: 0.0,
          previousClose: 0.0,
          change: 0.0,
          changePct: 0.0,
          currency: 'INR',
          market: market,
        ));
      }
    }
    return results;
  }

  Future<List<Quote>> getMarketOverview() async {
    return await MarketService.getMarketOverview();
  }

  Future<Quote?> getQuote(String symbol, String market) async {
    return await MarketService.quote(symbol, market);
  }

  Future<List<Map<String, dynamic>>> getLeaderboard() async {
    final data = await client
        .from('profiles')
        .select('id, name, wallet_balance, plan, total_realized_pnl')
        .order('total_realized_pnl', ascending: false)
        .limit(20);
    return (data as List<dynamic>)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .map((row) {
          return {
            'user_id': row['id'],
            'name': row['name'],
            'wallet_balance': (row['wallet_balance'] as num?)?.toDouble() ?? 0.0,
            'plan': row['plan'] as String? ?? 'free_starter',
            'realized_pnl': (row['total_realized_pnl'] as num?)?.toDouble() ?? 0.0,
          };
        })
        .toList();
  }

  Future<Map<String, dynamic>> getAnalytics() async {
    final user = currentUser;
    if (user == null) return {};

    final rows = await client
        .from('orders')
        .select('symbol, name, side, realized_pnl')
        .eq('user_id', user.id);
    final orders = (rows as List<dynamic>).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final totalTrades = orders.length;
    final buyTrades = orders.where((o) => o['side'] == 'buy').length;
    final sellTrades = orders.where((o) => o['side'] == 'sell').length;
    final winningTrades = orders.where((o) => (o['realized_pnl'] as num).toDouble() > 0).length;
    final losingTrades = orders.where((o) => (o['realized_pnl'] as num).toDouble() < 0).length;
    final realizedPnl = orders.fold<double>(0.0, (sum, o) => sum + ((o['realized_pnl'] as num?)?.toDouble() ?? 0.0));
    final winRate = totalTrades > 0 ? ((winningTrades / totalTrades) * 100).round() : 0;
    final bestTrade = orders.where((o) => (o['realized_pnl'] as num).toDouble() > 0).fold<Map<String, dynamic>?>(null, (best, next) {
      if (best == null) return next;
      return (next['realized_pnl'] as num).toDouble() > (best['realized_pnl'] as num).toDouble() ? next : best;
    });
    final worstTrade = orders.where((o) => (o['realized_pnl'] as num).toDouble() < 0).fold<Map<String, dynamic>?>(null, (worst, next) {
      if (worst == null) return next;
      return (next['realized_pnl'] as num).toDouble() < (worst['realized_pnl'] as num).toDouble() ? next : worst;
    });

    return {
      'total_trades': totalTrades,
      'buy_trades': buyTrades,
      'sell_trades': sellTrades,
      'winning_trades': winningTrades,
      'losing_trades': losingTrades,
      'win_rate': winRate,
      'realized_pnl': realizedPnl,
      'best_trade': bestTrade,
      'worst_trade': worstTrade,
    };
  }

  Future<Map<String, dynamic>> getAutopsy() async {
    final user = currentUser;
    if (user == null) {
      return {
        'summary': 'Sign in to see autopsy insights.',
        'insights': [],
      };
    }

    final rows = await client
        .from('orders')
        .select('symbol, name, market, side, quantity, price, total, realized_pnl, created_at')
        .eq('user_id', user.id)
        .order('created_at', ascending: false)
        .limit(20);
    final orders = (rows as List<dynamic>).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final losses = orders.where((o) => ((o['realized_pnl'] as num?)?.toDouble() ?? 0.0) < 0).toList();
    final insights = losses.take(5).map((order) {
      final loss = (order['realized_pnl'] as num?)?.toDouble() ?? 0.0;
      return {
        'symbol': order['symbol'] as String? ?? '',
        'name': order['name'] as String? ?? order['symbol'] as String? ?? '',
        'market': order['market'] as String? ?? 'stock',
        'loss': loss.abs(),
        'loss_pct': order['total'] != null && (order['total'] as num).toDouble() != 0.0 ? (loss.abs() / (order['total'] as num).toDouble()) * 100 : 0.0,
        'type': 'closed_loss',
        'tip': 'Review entry size and stop-loss discipline for ${order['symbol']}.',
      };
    }).toList();

    return {
      'summary': losses.isEmpty
          ? 'No major losing trades yet. Keep sharpening your strategy.'
          : 'Review your recent losing trades and look for recurring entry or exit mistakes.',
      'insights': insights,
    };
  }

  Future<void> addToWatchlist(String symbol, String market) async {
    final user = currentUser;
    if (user == null) return;
    await client.from('watchlist').upsert({
      'user_id': user.id,
      'symbol': symbol,
      'market': market,
    }, onConflict: 'user_id,symbol,market');
  }

  Future<void> removeFromWatchlist(String symbol, String market) async {
    final user = currentUser;
    if (user == null) return;
    await client.from('watchlist').delete().eq('user_id', user.id).eq('symbol', symbol).eq('market', market);
  }

  Future<Order> placeOrder({
    required String symbol,
    required String market,
    required String side,
    required double quantity,
  }) async {
    final user = currentUser;
    if (user == null) throw Exception('No authenticated user');

    final profile = await getUserProfile();
    if (profile == null) throw Exception('Profile not found');

    final quote = await MarketService.quote(symbol, market);
    if (quote == null) throw Exception('Market quote unavailable');

    final currentPrice = quote.price;
    final total = currentPrice * quantity;
    double realizedPnl = 0.0;

    if (!MarketHours.isOpen(market)) {
      final order = await client.from('orders').insert({
        'user_id': user.id,
        'symbol': symbol,
        'name': quote.name,
        'market': market,
        'side': side,
        'quantity': quantity,
        'price': currentPrice,
        'total': total,
        'realized_pnl': 0,
        'status': 'pending',
      }).select().maybeSingle();
      if (order == null) throw Exception('Could not place order');
      return Order.fromJson(Map<String, dynamic>.from(order as Map));
    }

    if (side == 'buy') {
      if (profile.walletBalance < total) {
        throw Exception('Insufficient wallet balance');
      }
      await client.from('profiles').update({'wallet_balance': profile.walletBalance - total}).eq('id', user.id);
      final existing = await client.from('holdings').select().eq('user_id', user.id).eq('symbol', symbol).eq('market', market).maybeSingle();
      if (existing == null) {
        await client.from('holdings').insert({
          'user_id': user.id,
          'symbol': symbol,
          'market': market,
          'quantity': quantity,
          'avg_price': currentPrice,
          'name': quote.name,
        });
      } else {
        final existingMap = Map<String, dynamic>.from(existing as Map);
        final oldQuantity = (existingMap['quantity'] as num).toDouble();
        final oldAvg = (existingMap['avg_price'] as num).toDouble();
        final newQuantity = oldQuantity + quantity;
        final newAvg = newQuantity > 0 ? ((oldAvg * oldQuantity) + (currentPrice * quantity)) / newQuantity : currentPrice;
        await client.from('holdings').update({
          'quantity': newQuantity,
          'avg_price': newAvg,
          'name': quote.name,
        }).eq('user_id', user.id).eq('symbol', symbol).eq('market', market);
      }
    } else {
      final holdingRaw = await client.from('holdings').select().eq('user_id', user.id).eq('symbol', symbol).eq('market', market).maybeSingle();
      if (holdingRaw == null) throw Exception('No holding available to sell');
      final holdingMap = Map<String, dynamic>.from(holdingRaw as Map);
      final currentQty = (holdingMap['quantity'] as num).toDouble();
      final avgPrice = (holdingMap['avg_price'] as num).toDouble();
      if (quantity > currentQty) throw Exception('Not enough quantity to sell');
      realizedPnl = (currentPrice - avgPrice) * quantity;
      final updatedQty = currentQty - quantity;
      await client.from('profiles').update({
        'wallet_balance': profile.walletBalance + total,
        'total_realized_pnl': profile.totalRealizedPnl + realizedPnl,
      }).eq('id', user.id);
      if (updatedQty <= 0) {
        await client.from('holdings').delete().eq('user_id', user.id).eq('symbol', symbol).eq('market', market);
      } else {
        await client.from('holdings').update({
          'quantity': updatedQty,
          'avg_price': avgPrice,
          'name': quote.name,
        }).eq('user_id', user.id).eq('symbol', symbol).eq('market', market);
      }
    }

    final order = await client.from('orders').insert({
      'user_id': user.id,
      'symbol': symbol,
      'name': quote.name,
      'market': market,
      'side': side,
      'quantity': quantity,
      'price': currentPrice,
      'total': total,
      'realized_pnl': realizedPnl,
      'status': 'executed',
      'executed_at': DateTime.now().toUtc().toIso8601String(),
    }).select().maybeSingle();

    if (order == null) throw Exception('Could not place order');
    return Order.fromJson(Map<String, dynamic>.from(order as Map));
  }

  Future<void> executePendingOrders() async {
    if (!MarketHours.isOpen('stock') && !MarketHours.isOpen('crypto')) return;
    final user = currentUser;
    if (user == null) return;

    final pending = await client.from('orders').select().eq('user_id', user.id).eq('status', 'pending');
    for (final raw in (pending as List<dynamic>)) {
      final row = Map<String, dynamic>.from(raw as Map);
      final id = row['id'] as String;
      final symbol = row['symbol'] as String;
      final market = row['market'] as String? ?? 'stock';
      final side = row['side'] as String;
      final quantity = (row['quantity'] as num).toDouble();

      if (!MarketHours.isOpen(market)) continue;

      try {
        final quote = await MarketService.quote(symbol, market);
        if (quote == null) continue;
        final execPrice = quote.price;
        final total = execPrice * quantity;
        final profile = await getUserProfile();
        if (profile == null) continue;

        double realizedPnl = 0.0;

        if (side == 'buy') {
          if (profile.walletBalance < total) continue;
          await client.from('profiles').update({'wallet_balance': profile.walletBalance - total}).eq('id', user.id);
          final existing = await client.from('holdings').select().eq('user_id', user.id).eq('symbol', symbol).eq('market', market).maybeSingle();
          if (existing == null) {
            await client.from('holdings').insert({
              'user_id': user.id, 'symbol': symbol, 'market': market,
              'quantity': quantity, 'avg_price': execPrice, 'name': quote.name,
            });
          } else {
            final m = Map<String, dynamic>.from(existing as Map);
            final oq = (m['quantity'] as num).toDouble();
            final oa = (m['avg_price'] as num).toDouble();
            final nq = oq + quantity;
            final na = nq > 0 ? ((oa * oq) + (execPrice * quantity)) / nq : execPrice;
            await client.from('holdings').update({'quantity': nq, 'avg_price': na, 'name': quote.name})
              .eq('user_id', user.id).eq('symbol', symbol).eq('market', market);
          }
        } else {
          final holdingRaw = await client.from('holdings').select().eq('user_id', user.id).eq('symbol', symbol).eq('market', market).maybeSingle();
          if (holdingRaw == null) {
            await client.from('orders').update({'status': 'cancelled'}).eq('id', id);
            continue;
          }
          final m = Map<String, dynamic>.from(holdingRaw as Map);
          final cq = (m['quantity'] as num).toDouble();
          final ap = (m['avg_price'] as num).toDouble();
          if (quantity > cq) {
            await client.from('orders').update({'status': 'cancelled'}).eq('id', id);
            continue;
          }
          realizedPnl = (execPrice - ap) * quantity;
          final uq = cq - quantity;
          await client.from('profiles').update({
            'wallet_balance': profile.walletBalance + total,
            'total_realized_pnl': profile.totalRealizedPnl + realizedPnl,
          }).eq('id', user.id);
          if (uq <= 0) {
            await client.from('holdings').delete().eq('user_id', user.id).eq('symbol', symbol).eq('market', market);
          } else {
            await client.from('holdings').update({'quantity': uq, 'avg_price': ap, 'name': quote.name})
              .eq('user_id', user.id).eq('symbol', symbol).eq('market', market);
          }
        }

        await client.from('orders').update({
          'status': 'executed',
          'price': execPrice,
          'total': total,
          'realized_pnl': realizedPnl,
          'executed_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('id', id);
      } catch (_) {}
    }
  }

  Future<void> cancelOrder(String orderId) async {
    await client.from('orders').update({'status': 'cancelled'}).eq('id', orderId);
  }

  Future<Map<String, dynamic>> createSubscriptionOrder(String planId) async {
    final plans = {
      'titan_1l': {'id': 'titan_1l', 'name': 'Starter Boost', 'price': 199, 'cash': 50000, 'is_mock': true},
      'titan_5l': {'id': 'titan_5l', 'name': 'Titan Plus', 'price': 899, 'cash': 100000, 'is_mock': true},
      'titan_pro': {'id': 'titan_pro', 'name': 'Pro Launch', 'price': 1499, 'cash': 200000, 'is_mock': true},
    };
    final plan = plans[planId] ?? plans['titan_1l']!;
    return {
      'id': '${plan['id']}_${DateTime.now().millisecondsSinceEpoch}',
      'plan': plan,
      'is_mock': true,
    };
  }

  Future<Map<String, dynamic>> activateSubscription({required String planId, String? orderId}) async {
    final user = currentUser;
    if (user == null) {
      throw Exception('No authenticated user');
    }

    final profile = await getUserProfile();
    if (profile == null) {
      throw Exception('Profile not found');
    }

    final planCash = planId == 'titan_5l' ? 100000.0 : planId == 'titan_pro' ? 200000.0 : 50000.0;
    await client.from('profiles').update({
      'wallet_balance': profile.walletBalance + planCash,
      'subscription_active': true,
      'plan': planId,
    }).eq('id', user.id);

    return {
      'message': 'Subscription activated and ₹${planCash.toStringAsFixed(0)} credited to your wallet.',
    };
  }

  Future<void> creditDemoCash(double amount) async {
    final user = currentUser;
    if (user == null) {
      throw Exception('No authenticated user');
    }

    final profile = await getUserProfile();
    if (profile == null) {
      throw Exception('Profile not found');
    }

    await client.from('profiles').update({
      'wallet_balance': profile.walletBalance + amount,
    }).eq('id', user.id);
  }

  Future<List<Map<String, dynamic>>> getHistory(String symbol, String market, String range) async {
    return await MarketService.getHistory(symbol, market, range);
  }
}
