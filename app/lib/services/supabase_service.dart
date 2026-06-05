import 'dart:convert';
import 'dart:typed_data';
import 'package:shared_preferences/shared_preferences.dart';
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

  Future<void> _saveCache(String key, String jsonStr) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, jsonStr);
    } catch (_) {}
  }

  Future<String?> _readCache(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(key);
    } catch (_) {
      return null;
    }
  }

  Future<List<Holding>> getCachedHoldings() async {
    final user = currentUser;
    if (user == null) return [];
    final jsonStr = await _readCache('holdings_${user.id}');
    if (jsonStr == null) return [];
    try {
      final decoded = jsonDecode(jsonStr) as List;
      return decoded
          .map((e) => Holding.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<Quote>> getCachedWatchlist() async {
    final user = currentUser;
    if (user == null) return [];
    final jsonStr = await _readCache('watchlist_${user.id}');
    if (jsonStr == null) return [];
    try {
      final decoded = jsonDecode(jsonStr) as List;
      return decoded
          .map((e) => Quote.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<Quote>> getCachedMarketOverview() async {
    final jsonStr = await _readCache('market_overview');
    if (jsonStr == null) return [];
    try {
      final decoded = jsonDecode(jsonStr) as List;
      return decoded
          .map((e) => Quote.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<app_models.User?> getCachedUserProfile() async {
    final user = currentUser;
    if (user == null) return null;
    final jsonStr = await _readCache('user_profile_${user.id}');
    if (jsonStr == null) return null;
    try {
      return app_models.User.fromJson(
        jsonDecode(jsonStr) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> initialize() async {
    if (client.auth.currentSession == null) {
      return;
    }
    await getUserProfile();
  }

  Future<AuthResponse> signUp({
    required String email,
    required String password,
    required String name,
    String? referralCode,
  }) async {
    String? referredById;
    if (referralCode != null && referralCode.trim().isNotEmpty) {
      final codeUpper = referralCode.trim().toUpperCase();
      final referrerProfile = await client
          .from('profiles')
          .select('id')
          .eq('referral_code', codeUpper)
          .maybeSingle();
      if (referrerProfile == null) {
        throw Exception(
          'Invalid referral code. Please check the code and try again.',
        );
      }
      referredById = referrerProfile['id'] as String;
    }

    final Map<String, dynamic> userData = {'name': name};
    if (referredById != null) {
      userData['referred_by'] = referredById;
    }

    final response = await client.auth.signUp(
      email: email,
      password: password,
      data: userData,
    );

    return response;
  }

  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
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

    final profile = await client
        .from('profiles')
        .select()
        .eq('id', user.id)
        .maybeSingle();
    if (profile == null) return null;

    final parsed = app_models.User.fromJson(
      Map<String, dynamic>.from(profile as Map),
    );
    await _saveCache('user_profile_${user.id}', jsonEncode(parsed.toJson()));
    return parsed;
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

    return (data as List<dynamic>)
        .map((e) => Order.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// Settles expired option positions automatically.
  /// - ITM options: auto-exercised, intrinsic value credited/debited to wallet
  /// - OTM options: expire worthless, position removed
  Future<void> settleExpiredDerivatives() async {
    final user = currentUser;
    if (user == null) return;

    final today = DateTime.now();
    final todayStr = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

    // Find all derivative holdings (OPTION + FUTURE) with expiry_date <= today
    final expiredOptionRows = await client
        .from('holdings')
        .select()
        .eq('user_id', user.id)
        .eq('instrument_type', 'OPTION')
        .lte('expiry_date', todayStr);

    final expiredFutureRows = await client
        .from('holdings')
        .select()
        .eq('user_id', user.id)
        .eq('instrument_type', 'FUTURE')
        .lte('expiry_date', todayStr);

    final allExpired = [
      ...(expiredOptionRows as List<dynamic>),
      ...(expiredFutureRows as List<dynamic>).where((r) {
        // For PERPETUAL futures, never auto-expire
        final expiry = (r as Map)['expiry_date'] as String? ?? '';
        return expiry != 'PERPETUAL' && expiry.isNotEmpty;
      }),
    ];

    if (allExpired.isEmpty) return;

    final profile = await getUserProfile();
    if (profile == null) return;
    double walletBalance = profile.walletBalance;
    double totalRealizedPnl = profile.totalRealizedPnl;

    for (final raw in allExpired) {
      final row = Map<String, dynamic>.from(raw as Map);
      final holdingId = row['id'] as String;
      final symbol = row['symbol'] as String;
      final market = row['market'] as String? ?? 'stock';
      final quantity = (row['quantity'] as num).toDouble();
      final avgPrice = (row['avg_price'] as num).toDouble();
      final instType = row['instrument_type'] as String? ?? 'OPTION';
      final optionType = row['option_type'] as String? ?? 'CE';
      final strikePrice = (row['strike_price'] as num?)?.toDouble() ?? 0.0;
      final expiryDate = row['expiry_date'] as String? ?? todayStr;

      // Get the underlying spot price for settlement
      String underlyingSymbol = symbol;
      if (symbol.contains('-')) {
        underlyingSymbol = symbol.split('-')[0];
      } else if (symbol.contains(' ')) {
        // Future symbols like "RELIANCE JUN FUT"
        underlyingSymbol = symbol.split(' ')[0];
      }

      double spotPrice = avgPrice; // fallback
      try {
        final quote = await MarketService.quote(underlyingSymbol, market);
        if (quote != null) spotPrice = quote.price;
      } catch (_) {}

      double settlementPnl = 0.0;
      String orderName = '';
      String notifTitle = '';
      String notifBody = '';

      if (instType == 'FUTURE') {
        // ── FUTURES SETTLEMENT ──
        // Futures settle at the closing spot price
        // Long: P&L = (spotPrice - avgPrice) × quantity
        // Short: P&L = (avgPrice - spotPrice) × |quantity|
        if (quantity > 0) {
          settlementPnl = (spotPrice - avgPrice) * quantity;
        } else {
          settlementPnl = (avgPrice - spotPrice) * quantity.abs();
        }

        orderName = 'Futures Expiry Settlement';
        notifTitle = 'Futures Expired';
        notifBody = '$symbol expired. Settlement P&L: ${settlementPnl >= 0 ? '+' : ''}₹${settlementPnl.toStringAsFixed(2)}';

        // Return the blocked margin + P&L to wallet
        // Margin was ~15% of notional at entry
        final blockedMargin = avgPrice * quantity.abs() * 0.15;
        walletBalance += blockedMargin + settlementPnl;

      } else {
        // ── OPTIONS SETTLEMENT ──
        double intrinsicValue = 0.0;
        if (optionType == 'CE') {
          intrinsicValue = (spotPrice - strikePrice).clamp(0.0, double.infinity);
        } else {
          intrinsicValue = (strikePrice - spotPrice).clamp(0.0, double.infinity);
        }

        final bool isITM = intrinsicValue > 0;

        if (quantity > 0) {
          // Long: bought option
          settlementPnl = (intrinsicValue - avgPrice) * quantity;
        } else {
          // Short: wrote option
          settlementPnl = (avgPrice - intrinsicValue) * quantity.abs();
        }

        walletBalance += settlementPnl;
        orderName = '${isITM ? "ITM" : "OTM"} Expiry Settlement';
        notifTitle = isITM ? 'Option Exercised (ITM)' : 'Option Expired (OTM)';
        notifBody = isITM
            ? '$symbol expired ITM. Settlement P&L: ₹${settlementPnl.toStringAsFixed(2)}'
            : '$symbol expired OTM. Premium lost: ₹${(avgPrice * quantity.abs()).toStringAsFixed(2)}';
      }

      totalRealizedPnl += settlementPnl;

      // Record the settlement as a closed order (shows in Order History)
      try {
        await client.from('orders').insert({
          'user_id': user.id,
          'symbol': symbol,
          'name': orderName,
          'market': market,
          'side': quantity > 0 ? 'sell' : 'buy',
          'quantity': quantity.abs(),
          'price': spotPrice,
          'total': spotPrice * quantity.abs(),
          'realized_pnl': settlementPnl,
          'status': 'executed',
          'order_type': 'expiry_settlement',
          'instrument_type': instType,
          'strike_price': instType == 'OPTION' ? strikePrice : null,
          'option_type': instType == 'OPTION' ? optionType : null,
          'expiry_date': expiryDate,
          'executed_at': DateTime.now().toUtc().toIso8601String(),
        });

        // Create notification
        await client.from('notifications').insert({
          'user_id': user.id,
          'title': notifTitle,
          'body': notifBody,
          'is_read': false,
          'action_type': 'expiry',
          'action_data': {'symbol': symbol, 'market': market},
        });
      } catch (_) {}

      // Delete the expired holding
      await client.from('holdings').delete().eq('id', holdingId);
    }

    // Update wallet balance and total realized P&L
    await client
        .from('profiles')
        .update({
          'wallet_balance': walletBalance,
          'total_realized_pnl': totalRealizedPnl,
        })
        .eq('id', user.id);
  }

  Future<List<Holding>> getHoldings() async {
    await Future.wait([
      settleExpiredDerivatives(),
      executePendingOrders(),
    ]);
    final user = currentUser;
    if (user == null) return [];

    final now = DateTime.now();
    final localTodayStart = DateTime(now.year, now.month, now.day);
    final todayStartStr = localTodayStart.toUtc().toIso8601String();

    String holdingKey(String symbol, String market) => '$symbol\x1F$market';

    final recentOrdersRaw = await client
        .from('orders')
        .select('symbol, market, quantity, price, side, name, realized_pnl')
        .eq('user_id', user.id)
        .eq('status', 'executed')
        .gte('executed_at', todayStartStr);

    final todayBuys = <String, double>{};
    final todayBuyCost = <String, double>{};
    final todaySells = <String, double>{};
    final todaySellCost = <String, double>{};
    final todayRealizedPnl = <String, double>{};
    final symbolNames = <String, String>{};

    for (final raw in (recentOrdersRaw as List<dynamic>)) {
      final r = Map<String, dynamic>.from(raw as Map);
      final symbol = r['symbol'] as String? ?? '';
      final market = r['market'] as String? ?? 'stock';
      final key = holdingKey(symbol, market);
      final q = (r['quantity'] as num).toDouble();
      final p = (r['price'] as num).toDouble();
      final side = r['side'] as String? ?? 'buy';
      final name = r['name'] as String? ?? symbol;
      final relPnl = (r['realized_pnl'] as num?)?.toDouble() ?? 0.0;

      symbolNames[key] = name;

      if (side == 'buy') {
        todayBuys[key] = (todayBuys[key] ?? 0.0) + q;
        todayBuyCost[key] = (todayBuyCost[key] ?? 0.0) + (q * p);
      } else if (side == 'sell') {
        todaySells[key] = (todaySells[key] ?? 0.0) + q;
        todaySellCost[key] = (todaySellCost[key] ?? 0.0) + (q * p);
        todayRealizedPnl[key] = (todayRealizedPnl[key] ?? 0.0) + relPnl;
      }
    }

    final rows = await client.from('holdings').select().eq('user_id', user.id);
    final results = <Holding>[];
    final activeKeys = <String>{};
    final activeHoldingsMap = <String, Map<String, dynamic>>{};

    for (final raw in (rows as List<dynamic>)) {
      final row = Map<String, dynamic>.from(raw as Map);
      final symbol = row['symbol'] as String? ?? '';
      final market = row['market'] as String? ?? 'stock';
      final key = holdingKey(symbol, market);
      activeKeys.add(key);
      activeHoldingsMap[key] = row;
    }

    final allKeys = {...activeKeys, ...todayBuys.keys, ...todaySells.keys};

    final allKeysList = allKeys.toList();

    // Build a map of underlying symbols for option and future contracts
    // Option symbols look like "RELIANCE-2026-06-05-2500-CE"
    // Future symbols look like "RELIANCE JUN FUT" or "BTCUSDT"
    final underlyingKeyMap = <String, String>{}; // key -> underlying key
    final underlyingKeys = <String>{}; // unique underlying keys to fetch
    for (final key in allKeysList) {
      final parts = key.split('\x1F');
      final symbol = parts[0];
      final market = parts[1];
      final activeRow = activeHoldingsMap[key];
      final instType = activeRow?['instrument_type'] as String? ?? 'EQUITY';

      if (instType == 'OPTION' && symbol.contains('-')) {
        final underlying = symbol.split('-')[0]; // e.g. RELIANCE
        final underlyingKey = '$underlying\x1F$market';
        underlyingKeyMap[key] = underlyingKey;
        underlyingKeys.add(underlyingKey);
      } else if (instType == 'FUTURE') {
        // Extract underlying from future symbol: "RELIANCE JUN FUT" -> "RELIANCE"
        String underlying = symbol;
        if (symbol.contains(' ')) {
          underlying = symbol.split(' ')[0];
        }
        final underlyingKey = '$underlying\x1F$market';
        underlyingKeyMap[key] = underlyingKey;
        underlyingKeys.add(underlyingKey);
      }
    }

    // Fetch quotes for all keys: equity/crypto symbols + underlying symbols for derivatives
    final keysToFetch = <String>{...allKeysList, ...underlyingKeys}
        .where((k) {
          // Skip fetching derivative symbols directly — they won't resolve
          final sym = k.split('\x1F')[0];
          final row = activeHoldingsMap[k];
          final instType = row?['instrument_type'] as String? ?? 'EQUITY';
          if (instType == 'OPTION' && sym.contains('-')) return false;
          if (instType == 'FUTURE') return false;
          return true;
        })
        .toList();

    final quoteFutures = keysToFetch.map((key) {
      final parts = key.split('\x1F');
      return MarketService.quote(parts[0], parts[1]);
    }).toList();

    final fetchedQuotes = await Future.wait(quoteFutures);
    final quotesMap = <String, Quote?>{};
    for (int i = 0; i < keysToFetch.length; i++) {
      quotesMap[keysToFetch[i]] = fetchedQuotes[i];
    }

    for (final key in allKeysList) {
      final parts = key.split('\x1F');
      final symbol = parts[0];
      final market = parts[1];

      final activeRow = activeHoldingsMap[key];
      final quantity = (activeRow?['quantity'] as num?)?.toDouble() ?? 0.0;
      final avgPrice = (activeRow?['avg_price'] as num?)?.toDouble() ?? 0.0;
      final name = activeRow?['name'] as String? ?? symbolNames[key] ?? symbol;
      final instType = activeRow?['instrument_type'] as String? ?? 'EQUITY';

      double currentPrice;
      double previousClose;

      if (instType == 'OPTION' && underlyingKeyMap.containsKey(key)) {
        // For options: estimate current price from underlying spot price
        final underlyingQuote = quotesMap[underlyingKeyMap[key]];
        final spotPrice = underlyingQuote?.price ?? 0.0;
        final spotPrevClose = underlyingQuote?.previousClose ?? spotPrice;
        final strikePrice = (activeRow?['strike_price'] as num?)?.toDouble() ?? 0.0;
        final optType = activeRow?['option_type'] as String? ?? 'CE';
        final expiryStr = activeRow?['expiry_date'] as String?;

        // Calculate intrinsic value
        double intrinsic = 0.0;
        if (optType == 'CE') {
          intrinsic = (spotPrice - strikePrice).clamp(0.0, double.infinity);
        } else {
          intrinsic = (strikePrice - spotPrice).clamp(0.0, double.infinity);
        }

        // Estimate time value based on days remaining
        double timeValue = 0.0;
        if (expiryStr != null) {
          try {
            final expiry = DateTime.parse(expiryStr);
            final now = DateTime.now();
            final daysLeft = expiry.difference(now).inHours / 24.0;
            if (daysLeft > 0) {
              // Simple time decay: sqrt(daysLeft/30) * avgPrice * 0.3
              // This gives a rough approximation of theta decay
              final timeDecayFactor = (daysLeft / 30.0).clamp(0.0, 1.0);
              final sqrtDecay = timeDecayFactor > 0 ? timeDecayFactor * 0.5 : 0.0;
              timeValue = avgPrice * sqrtDecay * 0.5;
            }
          } catch (_) {}
        }

        currentPrice = intrinsic + timeValue;
        if (currentPrice <= 0 && avgPrice > 0) {
          currentPrice = avgPrice * 0.05; // Floor at 5% of avg price (not zero)
        }

        // Previous close estimate using yesterday's spot
        double prevIntrinsic = 0.0;
        if (optType == 'CE') {
          prevIntrinsic = (spotPrevClose - strikePrice).clamp(0.0, double.infinity);
        } else {
          prevIntrinsic = (strikePrice - spotPrevClose).clamp(0.0, double.infinity);
        }
        previousClose = prevIntrinsic + timeValue;
        if (previousClose <= 0 && avgPrice > 0) {
          previousClose = avgPrice * 0.05;
        }
      } else if (instType == 'FUTURE' && underlyingKeyMap.containsKey(key)) {
        // For futures: derive price from underlying spot + carry cost
        final underlyingQuote = quotesMap[underlyingKeyMap[key]];
        final spotPrice = underlyingQuote?.price ?? avgPrice;
        final spotPrevClose = underlyingQuote?.previousClose ?? spotPrice;
        final expiryStr = activeRow?['expiry_date'] as String?;

        // Calculate carry cost: futures ≈ spot × (1 + r × T)
        double carryMultiplier = 1.0;
        if (expiryStr != null && expiryStr != 'PERPETUAL') {
          try {
            final expiry = DateTime.parse(expiryStr);
            final now = DateTime.now();
            final daysLeft = expiry.difference(now).inHours / 24.0;
            if (daysLeft > 0) {
              // Risk-free rate ~6.5% annualized
              carryMultiplier = 1.0 + 0.065 * (daysLeft / 365.0);
            }
          } catch (_) {}
        }

        currentPrice = spotPrice * carryMultiplier;
        previousClose = spotPrevClose * carryMultiplier;
      } else {
        // For stocks/crypto: use direct quote
        final currentQuote = quotesMap[key];
        currentPrice = currentQuote?.price ?? avgPrice;
        previousClose = currentQuote?.previousClose ?? currentPrice;
      }

      final totalBoughtToday = todayBuys[key] ?? 0.0;
      final cashInToday = todayBuyCost[key] ?? 0.0;
      final totalSoldToday = todaySells[key] ?? 0.0;
      final cashOutToday = todaySellCost[key] ?? 0.0;
      final realizedPnlToday = todayRealizedPnl[key] ?? 0.0;

      final invested = avgPrice * quantity.abs();
      final currentValue = currentPrice * quantity.abs();

      double dayPnl = 0.0;
      double dayPnlPct = 0.0;

      if (quantity > 0) {
        double initialQty = quantity - totalBoughtToday + totalSoldToday;
        if (initialQty < 0) {
          initialQty = 0.0;
        }
        final initialValue = initialQty * previousClose;
        dayPnl = (currentValue + cashOutToday) - (initialValue + cashInToday);

        final double denominator = (initialQty * previousClose) + cashInToday;
        if (denominator > 0) {
          dayPnlPct = (dayPnl / denominator) * 100;
        }
      } else if (quantity < 0) {
        double initialQtyAbs =
            quantity.abs() - totalSoldToday + totalBoughtToday;
        if (initialQtyAbs < 0) {
          initialQtyAbs = 0.0;
        }
        final initialValue = initialQtyAbs * previousClose;
        dayPnl = (initialValue + cashOutToday) - (currentValue + cashInToday);

        final double denominator =
            (initialQtyAbs * previousClose) + cashOutToday;
        if (denominator > 0) {
          dayPnlPct = (dayPnl / denominator) * 100;
        }
      } else {
        dayPnl = realizedPnlToday;
        dayPnlPct = 0.0;
      }

      final bool hasActivityToday = totalBoughtToday > 0 || totalSoldToday > 0;
      if (!MarketHours.isOpen(market) && !hasActivityToday) {
        dayPnl = 0.0;
        dayPnlPct = 0.0;
      }

      final double pnl = quantity != 0.0
          ? (currentPrice - avgPrice) * quantity
          : realizedPnlToday;
      final double pnlPct = quantity != 0.0
          ? (invested != 0 ? (pnl / invested) * 100 : 0.0)
          : 0.0;

      results.add(
        Holding(
          symbol: symbol,
          name: name,
          market: market,
          quantity: quantity,
          avgPrice: avgPrice,
          currentPrice: currentPrice,
          previousClose: previousClose,
          invested: invested,
          current: invested + pnl,
          pnl: pnl,
          pnlPct: pnlPct,
          dayPnl: dayPnl,
          dayPnlPct: dayPnlPct,
          instrumentType: activeRow?['instrument_type'] as String? ?? 'EQUITY',
          optionType: activeRow?['option_type'] as String?,
          strikePrice: (activeRow?['strike_price'] as num?)?.toDouble(),
          expiryDate: activeRow?['expiry_date'] as String?,
          productType: activeRow?['product_type'] as String? ?? 'CNC',
        ),
      );
    }

    await _saveCache(
      'holdings_${user.id}',
      jsonEncode(results.map((e) => e.toJson()).toList()),
    );
    return results;
  }

  Future<List<Map<String, dynamic>>> getCachedWatchlistRaw() async {
    final user = currentUser;
    if (user == null) return [];
    final jsonStr = await _readCache('watchlist_raw_${user.id}');
    if (jsonStr == null) return [];
    try {
      final decoded = jsonDecode(jsonStr) as List;
      return decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getWatchlistRaw() async {
    final user = currentUser;
    if (user == null) return [];
    final rows = await client
        .from('watchlist')
        .select()
        .eq('user_id', user.id)
        .order('created_at', ascending: false);
    final results = (rows as List<dynamic>)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    await _saveCache('watchlist_raw_${user.id}', jsonEncode(results));
    return results;
  }

  Future<List<Quote>> getWatchlist() async {
    final user = currentUser;
    if (user == null) return [];

    final rows = await client
        .from('watchlist')
        .select()
        .eq('user_id', user.id)
        .order('created_at', ascending: false);
    final results = <Quote>[];

    final rowsList = (rows as List<dynamic>)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final quoteFutures = rowsList.map((row) {
      final symbol = row['symbol'] as String? ?? '';
      final market = row['market'] as String? ?? 'stock';
      return MarketService.quote(symbol, market);
    }).toList();

    final quotes = await Future.wait(quoteFutures);

    for (int i = 0; i < rowsList.length; i++) {
      final row = rowsList[i];
      final symbol = row['symbol'] as String? ?? '';
      final market = row['market'] as String? ?? 'stock';
      final quote = quotes[i];

      if (quote != null) {
        results.add(quote);
      } else {
        results.add(
          Quote(
            symbol: symbol,
            yfSymbol: symbol,
            name: row['name'] as String? ?? symbol,
            price: 0.0,
            previousClose: 0.0,
            change: 0.0,
            changePct: 0.0,
            currency: 'INR',
            market: market,
          ),
        );
      }
    }
    await _saveCache(
      'watchlist_${user.id}',
      jsonEncode(results.map((e) => e.toJson()).toList()),
    );
    return results;
  }

  Future<List<Quote>> getMarketOverview() async {
    final overview = await MarketService.getMarketOverview();
    if (overview.isNotEmpty) {
      await _saveCache(
        'market_overview',
        jsonEncode(overview.map((e) => e.toJson()).toList()),
      );
    }
    return overview;
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
            'wallet_balance':
                (row['wallet_balance'] as num?)?.toDouble() ?? 0.0,
            'plan': row['plan'] as String? ?? 'free_starter',
            'realized_pnl':
                (row['total_realized_pnl'] as num?)?.toDouble() ?? 0.0,
          };
        })
        .toList();
  }

  Future<Map<String, dynamic>> getAnalytics() async {
    final user = currentUser;
    if (user == null) return {};

    final rows = await client
        .from('orders')
        .select('symbol, name, side, realized_pnl, created_at')
        .eq('user_id', user.id);
    final orders = (rows as List<dynamic>)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final totalTrades = orders.length;
    final buyTrades = orders.where((o) => o['side'] == 'buy').length;
    final sellTrades = orders.where((o) => o['side'] == 'sell').length;
    final winningTrades = orders
        .where((o) => ((o['realized_pnl'] as num?)?.toDouble() ?? 0.0) > 0)
        .length;
    final losingTrades = orders
        .where((o) => ((o['realized_pnl'] as num?)?.toDouble() ?? 0.0) < 0)
        .length;
    final realizedPnl = orders.fold<double>(
      0.0,
      (sum, o) => sum + ((o['realized_pnl'] as num?)?.toDouble() ?? 0.0),
    );
    final winRate = totalTrades > 0
        ? ((winningTrades / totalTrades) * 100).round()
        : 0;

    final wins = orders
        .where((o) => ((o['realized_pnl'] as num?)?.toDouble() ?? 0.0) > 0)
        .map((o) => (o['realized_pnl'] as num).toDouble())
        .toList();
    final losses = orders
        .where((o) => ((o['realized_pnl'] as num?)?.toDouble() ?? 0.0) < 0)
        .map((o) => (o['realized_pnl'] as num).toDouble())
        .toList();

    final totalWinsSum = wins.fold<double>(0.0, (sum, val) => sum + val);
    final totalLossesSum = losses.fold<double>(0.0, (sum, val) => sum + val);

    final avgWin = wins.isNotEmpty ? totalWinsSum / wins.length : 0.0;
    final avgLoss = losses.isNotEmpty ? totalLossesSum / losses.length : 0.0;
    final winLossRatio = avgLoss != 0.0 ? avgWin / avgLoss.abs() : 0.0;
    final profitFactor = totalLossesSum != 0.0
        ? totalWinsSum / totalLossesSum.abs()
        : (totalWinsSum > 0 ? double.infinity : 0.0);

    final bestTrade = orders
        .where((o) => ((o['realized_pnl'] as num?)?.toDouble() ?? 0.0) > 0)
        .fold<Map<String, dynamic>?>(null, (best, next) {
          if (best == null) return next;
          return (next['realized_pnl'] as num).toDouble() >
                  (best['realized_pnl'] as num).toDouble()
              ? next
              : best;
        });
    final worstTrade = orders
        .where((o) => ((o['realized_pnl'] as num?)?.toDouble() ?? 0.0) < 0)
        .fold<Map<String, dynamic>?>(null, (worst, next) {
          if (worst == null) return next;
          return (next['realized_pnl'] as num).toDouble() <
                  (worst['realized_pnl'] as num).toDouble()
              ? next
              : worst;
        });

    final sortedOrders = List<Map<String, dynamic>>.from(orders);
    sortedOrders.sort((a, b) {
      final aDate = a['created_at'] != null
          ? DateTime.tryParse(a['created_at'] as String)
          : null;
      final bDate = b['created_at'] != null
          ? DateTime.tryParse(b['created_at'] as String)
          : null;
      if (aDate == null || bDate == null) return 0;
      return aDate.compareTo(bDate);
    });

    double runningPnl = 0.0;
    final pnlSeries = sortedOrders.map((o) {
      runningPnl += ((o['realized_pnl'] as num?)?.toDouble() ?? 0.0);
      return {'date': o['created_at'] as String? ?? '', 'pnl': runningPnl};
    }).toList();

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
      'avg_win': avgWin,
      'avg_loss': avgLoss,
      'win_loss_ratio': winLossRatio,
      'profit_factor': profitFactor,
      'pnl_series': pnlSeries,
    };
  }

  Future<Map<String, dynamic>> getAutopsy() async {
    final user = currentUser;
    if (user == null) {
      return {'summary': 'Sign in to see autopsy insights.', 'insights': []};
    }

    try {
      final response = await client.functions.invoke('trade-autopsy');
      final rawData = response.data;
      if (rawData is Map) {
        return Map<String, dynamic>.from(rawData);
      } else if (rawData is String) {
        return jsonDecode(rawData) as Map<String, dynamic>;
      }
    } catch (e) {
      // Fallback
      return {
        'summary': 'Failed to load live autopsy insights. Please try again.',
        'insights': [],
      };
    }

    return {'summary': 'Failed to parse autopsy insights.', 'insights': []};
  }

  Future<void> addToWatchlist(
    String symbol,
    String market, [
    String? name,
  ]) async {
    final user = currentUser;
    if (user == null) return;
    await client.from('watchlist').upsert({
      'user_id': user.id,
      'symbol': symbol,
      'market': market,
      'name': ?name,
    }, onConflict: 'user_id,symbol,market');
  }

  Future<bool> isWatched(String symbol, String market) async {
    final user = currentUser;
    if (user == null) return false;
    final rows = await client
        .from('watchlist')
        .select('id')
        .eq('user_id', user.id)
        .eq('symbol', symbol)
        .eq('market', market);
    return (rows as List).isNotEmpty;
  }

  Future<void> removeFromWatchlist(String symbol, String market) async {
    final user = currentUser;
    if (user == null) return;
    await client
        .from('watchlist')
        .delete()
        .eq('user_id', user.id)
        .eq('symbol', symbol)
        .eq('market', market);
  }

  Future<Order> placeOrder({
    required String symbol,
    required String market,
    required String side,
    required double quantity,
    double? price,
    bool isMarket = true,
    String instrumentType = 'EQUITY',
    double? strikePrice,
    String? optionType,
    String? expiryDate,
  }) async {
    side = side.toLowerCase();
    final user = currentUser;
    if (user == null) throw Exception('No authenticated user');

    final profile = await getUserProfile();
    if (profile == null) throw Exception('Profile not found');

    double limitPrice = price ?? 0.0;
    double currentPrice = 0.0;
    String name = symbol;
    bool isQuoteAvailable = false;

    if (instrumentType == 'EQUITY') {
      final quote = await MarketService.quote(symbol, market);
      if (quote != null && quote.price > 0) {
        currentPrice = quote.price;
        name = quote.name;
        isQuoteAvailable = true;
      } else {
        if (price == null || price <= 0) {
          throw Exception('Market quote unavailable');
        }
        currentPrice = price;
      }
    } else {
      final liveQuote = await MarketService.quote(symbol, market);
      if (liveQuote != null && liveQuote.price > 0) {
        currentPrice = liveQuote.price;
        name = liveQuote.name;
        isQuoteAvailable = true;
      } else {
        if (price == null || price <= 0) {
          throw Exception('Live derivative quote unavailable. Please try again.');
        }
        currentPrice = price;
        if (instrumentType == 'FUTURE') {
          name = '$symbol Perpetual Futures';
        } else {
          name = '$symbol $expiryDate $strikePrice $optionType';
        }
      }
    }

    // Critical guard: never allow orders at price 0
    if (currentPrice <= 0) {
      throw Exception('Cannot place order: price is ₹0. Quote may be temporarily unavailable.');
    }

    bool executeImmediately = isMarket;
    if (!isMarket) {
      if (isQuoteAvailable) {
        if (side == 'buy') {
          executeImmediately = (currentPrice <= limitPrice);
        } else {
          executeImmediately = (currentPrice >= limitPrice);
        }
      } else {
        executeImmediately = false;
      }
    }

    if (market != 'crypto' && !MarketHours.isOpen(market)) {
      executeImmediately = false;
    }

    if (!executeImmediately) {
      final targetPrice = isMarket ? currentPrice : limitPrice;
      final total = targetPrice * quantity;

      final order = await client
          .from('orders')
          .insert({
            'user_id': user.id,
            'symbol': symbol,
            'name': name,
            'market': market,
            'side': side,
            'quantity': quantity,
            'price': targetPrice,
            'total': total,
            'realized_pnl': 0.0,
            'status': 'pending',
            'order_type': isMarket ? 'market' : 'limit',
            'instrument_type': instrumentType,
            'strike_price': strikePrice,
            'option_type': optionType,
            'expiry_date': expiryDate,
          })
          .select()
          .maybeSingle();

      if (order == null) throw Exception('Could not place order');

      try {
        await client.from('notifications').insert({
          'user_id': user.id,
          'title': 'Order Pending',
          'body':
              '${side.toUpperCase()} ${quantity.toStringAsFixed(market == "crypto" ? 4 : 0)} $symbol placed at ₹${targetPrice.toStringAsFixed(2)}',
          'is_read': false,
          'action_type': 'order',
          'action_data': {'symbol': symbol, 'market': market},
        });
      } catch (_) {}

      return Order.fromJson(Map<String, dynamic>.from(order as Map));
    }

    final execPrice = currentPrice;
    final total = execPrice * quantity;
    // Calculate margin required: derivatives use ~15% margin, equity uses full value
    final bool isDerivative = instrumentType == 'FUTURE' || instrumentType == 'OPTION';
    final double marginPct = isDerivative ? 0.15 : 1.0;
    final double marginRequired = total * marginPct;
    double realizedPnl = 0.0;

    if (side == 'buy') {
      final existing = await client
          .from('holdings')
          .select()
          .eq('user_id', user.id)
          .eq('symbol', symbol)
          .eq('market', market)
          .maybeSingle();
      if (existing == null) {
        if (profile.walletBalance < marginRequired) {
          throw Exception('Insufficient wallet balance. Required margin: ₹${marginRequired.toStringAsFixed(0)}');
        }
        await client
            .from('profiles')
            .update({'wallet_balance': profile.walletBalance - (isDerivative ? marginRequired : total)})
            .eq('id', user.id);
        await client.from('holdings').insert({
          'user_id': user.id,
          'symbol': symbol,
          'market': market,
          'quantity': quantity,
          'avg_price': execPrice,
          'name': name,
          'instrument_type': instrumentType,
          'strike_price': strikePrice,
          'option_type': optionType,
          'expiry_date': expiryDate,
        });
      } else {
        final existingMap = Map<String, dynamic>.from(existing as Map);
        final oldQuantity = (existingMap['quantity'] as num).toDouble();
        final oldAvg = (existingMap['avg_price'] as num).toDouble();

        if (oldQuantity < 0) {
          // Covering short position
          final coverQty = quantity > -oldQuantity ? -oldQuantity : quantity;
          final remainingBuyQty = quantity - coverQty;

          realizedPnl += (oldAvg - execPrice) * coverQty;

          final double resultingBalance = profile.walletBalance +
              (isDerivative
                  ? (coverQty * oldAvg * marginPct + realizedPnl)
                  : -(coverQty * execPrice));

          if (resultingBalance < 0) {
            throw Exception('Insufficient wallet balance to cover short position.');
          }

          await client
              .from('profiles')
              .update({
                'wallet_balance': resultingBalance,
                'total_realized_pnl': profile.totalRealizedPnl + realizedPnl,
              })
              .eq('id', user.id);

          final newQty = oldQuantity + coverQty;
          if (newQty.abs() < 0.00000001) {
            await client
                .from('holdings')
                .delete()
                .eq('user_id', user.id)
                .eq('symbol', symbol)
                .eq('market', market);
          } else {
            await client
                .from('holdings')
                .update({'quantity': newQty})
                .eq('user_id', user.id)
                .eq('symbol', symbol)
                .eq('market', market);
          }

          if (remainingBuyQty > 0) {
            final remainingTotal = remainingBuyQty * execPrice;
            final remainingMargin = remainingTotal * marginPct;
            final updatedProfile = await getUserProfile();
            if (updatedProfile != null) {
              if (updatedProfile.walletBalance < remainingMargin) {
                throw Exception('Insufficient wallet balance for remaining buy. Required: ₹${remainingMargin.toStringAsFixed(0)}');
              }
              await client
                  .from('profiles')
                  .update({
                    'wallet_balance':
                        updatedProfile.walletBalance - (isDerivative ? remainingMargin : remainingTotal),
                  })
                  .eq('id', user.id);
              await client.from('holdings').insert({
                'user_id': user.id,
                'symbol': symbol,
                'market': market,
                'quantity': remainingBuyQty,
                'avg_price': execPrice,
                'name': name,
                'instrument_type': instrumentType,
                'strike_price': strikePrice,
                'option_type': optionType,
                'expiry_date': expiryDate,
              });
            }
          }
        } else {
          // Adding to long position
          if (profile.walletBalance < marginRequired) {
            throw Exception('Insufficient wallet balance. Required margin: ₹${marginRequired.toStringAsFixed(0)}');
          }
          await client
              .from('profiles')
              .update({'wallet_balance': profile.walletBalance - (isDerivative ? marginRequired : total)})
              .eq('id', user.id);
          final newQuantity = oldQuantity + quantity;
          final newAvg = newQuantity > 0
              ? ((oldAvg * oldQuantity) + (execPrice * quantity)) / newQuantity
              : execPrice;
          await client
              .from('holdings')
              .update({
                'quantity': newQuantity,
                'avg_price': newAvg,
                'name': name,
              })
              .eq('user_id', user.id)
              .eq('symbol', symbol)
              .eq('market', market);
        }
      }
    } else {
      final existing = await client
          .from('holdings')
          .select()
          .eq('user_id', user.id)
          .eq('symbol', symbol)
          .eq('market', market)
          .maybeSingle();
      if (existing == null) {
        // Open new short position — require margin
        if (profile.walletBalance < marginRequired) {
          throw Exception('Insufficient margin to short sell. Required: ₹${marginRequired.toStringAsFixed(0)}');
        }
        // For derivatives: block margin from wallet; for equity: credit sale proceeds
        final double walletDelta = isDerivative ? -marginRequired : total;
        await client
            .from('profiles')
            .update({'wallet_balance': profile.walletBalance + walletDelta})
            .eq('id', user.id);
        await client.from('holdings').insert({
          'user_id': user.id,
          'symbol': symbol,
          'market': market,
          'quantity': -quantity,
          'avg_price': execPrice,
          'name': name,
          'instrument_type': instrumentType,
          'strike_price': strikePrice,
          'option_type': optionType,
          'expiry_date': expiryDate,
        });
      } else {
        final existingMap = Map<String, dynamic>.from(existing as Map);
        final oldQuantity = (existingMap['quantity'] as num).toDouble();
        final oldAvg = (existingMap['avg_price'] as num).toDouble();

        if (oldQuantity > 0) {
          // Selling to close/reduce long position
          final sellQty = quantity > oldQuantity ? oldQuantity : quantity;
          final remainingSellQty = quantity - sellQty;

          realizedPnl += (execPrice - oldAvg) * sellQty;
          await client
              .from('profiles')
              .update({
                'wallet_balance': profile.walletBalance + (isDerivative ? (sellQty * oldAvg * marginPct + realizedPnl) : (sellQty * execPrice)),
                'total_realized_pnl': profile.totalRealizedPnl + realizedPnl,
              })
              .eq('id', user.id);

          final newQty = oldQuantity - sellQty;
          if (newQty.abs() < 0.00000001) {
            await client
                .from('holdings')
                .delete()
                .eq('user_id', user.id)
                .eq('symbol', symbol)
                .eq('market', market);
          } else {
            await client
                .from('holdings')
                .update({'quantity': newQty, 'avg_price': oldAvg, 'name': name})
                .eq('user_id', user.id)
                .eq('symbol', symbol)
                .eq('market', market);
          }

          if (remainingSellQty > 0) {
            final remainingTotal = remainingSellQty * execPrice;
            final remainingMargin = remainingTotal * marginPct;
            final updatedProfile = await getUserProfile();
            if (updatedProfile != null) {
              if (updatedProfile.walletBalance < remainingMargin) {
                throw Exception('Insufficient margin for remaining short. Required: ₹${remainingMargin.toStringAsFixed(0)}');
              }
              await client
                  .from('profiles')
                  .update({
                    'wallet_balance':
                        updatedProfile.walletBalance - remainingMargin,
                  })
                  .eq('id', user.id);
              await client.from('holdings').insert({
                'user_id': user.id,
                'symbol': symbol,
                'market': market,
                'quantity': -remainingSellQty,
                'avg_price': execPrice,
                'name': name,
                'instrument_type': instrumentType,
                'strike_price': strikePrice,
                'option_type': optionType,
                'expiry_date': expiryDate,
              });
            }
          }
        } else {
          // Adding to existing short position
          if (profile.walletBalance < marginRequired) {
            throw Exception('Insufficient margin to add to short. Required: ₹${marginRequired.toStringAsFixed(0)}');
          }
          await client
              .from('profiles')
              .update({'wallet_balance': profile.walletBalance - (isDerivative ? marginRequired : -total)})
              .eq('id', user.id);
          final newQuantity = oldQuantity - quantity;
          final oldQtyAbs = oldQuantity.abs();
          final newAvg = (oldQtyAbs + quantity) > 0
              ? ((oldAvg * oldQtyAbs) + (execPrice * quantity)) /
                    (oldQtyAbs + quantity)
              : execPrice;
          await client
              .from('holdings')
              .update({
                'quantity': newQuantity,
                'avg_price': newAvg,
                'name': name,
              })
              .eq('user_id', user.id)
              .eq('symbol', symbol)
              .eq('market', market);
        }
      }
    }

    final order = await client
        .from('orders')
        .insert({
          'user_id': user.id,
          'symbol': symbol,
          'name': name,
          'market': market,
          'side': side,
          'quantity': quantity,
          'price': execPrice,
          'total': total,
          'realized_pnl': realizedPnl,
          'status': 'executed',
          'order_type': isMarket ? 'market' : 'limit',
          'executed_at': DateTime.now().toUtc().toIso8601String(),
          'instrument_type': instrumentType,
          'strike_price': strikePrice,
          'option_type': optionType,
          'expiry_date': expiryDate,
        })
        .select()
        .maybeSingle();

    if (order == null) throw Exception('Could not place order');
    final placedOrder = Order.fromJson(Map<String, dynamic>.from(order as Map));

    try {
      await client.from('notifications').insert({
        'user_id': user.id,
        'title': 'Order Executed',
        'body':
            '${side.toUpperCase()} ${quantity.toStringAsFixed(market == "crypto" ? 4 : 0)} $symbol filled at ₹${execPrice.toStringAsFixed(2)}',
        'is_read': false,
        'action_type': 'order',
        'action_data': {'symbol': symbol, 'market': market},
      });
    } catch (_) {}

    return placedOrder;
  }

  Future<List<Order>> executePendingOrders() async {
    if (!MarketHours.isOpen('stock') && !MarketHours.isOpen('crypto')) {
      return [];
    }
    final user = currentUser;
    if (user == null) return [];

    final executedOrders = <Order>[];
    final pending = await client
        .from('orders')
        .select()
        .eq('user_id', user.id)
        .eq('status', 'pending');
    for (final raw in (pending as List<dynamic>)) {
      final row = Map<String, dynamic>.from(raw as Map);
      final id = row['id'] as String;
      final symbol = row['symbol'] as String;
      final market = row['market'] as String? ?? 'stock';
      final side = row['side'] as String;
      final quantity = (row['quantity'] as num).toDouble();
      final instrumentType = row['instrument_type'] as String? ?? 'EQUITY';
      final strikePrice = (row['strike_price'] as num?)?.toDouble();
      final optionType = row['option_type'] as String?;
      final expiryDate = row['expiry_date'] as String?;
      final orderType = row['order_type'] as String? ?? 'market';
      final limitPrice = (row['price'] as num?)?.toDouble() ?? 0.0;

      if (!MarketHours.isOpen(market)) continue;

      try {
        double execPrice = 0.0;
        String name = symbol;

        final quote = await MarketService.quote(symbol, market);
        if (quote == null) continue;
        execPrice = quote.price;
        name = quote.name;

        if (orderType == 'limit') {
          if (side == 'buy' && execPrice > limitPrice) {
            continue;
          }
          if (side == 'sell' && execPrice < limitPrice) {
            continue;
          }
        }

        final total = execPrice * quantity;
        final bool isDerivative = instrumentType == 'FUTURE' || instrumentType == 'OPTION';
        final double marginPct = isDerivative ? 0.15 : 1.0;
        final double marginRequired = total * marginPct;

        final profile = await getUserProfile();
        if (profile == null) continue;

        double realizedPnl = 0.0;

        if (side == 'buy') {
          final existing = await client
              .from('holdings')
              .select()
              .eq('user_id', user.id)
              .eq('symbol', symbol)
              .eq('market', market)
              .maybeSingle();
          if (existing == null) {
            if (profile.walletBalance < marginRequired) continue;
            await client
                .from('profiles')
                .update({'wallet_balance': profile.walletBalance - (isDerivative ? marginRequired : total)})
                .eq('id', user.id);
            await client.from('holdings').insert({
              'user_id': user.id,
              'symbol': symbol,
              'market': market,
              'quantity': quantity,
              'avg_price': execPrice,
              'name': name,
              'instrument_type': instrumentType,
              'strike_price': strikePrice,
              'option_type': optionType,
              'expiry_date': expiryDate,
            });
          } else {
            final m = Map<String, dynamic>.from(existing as Map);
            final oq = (m['quantity'] as num).toDouble();
            final oa = (m['avg_price'] as num).toDouble();

            if (oq < 0) {
              // Covering short position
              final coverQty = quantity > -oq ? -oq : quantity;
              final remainingBuyQty = quantity - coverQty;

              if (profile.walletBalance < (coverQty * execPrice)) continue;

              realizedPnl += (oa - execPrice) * coverQty;

              await client
                  .from('profiles')
                  .update({
                    'wallet_balance':
                        profile.walletBalance - (coverQty * execPrice),
                    'total_realized_pnl':
                        profile.totalRealizedPnl + realizedPnl,
                  })
                  .eq('id', user.id);

              final newQty = oq + coverQty;
              if (newQty.abs() < 0.00000001) {
                await client
                    .from('holdings')
                    .delete()
                    .eq('user_id', user.id)
                    .eq('symbol', symbol)
                    .eq('market', market);
              } else {
                await client
                    .from('holdings')
                    .update({'quantity': newQty})
                    .eq('user_id', user.id)
                    .eq('symbol', symbol)
                    .eq('market', market);
              }

              if (remainingBuyQty > 0) {
                final remainingTotal = remainingBuyQty * execPrice;
                final remainingMargin = remainingTotal * marginPct;
                final updatedProfile = await getUserProfile();
                if (updatedProfile != null &&
                    updatedProfile.walletBalance >= remainingMargin) {
                  await client
                      .from('profiles')
                      .update({
                        'wallet_balance':
                            updatedProfile.walletBalance - (isDerivative ? remainingMargin : remainingTotal),
                      })
                      .eq('id', user.id);
                  await client.from('holdings').insert({
                    'user_id': user.id,
                    'symbol': symbol,
                    'market': market,
                    'quantity': remainingBuyQty,
                    'avg_price': execPrice,
                    'name': name,
                    'instrument_type': instrumentType,
                    'strike_price': strikePrice,
                    'option_type': optionType,
                    'expiry_date': expiryDate,
                  });
                }
              }
            } else {
              if (profile.walletBalance < marginRequired) continue;
              await client
                  .from('profiles')
                  .update({'wallet_balance': profile.walletBalance - (isDerivative ? marginRequired : total)})
                  .eq('id', user.id);
              final nq = oq + quantity;
              final na = nq > 0
                  ? ((oa * oq) + (execPrice * quantity)) / nq
                  : execPrice;
              await client
                  .from('holdings')
                  .update({'quantity': nq, 'avg_price': na, 'name': name})
                  .eq('user_id', user.id)
                  .eq('symbol', symbol)
                  .eq('market', market);
            }
          }
        } else {
          final existing = await client
              .from('holdings')
              .select()
              .eq('user_id', user.id)
              .eq('symbol', symbol)
              .eq('market', market)
              .maybeSingle();
          if (existing == null) {
            // Open new short position
            if (profile.walletBalance < marginRequired) continue;
            final double walletDelta = isDerivative ? -marginRequired : total;
            await client
                .from('profiles')
                .update({'wallet_balance': profile.walletBalance + walletDelta})
                .eq('id', user.id);
            await client.from('holdings').insert({
              'user_id': user.id,
              'symbol': symbol,
              'market': market,
              'quantity': -quantity,
              'avg_price': execPrice,
              'name': name,
              'instrument_type': instrumentType,
              'strike_price': strikePrice,
              'option_type': optionType,
              'expiry_date': expiryDate,
            });
          } else {
            final m = Map<String, dynamic>.from(existing as Map);
            final oq = (m['quantity'] as num).toDouble();
            final oa = (m['avg_price'] as num).toDouble();

            if (oq > 0) {
              // Selling to close/reduce long position
              final sellQty = quantity > oq ? oq : quantity;
              final remainingSellQty = quantity - sellQty;

              realizedPnl += (execPrice - oa) * sellQty;
              await client
                  .from('profiles')
                  .update({
                    'wallet_balance':
                        profile.walletBalance + (isDerivative ? (sellQty * oa * marginPct + realizedPnl) : (sellQty * execPrice)),
                    'total_realized_pnl':
                        profile.totalRealizedPnl + realizedPnl,
                  })
                  .eq('id', user.id);

              final newQty = oq - sellQty;
              if (newQty.abs() < 0.00000001) {
                await client
                    .from('holdings')
                    .delete()
                    .eq('user_id', user.id)
                    .eq('symbol', symbol)
                    .eq('market', market);
              } else {
                await client
                    .from('holdings')
                    .update({'quantity': newQty, 'avg_price': oa, 'name': name})
                    .eq('user_id', user.id)
                    .eq('symbol', symbol)
                    .eq('market', market);
              }

              if (remainingSellQty > 0) {
                final remainingTotal = remainingSellQty * execPrice;
                final remainingMargin = remainingTotal * marginPct;
                final updatedProfile = await getUserProfile();
                if (updatedProfile != null &&
                    updatedProfile.walletBalance >= remainingMargin) {
                  await client
                      .from('profiles')
                      .update({
                        'wallet_balance':
                            updatedProfile.walletBalance - remainingMargin,
                      })
                      .eq('id', user.id);
                  await client.from('holdings').insert({
                    'user_id': user.id,
                    'symbol': symbol,
                    'market': market,
                    'quantity': -remainingSellQty,
                    'avg_price': execPrice,
                    'name': name,
                    'instrument_type': instrumentType,
                    'strike_price': strikePrice,
                    'option_type': optionType,
                    'expiry_date': expiryDate,
                  });
                }
              }
            } else {
              // Adding to short position
              if (profile.walletBalance < marginRequired) continue;
              await client
                  .from('profiles')
                  .update({'wallet_balance': profile.walletBalance - (isDerivative ? marginRequired : -total)})
                  .eq('id', user.id);
              final nq = oq - quantity;
              final oqAbs = oq.abs();
              final na = (oqAbs + quantity) > 0
                  ? ((oa * oqAbs) + (execPrice * quantity)) / (oqAbs + quantity)
                  : execPrice;
              await client
                  .from('holdings')
                  .update({'quantity': nq, 'avg_price': na, 'name': name})
                  .eq('user_id', user.id)
                  .eq('symbol', symbol)
                  .eq('market', market);
            }
          }
        }

        final updatedOrder = await client
            .from('orders')
            .update({
              'status': 'executed',
              'price': execPrice,
              'total': total,
              'realized_pnl': realizedPnl,
              'executed_at': DateTime.now().toUtc().toIso8601String(),
            })
            .eq('id', id)
            .select()
            .maybeSingle();

        if (updatedOrder != null) {
          final execOrder = Order.fromJson(
            Map<String, dynamic>.from(updatedOrder as Map),
          );
          executedOrders.add(execOrder);

          try {
            await client.from('notifications').insert({
              'user_id': user.id,
              'title': 'Order Executed',
              'body':
                  '${side.toUpperCase()} ${quantity.toStringAsFixed(market == "crypto" ? 4 : 0)} $symbol filled at ₹${execPrice.toStringAsFixed(2)}',
              'is_read': false,
              'action_type': 'order',
              'action_data': {'symbol': symbol, 'market': market},
            });
          } catch (_) {}
        }
      } catch (_) {}
    }
    return executedOrders;
  }

  Future<void> cancelOrder(String orderId) async {
    await client
        .from('orders')
        .update({'status': 'cancelled'})
        .eq('id', orderId);
  }

  Future<void> modifyOrder({
    required String orderId,
    required double quantity,
    required double price,
  }) async {
    final total = quantity * price;
    await client
        .from('orders')
        .update({'quantity': quantity, 'price': price, 'total': total})
        .eq('id', orderId);
  }

  Future<Map<String, dynamic>> createSubscriptionOrder(String planId) async {
    final plans = {
      'titan_1l': {
        'id': 'titan_1l',
        'name': 'Starter Boost',
        'price': 199,
        'cash': 100000,
        'is_mock': true,
      },
      'titan_5l': {
        'id': 'titan_5l',
        'name': 'Titan Plus',
        'price': 599,
        'cash': 500000,
        'is_mock': true,
      },
      'titan_pro': {
        'id': 'titan_pro',
        'name': 'Pro Launch',
        'price': 999,
        'cash': 1000000,
        'is_mock': true,
      },
    };
    final plan = plans[planId] ?? plans['titan_1l']!;
    return {
      'id': '${plan['id']}_${DateTime.now().millisecondsSinceEpoch}',
      'plan': plan,
      'is_mock': true,
    };
  }

  Future<Map<String, dynamic>> activateSubscription({
    required String planId,
    String? orderId,
  }) async {
    final user = currentUser;
    if (user == null) {
      throw Exception('No authenticated user');
    }

    final profile = await getUserProfile();
    if (profile == null) {
      throw Exception('Profile not found');
    }

    final planCash = planId == 'titan_5l'
        ? 500000.0
        : planId == 'titan_pro'
        ? 1000000.0
        : 100000.0;
    await client
        .from('profiles')
        .update({
          'wallet_balance': profile.walletBalance + planCash,
          'subscription_active': true,
          'plan': planId,
        })
        .eq('id', user.id);

    return {
      'message':
          'Subscription activated and ₹${planCash.toStringAsFixed(0)} credited to your wallet.',
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

    await client
        .from('profiles')
        .update({'wallet_balance': profile.walletBalance + amount})
        .eq('id', user.id);
  }

  Future<void> purchasePackage(
    String packageName,
    double packagePrice,
    double cashAmount,
  ) async {
    final user = currentUser;
    if (user == null) {
      throw Exception('No authenticated user');
    }

    final profile = await getUserProfile();
    if (profile == null) {
      throw Exception('Profile not found');
    }

    // 1. Credit the user's wallet
    await client
        .from('profiles')
        .update({'wallet_balance': profile.walletBalance + cashAmount})
        .eq('id', user.id);

    // 2. Check if user was referred by someone
    if (profile.referredBy != null && profile.referredBy!.isNotEmpty) {
      final commissionAmt = 0.2 * packagePrice;
      await client.from('referral_commissions').insert({
        'referrer_id': profile.referredBy,
        'referred_id': user.id,
        'package_name': packageName,
        'package_price': packagePrice,
        'commission_amount': commissionAmt,
        'status': 'unclaimed',
      });
    }
  }

  Future<List<Map<String, dynamic>>> getHistory(
    String symbol,
    String market,
    String range,
  ) async {
    return await MarketService.getHistory(symbol, market, range);
  }

  Future<void> submitSupportTicket({
    required String type,
    required String title,
    required String content,
    String? imageUrl,
  }) async {
    final user = currentUser;
    if (user == null) throw Exception('No authenticated user');
    await client.from('support_tickets').insert({
      'user_id': user.id,
      'email': user.email ?? 'unknown',
      'type': type,
      'title': title,
      'content': content,
      'image_url': imageUrl,
    });
  }

  Future<String?> uploadTicketAttachment(String path, Uint8List bytes) async {
    final user = currentUser;
    if (user == null) return null;
    final fileExtension = path.split('.').last;
    final fileName =
        '${user.id}_${DateTime.now().millisecondsSinceEpoch}.$fileExtension';

    await client.storage
        .from('support_attachments')
        .uploadBinary(
          fileName,
          bytes,
          fileOptions: FileOptions(
            contentType: fileExtension == 'png' ? 'image/png' : 'image/jpeg',
            upsert: true,
          ),
        );

    return client.storage.from('support_attachments').getPublicUrl(fileName);
  }

  Future<List<Map<String, dynamic>>> getSupportTickets() async {
    final rows = await client
        .from('support_tickets')
        .select('*')
        .order('created_at', ascending: false);
    return (rows as List<dynamic>)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }
  Future<void> toggleTicketResolved(String ticketId, bool resolved) async {
    await client.from('support_tickets').update({
      'resolved': resolved,
    }).eq('id', ticketId);
  }

  Future<void> sendReward({
    required String email,
    required double amount,
    required String message,
  }) async {
    // 1. Find profile by email
    final profile = await client
        .from('profiles')
        .select('id')
        .eq('email', email.trim().toLowerCase())
        .maybeSingle();

    if (profile == null) {
      throw Exception('No account found with email $email');
    }

    final targetUserId = profile['id'] as String;

    // 2. Insert rewards record
    await client.from('rewards').insert({
      'user_id': targetUserId,
      'amount': amount,
      'message': message,
      'is_claimed': false,
    });

    // 3. Create notification for the user
    await client.from('notifications').insert({
      'user_id': targetUserId,
      'title': 'Bug Bounty Reward Received! 🎉',
      'body': 'You have been awarded ₹${amount.toStringAsFixed(0)}: $message',
      'is_read': false,
      'action_type': 'reward',
    });
  }

  Future<List<Map<String, dynamic>>> checkUnclaimedRewards() async {
    final user = currentUser;
    if (user == null) return [];
    final rows = await client
        .from('rewards')
        .select('*')
        .eq('user_id', user.id)
        .eq('is_claimed', false);
    return (rows as List<dynamic>)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<void> claimReward(String rewardId, double amount) async {
    final user = currentUser;
    if (user == null) throw Exception('No authenticated user');

    // 1. Mark reward as claimed
    await client.from('rewards').update({
      'is_claimed': true,
    }).eq('id', rewardId);

    // 2. Add to user profile wallet balance
    final profile = await getUserProfile();
    if (profile != null) {
      final newBalance = profile.walletBalance + amount;
      await client.from('profiles').update({
        'wallet_balance': newBalance,
      }).eq('id', user.id);
    }
  }

  Future<void> sendCustomNotification({
    required String email,
    required String title,
    required String body,
    String? imageUrl,
  }) async {
    final profile = await client
        .from('profiles')
        .select('id')
        .eq('email', email.trim().toLowerCase())
        .maybeSingle();

    if (profile == null) {
      throw Exception('No account found with email $email');
    }

    final targetUserId = profile['id'] as String;

    await client.from('notifications').insert({
      'user_id': targetUserId,
      'title': title,
      'body': body,
      'is_read': false,
      'action_type': 'custom',
      if (imageUrl != null) 'action_data': {'image_url': imageUrl},
    });
  }

  Future<void> sendBroadcastNotification({
    required String title,
    required String body,
    String? imageUrl,
  }) async {
    final profiles = await client.from('profiles').select('id');
    if (profiles == null) return;
    final list = profiles as List<dynamic>;
    if (list.isEmpty) return;

    final inserts = list.map((profile) {
      final userId = profile['id'] as String;
      return {
        'user_id': userId,
        'title': title,
        'body': body,
        'is_read': false,
        'action_type': 'broadcast',
        if (imageUrl != null) 'action_data': {'image_url': imageUrl},
      };
    }).toList();

    for (var i = 0; i < inserts.length; i += 100) {
      final chunk = inserts.sublist(i, i + 100 > inserts.length ? inserts.length : i + 100);
      await client.from('notifications').insert(chunk);
    }
  }
}
