import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user.dart' as app_models;
import '../models/portfolio.dart';
import '../models/order.dart';
import '../models/quote.dart';
import '../models/position_model.dart';
import '../models/price_alert.dart';
import '../core/market_hours.dart';
import '../core/option_pricing.dart';
import 'market_service.dart';
import 'fo_instruments_service.dart';
import 'firebase_service.dart';
import 'notification_service.dart';

class SupabaseService {
  static final SupabaseService _instance = SupabaseService._internal();
  factory SupabaseService() => _instance;
  SupabaseService._internal();

  final SupabaseClient client = Supabase.instance.client;

  Map<String, dynamic>? _activeChargeConfig;
  String? _activeChargeConfigId;

  static const Map<String, dynamic> defaultChargeRates = {
    "equity_brokerage_rate": 0.0005,
    "equity_brokerage_max": 20.00,
    "fo_brokerage_flat": 20.00,
    "stamp_duty_delivery": 0.00015,
    "stamp_duty_intraday": 0.00003,
    "stamp_duty_options": 0.00003,
    "stamp_duty_futures": 0.00002,
    "stt_delivery": 0.001,
    "stt_intraday_sell": 0.00025,
    "stt_options_sell": 0.000625,
    "stt_futures_sell": 0.000125,
    "exchange_delivery": 0.0000322,
    "exchange_options": 0.00053,
    "exchange_futures": 0.000019,
    "gst_rate": 0.18,
    "clearing_fee_rate": 0.000002,
    "sebi_regulatory_fee_rate": 0.000001,
    "turnover_tax_rate": 0.000001,
    "dp_charges_flat": 13.50,
    "other_broker_fee_flat": 0.0
  };

  Future<void> fetchActiveChargeConfig() async {
    try {
      final res = await client
          .from('charge_configurations')
          .select('id, config')
          .order('effective_from', ascending: false)
          .limit(1)
          .maybeSingle();
      if (res != null) {
        _activeChargeConfigId = res['id'] as String?;
        _activeChargeConfig = Map<String, dynamic>.from(res['config'] as Map);
      }
    } catch (e) {
      debugPrint('Failed to load charge configurations: $e');
    }
  }

  Map<String, double> calculateTransactionCharges({
    required String instrumentType,
    required String side,
    required double quantity,
    required double price,
    required bool isIntraday,
  }) {
    final config = _activeChargeConfig ?? defaultChargeRates;
    final totalValue = price * quantity;

    double brokerage = 0.0;
    double stampDuty = 0.0;
    double stt = 0.0;
    double exchangeCharges = 0.0;

    if (instrumentType == 'EQUITY') {
      final rate = (config['equity_brokerage_rate'] as num?)?.toDouble() ?? 0.0005;
      final maxB = (config['equity_brokerage_max'] as num?)?.toDouble() ?? 20.0;
      brokerage = totalValue * rate;
      if (brokerage > maxB) brokerage = maxB;

      if (side == 'buy') {
        final sdRate = isIntraday
            ? ((config['stamp_duty_intraday'] as num?)?.toDouble() ?? 0.00003)
            : ((config['stamp_duty_delivery'] as num?)?.toDouble() ?? 0.00015);
        stampDuty = totalValue * sdRate;
      }

      if (isIntraday) {
        if (side == 'sell') {
          final sttRate = (config['stt_intraday_sell'] as num?)?.toDouble() ?? 0.00025;
          stt = totalValue * sttRate;
        }
      } else {
        final sttRate = (config['stt_delivery'] as num?)?.toDouble() ?? 0.001;
        stt = totalValue * sttRate;
      }

      final exRate = (config['exchange_delivery'] as num?)?.toDouble() ?? 0.0000322;
      exchangeCharges = totalValue * exRate;

    } else if (instrumentType == 'FUTURE') {
      brokerage = (config['fo_brokerage_flat'] as num?)?.toDouble() ?? 20.0;

      if (side == 'buy') {
        final sdRate = (config['stamp_duty_futures'] as num?)?.toDouble() ?? 0.00002;
        stampDuty = totalValue * sdRate;
      }

      if (side == 'sell') {
        final sttRate = (config['stt_futures_sell'] as num?)?.toDouble() ?? 0.000125;
        stt = totalValue * sttRate;
      }

      final exRate = (config['exchange_futures'] as num?)?.toDouble() ?? 0.000019;
      exchangeCharges = totalValue * exRate;

    } else if (instrumentType == 'OPTION') {
      brokerage = (config['fo_brokerage_flat'] as num?)?.toDouble() ?? 20.0;

      if (side == 'buy') {
        final sdRate = (config['stamp_duty_options'] as num?)?.toDouble() ?? 0.00003;
        stampDuty = totalValue * sdRate;
      }

      if (side == 'sell') {
        final sttRate = (config['stt_options_sell'] as num?)?.toDouble() ?? 0.000625;
        stt = totalValue * sttRate;
      }

      final exRate = (config['exchange_options'] as num?)?.toDouble() ?? 0.00053;
      exchangeCharges = totalValue * exRate;
    }

    final clearingFeeRate = (config['clearing_fee_rate'] as num?)?.toDouble() ?? 0.000002;
    final sebiFeeRate = (config['sebi_regulatory_fee_rate'] as num?)?.toDouble() ?? 0.000001;
    final turnoverTaxRate = (config['turnover_tax_rate'] as num?)?.toDouble() ?? 0.000001;
    final dpChargesFlat = (config['dp_charges_flat'] as num?)?.toDouble() ?? 13.50;
    final otherBrokerFeeFlat = (config['other_broker_fee_flat'] as num?)?.toDouble() ?? 0.0;

    final clearingFee = totalValue * clearingFeeRate;
    final sebiRegulatoryFee = totalValue * sebiFeeRate;
    final turnoverTax = totalValue * turnoverTaxRate;
    final dpCharges = (instrumentType == 'EQUITY' && side == 'sell' && !isIntraday) ? dpChargesFlat : 0.0;
    final otherBrokerFee = otherBrokerFeeFlat;

    final gstRate = (config['gst_rate'] as num?)?.toDouble() ?? 0.18;
    final gst = (brokerage + exchangeCharges + clearingFee + sebiRegulatoryFee + turnoverTax + otherBrokerFee) * gstRate;

    final taxCharges = stt + exchangeCharges + gst + clearingFee + sebiRegulatoryFee + turnoverTax;
    final totalCharges = brokerage + stampDuty + taxCharges + dpCharges + otherBrokerFee;

    return {
      'brokerage': (brokerage * 100).roundToDouble() / 100.0,
      'stamp_duty': (stampDuty * 100).roundToDouble() / 100.0,
      'stt': (stt * 100).roundToDouble() / 100.0,
      'exchange_charges': (exchangeCharges * 100).roundToDouble() / 100.0,
      'clearing_fee': (clearingFee * 100).roundToDouble() / 100.0,
      'sebi_regulatory_fee': (sebiRegulatoryFee * 100).roundToDouble() / 100.0,
      'turnover_tax': (turnoverTax * 100).roundToDouble() / 100.0,
      'dp_charges': (dpCharges * 100).roundToDouble() / 100.0,
      'other_broker_fee': (otherBrokerFee * 100).roundToDouble() / 100.0,
      'gst': (gst * 100).roundToDouble() / 100.0,
      'tax_charges': (taxCharges * 100).roundToDouble() / 100.0,
      'total_charges': (totalCharges * 100).roundToDouble() / 100.0,
    };
  }

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
    await fetchActiveChargeConfig();
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

    try {
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
    } catch (e) {
      // Offline / DNS failure: degrade gracefully to last cached profile.
      if (FirebaseService.isTransientNetworkError(e)) {
        debugPrint('getUserProfile offline, using cache: $e');
        return getCachedUserProfile();
      }
      rethrow;
    }
  }

  Future<Map<String, String>> getAppVersionConfig() async {
    try {
      final data = await client.from('app_config').select('key, value');
      final Map<String, String> config = {};
      for (final row in (data as List<dynamic>)) {
        final r = Map<String, dynamic>.from(row as Map);
        final k = r['key']?.toString();
        final v = r['value']?.toString();
        if (k != null && v != null) {
          config[k] = v;
        }
      }
      return config;
    } catch (e) {
      debugPrint('Error getting app version config: $e');
      rethrow;
    }
  }

  Future<List<Order>> getOrders({int limit = 50}) async {
    await executePendingOrders();
    final user = currentUser;
    if (user == null) return [];

    try {
      final data = await client
          .from('orders')
          .select()
          .eq('user_id', user.id)
          .order('created_at', ascending: false)
          .limit(limit);

      return (data as List<dynamic>)
          .map((e) => Order.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (e) {
      // Offline / DNS failure: return empty list instead of crashing the UI.
      if (FirebaseService.isTransientNetworkError(e)) {
        debugPrint('getOrders offline: $e');
        return [];
      }
      rethrow;
    }
  }

  /// Settles expired option positions automatically.
  /// - ITM options: auto-exercised, intrinsic value credited/debited to wallet
  /// - OTM options: expire worthless, position removed
  Future<void> settleExpiredDerivatives() async {
    // Step 3: expiry settlement is server-side (settle-expired-positions cron).
    if (_serverExecOnly) return;
    final user = currentUser;
    if (user == null) return;

    final today = DateTime.now();
    final todayStr = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

    // Find all active derivative positions in fo_positions with expiry_date <= today
    final expiredOptionRows = await client
        .from('fo_positions')
        .select()
        .eq('user_id', user.id)
        .eq('is_settled', false)
        .eq('instrument_type', 'OPTION')
        .lte('expiry_date', todayStr);

    final expiredFutureRows = await client
        .from('fo_positions')
        .select()
        .eq('user_id', user.id)
        .eq('is_settled', false)
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
      final positionId = row['id'] as String;
      final symbol = row['symbol'] as String;
      final market = 'stock';
      final netQty = (row['net_qty'] as num).toDouble();
      final lotSize = (row['lot_size'] as num?)?.toDouble() ?? 1.0;
      final double quantity = netQty * lotSize;
      final avgPrice = (row['avg_entry_price'] as num).toDouble();
      final instType = row['instrument_type'] as String? ?? 'OPTION';
      final optionType = row['option_type'] as String? ?? 'CE';
      final strikePrice = (row['strike_price'] as num?)?.toDouble() ?? 0.0;
      final expiryDate = row['expiry_date'] as String? ?? todayStr;
      final blockedMargin = (row['margin_blocked'] as num?)?.toDouble() ?? 0.0;

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
      double walletChange = 0.0;
      double premiumReceivedLogVal = 0.0;
      String orderName = '';
      String notifTitle = '';
      String notifBody = '';
      String settlementType = 'OTM';
      double intrinsicValue = 0.0;

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
        settlementType = 'FUTURE_EXPIRY';

        // Return the blocked margin + P&L to wallet
        walletChange = blockedMargin + settlementPnl;
        walletBalance += walletChange;

      } else {
        // ── OPTIONS SETTLEMENT ──
        if (optionType == 'CE') {
          intrinsicValue = (spotPrice - strikePrice).clamp(0.0, double.infinity);
        } else {
          intrinsicValue = (strikePrice - spotPrice).clamp(0.0, double.infinity);
        }

        final bool isITM = intrinsicValue > 0;
        settlementType = isITM ? 'ITM' : 'OTM';

        if (quantity > 0) {
          // Long Option (buyer)
          // Realized P&L is (intrinsicValue - avgPrice) * quantity
          settlementPnl = (intrinsicValue - avgPrice) * quantity;
          // Wallet change: credit the full intrinsic value (since premium was already debited at entry)
          walletChange = intrinsicValue * quantity;
        } else {
          // Short Option (writer)
          // Realized P&L is (avgPrice - intrinsicValue) * quantity.abs()
          settlementPnl = (avgPrice - intrinsicValue) * quantity.abs();
          // Wallet change: release blocked margin and debit/pay the intrinsic value
          walletChange = blockedMargin - (intrinsicValue * quantity.abs());
          premiumReceivedLogVal = avgPrice * quantity.abs();
        }

        walletBalance += walletChange;
        orderName = '${isITM ? "ITM" : "OTM"} Expiry Settlement';
        notifTitle = isITM ? 'Option Exercised (ITM)' : 'Option Expired (OTM)';
        notifBody = isITM
            ? '$symbol expired ITM. Settlement P&L: ₹${settlementPnl.toStringAsFixed(2)}'
            : '$symbol expired OTM. Premium lost: ₹${(avgPrice * quantity.abs()).toStringAsFixed(2)}';
      }

      if (_activeChargeConfig == null) {
        await fetchActiveChargeConfig();
      }

      final Map<String, double> charges = (market == 'stock')
          ? calculateTransactionCharges(
              instrumentType: instType,
              side: quantity > 0 ? 'sell' : 'buy',
              quantity: quantity.abs(),
              price: spotPrice,
              isIntraday: false,
            )
          : {
              'brokerage': 0.0,
              'stamp_duty': 0.0,
              'tax_charges': 0.0,
              'total_charges': 0.0,
            };
      final totalCharges = charges['total_charges'] ?? 0.0;
      walletBalance -= totalCharges;
      walletChange -= totalCharges;

      totalRealizedPnl += settlementPnl - totalCharges;

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
          'charge_config_id': _activeChargeConfigId,
          'brokerage': charges['brokerage'],
          'stamp_duty': charges['stamp_duty'],
          'tax_charges': charges['tax_charges'],
          'total_charges': totalCharges,
        });

        // Insert immutable settlement ledger entry
        await client.from('settlement_ledger').insert({
          'user_id': user.id,
          'position_id': positionId,
          'symbol': symbol,
          'instrument_type': instType,
          'option_type': instType == 'OPTION' ? optionType : null,
          'strike_price': instType == 'OPTION' ? strikePrice : null,
          'expiry_date': expiryDate,
          'quantity': quantity.abs(),
          'avg_price': avgPrice,
          'settlement_type': settlementType,
          'intrinsic_value': instType == 'OPTION' ? intrinsicValue : 0.0,
          'premium_received': premiumReceivedLogVal,
          'margin_released': blockedMargin,
          'wallet_change': walletChange,
          'timestamp': DateTime.now().toUtc().toIso8601String(),
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

      // Settle the expired position in fo_positions
      await client.from('fo_positions').update({
        'is_settled': true,
        'settled_at': DateTime.now().toUtc().toIso8601String(),
        'settlement_price': spotPrice,
        'realized_pnl': settlementPnl,
      }).eq('id', positionId);
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

  Future<List<FoPosition>> getFoPositions() async {
    final user = currentUser;
    if (user == null) return [];

    try {
      final response = await client
          .from('fo_positions')
          .select()
          .eq('user_id', user.id)
          .eq('is_settled', false);

      final positions = (response as List<dynamic>)
          .map((e) => FoPosition.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();

      return positions;
    } catch (e) {
      debugPrint('Error getting F&O positions: $e');
      return [];
    }
  }

  double _normalCDF(double x) {
    final t = 1 / (1 + 0.2316419 * x.abs());
    final d = 0.3989422804 * math.exp(-x * x / 2);
    final p = d * t * (0.31938153 + t * (-0.356563782 + t * (1.781477937 + t * (-1.821255978 + t * 1.330274429))));
    return x >= 0 ? 1 - p : p;
  }

  double _blackScholes(String optionType, double spot, double strike, double T) {
    if (T <= 0) {
      if (optionType == 'CE') {
        return math.max(0.0, spot - strike);
      } else {
        return math.max(0.0, strike - spot);
      }
    }
    const r = 0.065;
    const sigma = 0.25;
    final d1 = (math.log(spot / strike) + (r + 0.5 * sigma * sigma) * T) / (sigma * math.sqrt(T));
    final d2 = d1 - sigma * math.sqrt(T);
    
    double price = 0.0;
    if (optionType == 'CE') {
      price = spot * _normalCDF(d1) - strike * math.exp(-r * T) * _normalCDF(d2);
    } else {
      price = strike * math.exp(-r * T) * _normalCDF(-d2) - spot * _normalCDF(-d1);
    }
    return math.max(0.05, (price * 100).round() / 100.0);
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
        .select('symbol, market, quantity, price, side, name, realized_pnl, total_charges')
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
      final totalCharges = (r['total_charges'] as num?)?.toDouble() ?? 0.0;

      symbolNames[key] = name;

      if (side == 'buy') {
        todayBuys[key] = (todayBuys[key] ?? 0.0) + q;
        todayBuyCost[key] = (todayBuyCost[key] ?? 0.0) + (q * p);
      } else if (side == 'sell') {
        todaySells[key] = (todaySells[key] ?? 0.0) + q;
        todaySellCost[key] = (todaySellCost[key] ?? 0.0) + (q * p);
      }
      
      todayRealizedPnl[key] = (todayRealizedPnl[key] ?? 0.0) + relPnl - totalCharges;
    }

    final List<dynamic> rows = [];
    try {
      final rawHoldings = await client.from('holdings').select().eq('user_id', user.id);
      rows.addAll(rawHoldings as List<dynamic>);
    } catch (e) {
      debugPrint('Error loading holdings: $e');
    }

    try {
      final rawFoPositions = await client
          .from('fo_positions')
          .select()
          .eq('user_id', user.id)
          .eq('is_settled', false);
      for (final foRow in (rawFoPositions as List<dynamic>)) {
        final f = Map<String, dynamic>.from(foRow as Map);
        final netQty = (f['net_qty'] as num?)?.toDouble() ?? 0.0;
        final lotSize = (f['lot_size'] as num?)?.toDouble() ?? 1.0;
        final avgEntryPrice = (f['avg_entry_price'] as num?)?.toDouble() ?? 0.0;
        final symbol = f['symbol'] as String? ?? '';
        
        rows.add({
          'id': f['id'],
          'user_id': f['user_id'],
          'symbol': symbol,
          'market': 'stock',
          'quantity': netQty * lotSize,
          'avg_price': avgEntryPrice,
          'name': symbol,
          'instrument_type': f['instrument_type'],
          'strike_price': f['strike_price'],
          'option_type': f['option_type'],
          'expiry_date': f['expiry_date'],
          'product_type': 'NRML',
          'created_at': f['created_at'],
        });
      }
    } catch (e) {
      debugPrint('Error merging F&O positions: $e');
    }

    final results = <Holding>[];
    final activeKeys = <String>{};
    final activeHoldingsMap = <String, Map<String, dynamic>>{};

    for (final raw in rows) {
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
      final key = keysToFetch[i];
      final q = fetchedQuotes[i];
      quotesMap[key] = q;
      if (q != null) {
        final parts = key.split('\x1F');
        final normSym = MarketService.normalizeSymbol(parts[0], parts[1]);
        quotesMap['$normSym\x1F${parts[1]}'] = q;
      }
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
        final underlyingKey = underlyingKeyMap[key]!;
        final uparts = underlyingKey.split('\x1F');
        final normUnderlyingKey = '${MarketService.normalizeSymbol(uparts[0], uparts[1])}\x1F${uparts[1]}';
        final underlyingQuote = quotesMap[underlyingKey] ?? quotesMap[normUnderlyingKey];
        
        final spotPrice = underlyingQuote?.price ?? 0.0;
        final spotPrevClose = underlyingQuote?.previousClose ?? spotPrice;
        final strikePrice = (activeRow?['strike_price'] as num?)?.toDouble() ?? 0.0;
        final optType = activeRow?['option_type'] as String? ?? 'CE';
        final expiryStr = activeRow?['expiry_date'] as String?;

        double daysLeft = 0.0;
        if (expiryStr != null) {
          try {
            final expiry = DateTime.parse(expiryStr);
            daysLeft = expiry.difference(now).inHours / 24.0;
          } catch (_) {}
        }
        final T = math.max(0.0001, daysLeft) / 365.0;
        currentPrice = _blackScholes(optType, spotPrice, strikePrice, T);

        final tYesterday = (math.max(0.0, daysLeft) + 1.0) / 365.0;
        previousClose = _blackScholes(optType, spotPrevClose, strikePrice, tYesterday);

        // If created today, override previousClose with avgPrice
        final createdAtStr = activeRow?['created_at'] as String?;
        if (createdAtStr != null) {
          try {
            final createdAt = DateTime.parse(createdAtStr).toLocal();
            final now = DateTime.now();
            if (createdAt.year == now.year && createdAt.month == now.month && createdAt.day == now.day) {
              previousClose = avgPrice;
            }
          } catch (_) {}
        }
      } else if (instType == 'FUTURE' && underlyingKeyMap.containsKey(key)) {
        // For futures: derive price from underlying spot + carry cost
        final underlyingKey = underlyingKeyMap[key]!;
        final uparts = underlyingKey.split('\x1F');
        final normUnderlyingKey = '${MarketService.normalizeSymbol(uparts[0], uparts[1])}\x1F${uparts[1]}';
        final underlyingQuote = quotesMap[underlyingKey] ?? quotesMap[normUnderlyingKey];
        
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

        // If created today, override previousClose with avgPrice
        final createdAtStr = activeRow?['created_at'] as String?;
        if (createdAtStr != null) {
          try {
            final createdAt = DateTime.parse(createdAtStr).toLocal();
            final now = DateTime.now();
            if (createdAt.year == now.year && createdAt.month == now.month && createdAt.day == now.day) {
              previousClose = avgPrice;
            }
          } catch (_) {}
        }
      } else {
        // For stocks/crypto: use direct quote
        final normKey = '${MarketService.normalizeSymbol(symbol, market)}\x1F$market';
        final currentQuote = quotesMap[key] ?? quotesMap[normKey];
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
    final parts = symbol.split('-');
    final isOption = parts.length >= 5 && (parts.last == 'CE' || parts.last == 'PE');
    final isFuture = symbol.contains(' FUT');

    if (market == 'stock' && (isOption || isFuture)) {
      final underlyingSymbol = isOption ? parts[0] : symbol.split(' ')[0];
      final spotQuote = await MarketService.quote(underlyingSymbol, market);
      if (spotQuote == null) return null;

      double price = 0.0;
      double previousClose = 0.0;

      if (isFuture) {
        price = OptionPricing.futurePrice(spot: spotQuote.price, daysToExpiry: 15.0);
        previousClose = OptionPricing.futurePrice(spot: spotQuote.previousClose, daysToExpiry: 15.0);
      } else {
        // Option — priced with the shared Black-Scholes estimator so the LTP
        // matches the portfolio screen and the limit-fill engine exactly.
        final strikePrice = double.tryParse(parts[4]) ?? 0.0;
        final optType = parts.last;

        double daysToExpiry = 7.0;
        final expiry = DateTime.tryParse(
          '${parts[1]}-${parts[2].padLeft(2, '0')}-${parts[3].padLeft(2, '0')}',
        );
        if (expiry != null) {
          daysToExpiry = expiry.difference(DateTime.now()).inHours / 24.0;
        }

        price = OptionPricing.optionPremium(
          optionType: optType,
          spot: spotQuote.price,
          strike: strikePrice,
          daysToExpiry: daysToExpiry,
        );
        previousClose = OptionPricing.optionPremium(
          optionType: optType,
          spot: spotQuote.previousClose,
          strike: strikePrice,
          daysToExpiry: daysToExpiry + 1.0,
        );
      }

      final change = price - previousClose;
      final changePct = previousClose > 0 ? (change / previousClose) * 100 : 0.0;

      return Quote(
        symbol: symbol,
        yfSymbol: symbol,
        name: symbol,
        price: price,
        previousClose: previousClose,
        change: change,
        changePct: changePct,
        currency: 'INR',
        market: 'stock',
      );
    }

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
      'name': name,
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

  // ── Price Alerts ──────────────────────────────────────────────────────────

  /// Creates a price alert. [direction] is 'above' or 'below'. The reference
  /// price (current price at creation) is stored for context.
  Future<PriceAlert?> createPriceAlert({
    required String symbol,
    required String market,
    String? name,
    required double targetPrice,
    required String direction,
    double? referencePrice,
  }) async {
    final user = currentUser;
    if (user == null) return null;
    final row = await client
        .from('price_alerts')
        .insert({
          'user_id': user.id,
          'symbol': symbol,
          'market': market,
          'name': name,
          'target_price': targetPrice,
          'direction': direction,
          'reference_price': referencePrice,
          'status': 'active',
        })
        .select()
        .maybeSingle();
    if (row == null) return null;
    return PriceAlert.fromJson(Map<String, dynamic>.from(row as Map));
  }

  /// Returns the user's price alerts, newest first. When [symbol] is provided,
  /// only alerts for that symbol are returned. When [activeOnly] is true, only
  /// alerts with status 'active' are returned.
  Future<List<PriceAlert>> getPriceAlerts({
    String? symbol,
    String? market,
    bool activeOnly = false,
  }) async {
    final user = currentUser;
    if (user == null) return [];
    try {
      var query = client.from('price_alerts').select().eq('user_id', user.id);
      if (symbol != null) query = query.eq('symbol', symbol);
      if (market != null) query = query.eq('market', market);
      if (activeOnly) query = query.eq('status', 'active');
      final data = await query.order('created_at', ascending: false);
      return (data as List<dynamic>)
          .map((e) => PriceAlert.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (e) {
      if (FirebaseService.isTransientNetworkError(e)) return [];
      rethrow;
    }
  }

  /// Permanently deletes a price alert.
  Future<void> deletePriceAlert(String id) async {
    final user = currentUser;
    if (user == null) return;
    await client
        .from('price_alerts')
        .delete()
        .eq('id', id)
        .eq('user_id', user.id);
  }

  /// Evaluates all active price alerts against the latest quotes. When a
  /// target is crossed, fires a local + in-app notification and marks the
  /// alert 'triggered'. Safe to call on every refresh cycle: it returns early
  /// when the user has no active alerts and never throws on network errors.
  Future<void> evaluatePriceAlerts() async {
    final user = currentUser;
    if (user == null) return;
    try {
      final alerts = await getPriceAlerts(activeOnly: true);
      if (alerts.isEmpty) return;

      // Fetch one quote per unique (symbol, market) pair.
      final uniqueKeys = <String, PriceAlert>{};
      for (final a in alerts) {
        uniqueKeys['${a.symbol}\x1F${a.market}'] = a;
      }
      final priceBySymbol = <String, double>{};
      await Future.wait(uniqueKeys.values.map((a) async {
        try {
          final q = await MarketService.quote(a.symbol, a.market);
          if (q != null && q.price > 0) {
            priceBySymbol['${a.symbol}\x1F${a.market}'] = q.price;
          }
        } catch (_) {}
      }));

      for (final alert in alerts) {
        final price = priceBySymbol['${alert.symbol}\x1F${alert.market}'];
        if (price == null) continue;

        final crossed = alert.isAbove
            ? price >= alert.targetPrice
            : price <= alert.targetPrice;
        if (!crossed) continue;

        // Mark triggered first (atomic guard): only proceed if THIS call wins
        // the active->triggered transition, so the notification fires once.
        final claim = await client
            .from('price_alerts')
            .update({
              'status': 'triggered',
              'triggered_at': DateTime.now().toUtc().toIso8601String(),
            })
            .eq('id', alert.id)
            .eq('status', 'active')
            .select();
        if ((claim as List).isEmpty) continue;

        final displaySymbol = (alert.name?.isNotEmpty ?? false)
            ? alert.name!
            : alert.symbol.replaceFirst('NSE:', '');
        final title = 'Price Alert: $displaySymbol';
        final body =
            '$displaySymbol is now ₹${price.toStringAsFixed(2)} '
            '(${alert.isAbove ? 'above' : 'below'} your target of ₹${alert.targetPrice.toStringAsFixed(2)}).';

        // In-app notification row so it appears in the notifications screen.
        try {
          await client.from('notifications').insert({
            'user_id': user.id,
            'title': title,
            'body': body,
            'is_read': false,
            'action_type': 'price_alert',
            'action_data': {'symbol': alert.symbol, 'market': alert.market},
          });
        } catch (_) {}

        // Local device notification with the dedicated price-alert sound/channel.
        try {
          await NotificationService().showNotification(
            id: alert.id.hashCode,
            title: title,
            body: body,
            category: NotificationCategory.priceAlert,
          );
        } catch (_) {}
      }
    } catch (e) {
      if (FirebaseService.isTransientNetworkError(e)) return;
      debugPrint('evaluatePriceAlerts error: $e');
    }
  }

  // Step 2 of the server-trust migration. When true, order placement is routed
  // through the validated server-side 'place-order' edge function (the trusted
  // "teller"): the server authenticates the user from their JWT, validates every
  // field, fetches a trusted price, and runs all money math via the audited
  // execution engine — the phone never computes balances or writes money rows.
  // Flip this to false to instantly revert to the legacy on-device path
  // (_placeOrderLocal) without any other code change. The legacy path still
  // works because direct table writes are not locked down until Step 3.
  static const bool _useServerPlaceOrder = true;

  // Step 3: when true, the phone performs NO direct money-table writes — order
  // execution and expiry settlement run entirely on the server (place-order
  // triggers execution on placement; crons also run on schedule). This MUST
  // stay true once the database write-lockdown (RLS) is applied.
  // ignore: prefer_final_fields
  static bool _serverExecOnly = true;

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
    bool isIntraday = false,
    bool isExitOrder = false,
  }) async {
    if (!_useServerPlaceOrder) {
      return _placeOrderLocal(
        symbol: symbol,
        market: market,
        side: side,
        quantity: quantity,
        price: price,
        isMarket: isMarket,
        instrumentType: instrumentType,
        strikePrice: strikePrice,
        optionType: optionType,
        expiryDate: expiryDate,
        isIntraday: isIntraday,
        isExitOrder: isExitOrder,
      );
    }

    final user = currentUser;
    if (user == null) throw Exception('No authenticated user');

    final body = <String, dynamic>{
      'symbol': symbol,
      'market': market,
      'side': side.toLowerCase(),
      'quantity': quantity,
      'isMarket': isMarket,
      'instrumentType': instrumentType,
      'isExitOrder': isExitOrder,
      'price': ?price,
      'strikePrice': ?strikePrice,
      'optionType': ?optionType,
      'expiryDate': ?expiryDate,
    };

    Map<String, dynamic> data;
    try {
      final response = await client.functions.invoke('place-order', body: body);
      final raw = response.data;
      if (raw is Map) {
        data = Map<String, dynamic>.from(raw);
      } else if (raw is String && raw.isNotEmpty) {
        data = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      } else {
        throw Exception('Order service returned an empty response');
      }
    } on FunctionException catch (e) {
      // Surface the server's validation/auth error message to the UI.
      final details = e.details;
      String msg = 'Order failed. Please try again.';
      if (details is Map && details['error'] != null) {
        msg = details['error'].toString();
      } else if (details is String && details.isNotEmpty) {
        try {
          final parsed = jsonDecode(details);
          if (parsed is Map && parsed['error'] != null) {
            msg = parsed['error'].toString();
          } else {
            msg = details;
          }
        } catch (_) {
          msg = details;
        }
      }
      throw Exception(msg);
    }

    if (data['error'] != null) {
      throw Exception(data['error'].toString());
    }

    final orderId = data['order_id'] as String?;
    final status = data['status'] as String? ?? 'pending';

    // Fetch the resulting order row to return to the UI. For executed F&O orders
    // the pending row is replaced by a fresh executed order, so fall back to the
    // most recent order for this symbol when the original id is gone.
    Map<String, dynamic>? row;
    if (orderId != null) {
      final byId =
          await client.from('orders').select().eq('id', orderId).maybeSingle();
      if (byId != null) row = Map<String, dynamic>.from(byId as Map);
    }
    if (row == null) {
      final latest = await client
          .from('orders')
          .select()
          .eq('user_id', user.id)
          .eq('symbol', symbol)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      if (latest != null) row = Map<String, dynamic>.from(latest as Map);
    }

    if (row != null) {
      return Order.fromJson(row);
    }

    // Last-resort synthetic order so the UI can still react to the status.
    return Order(
      id: orderId ?? '',
      symbol: symbol,
      name: symbol,
      market: market,
      side: side.toLowerCase(),
      quantity: quantity,
      price: price ?? 0.0,
      total: (price ?? 0.0) * quantity,
      status: status,
    );
  }

  Future<Order> _placeOrderLocal({
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
    bool isIntraday = false,
    bool isExitOrder = false,
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
    String priceSource = 'FALLBACK_PREFILLED';
    final nseContractDate = DateTime.now().toIso8601String().split('T')[0];

    if (instrumentType == 'EQUITY') {
      final quote = await MarketService.quote(symbol, market);
      if (quote != null && quote.price > 0) {
        currentPrice = quote.price;
        name = quote.name;
        isQuoteAvailable = true;
        priceSource = 'EQUITY_LTP';
      } else {
        if (price == null || price <= 0) {
          throw Exception('Market quote unavailable');
        }
        currentPrice = price;
      }
    } else if (instrumentType == 'OPTION') {
      // The market-quote endpoint returns the UNDERLYING spot price for an
      // option contract symbol (e.g. ~1330 for a RELIANCE option), NOT the
      // option premium. The client computes and displays the correct premium
      // (via the option chain) and passes it as `price`. Use that premium as
      // the execution price so the cost charged matches what the user saw and
      // confirmed. Without this, an option buy is wrongly priced at the
      // underlying's price and gets rejected for "insufficient balance".
      if (price != null && price > 0) {
        currentPrice = price;
        isQuoteAvailable = true;
        priceSource = 'OPTION_PREMIUM';
        name = '$symbol $expiryDate $strikePrice $optionType';
      } else {
        final liveQuote = await MarketService.quote(symbol, market);
        if (liveQuote != null && liveQuote.price > 0) {
          currentPrice = liveQuote.price;
          name = liveQuote.name;
          isQuoteAvailable = true;
          priceSource = 'OPTION_PREMIUM';
        } else {
          throw Exception('Live derivative quote unavailable. Please try again.');
        }
      }
    } else {
      // FUTURE: the underlying-tracked quote is an acceptable proxy for the
      // futures price; fall back to the client-supplied price if unavailable.
      final liveQuote = await MarketService.quote(symbol, market);
      if (liveQuote != null && liveQuote.price > 0) {
        currentPrice = liveQuote.price;
        name = liveQuote.name;
        isQuoteAvailable = true;
        priceSource = 'FUTURE_LTP';
      } else {
        if (price == null || price <= 0) {
          throw Exception('Live derivative quote unavailable. Please try again.');
        }
        currentPrice = price;
        name = '$symbol Perpetual Futures';
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

    // Market-hours gate for ALL markets (equity, F&O, crypto). Previously this
    // only applied to non-stock markets, so equity and F&O orders (which use
    // market == 'stock') executed at any hour. Now any order placed while its
    // market is closed is routed to pending and the pending executor (which
    // also respects market hours) fills it once the market reopens. Crypto is
    // unaffected since MarketHours.isOpen('crypto') is always true.
    if (!MarketHours.isOpen(market)) {
      executeImmediately = false;
    }

    // Option limit orders must WAIT for the live premium to reach the limit.
    // For options, currentPrice above is the client-supplied premium (which
    // equals the limit the user typed), so the buy/sell comparison would always
    // be satisfied and fill instantly. Route option limit orders to the pending
    // executor instead — it evaluates the trigger against a live computed
    // premium (intrinsic + time value) and only fills once the limit is hit.
    if (instrumentType == 'OPTION' && !isMarket) {
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
            'execution_price_source': priceSource,
            'execution_reference_price': currentPrice,
            'nse_contract_date': nseContractDate,
            'is_exit': isExitOrder,
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

    if (_activeChargeConfig == null) {
      await fetchActiveChargeConfig();
    }

    final Map<String, double> charges = (market == 'stock')
        ? calculateTransactionCharges(
            instrumentType: instrumentType,
            side: side,
            quantity: quantity,
            price: execPrice,
            isIntraday: isIntraday,
          )
        : {
            'brokerage': 0.0,
            'stamp_duty': 0.0,
            'tax_charges': 0.0,
            'total_charges': 0.0,
          };
    final totalCharges = charges['total_charges'] ?? 0.0;

    final bool isDerivative = instrumentType == 'FUTURE' || instrumentType == 'OPTION';

    if (isDerivative) {
      final lotSize = await FoInstrumentsService().getLotSize(symbol);
      int tradeQtyLots = (quantity / lotSize).toInt();
      int tradeSideSign = side == 'buy' ? 1 : -1;

      // 1. Fetch existing position
      final existingResponse = await client
          .from('fo_positions')
          .select()
          .eq('user_id', user.id)
          .eq('symbol', symbol)
          .eq('instrument_type', instrumentType)
          .eq('option_type', optionType ?? '')
          .eq('strike_price', strikePrice ?? 0.0)
          .eq('expiry_date', expiryDate ?? '')
          .eq('is_settled', false)
          .maybeSingle();

      FoPosition? existingPos;
      if (existingResponse != null) {
        existingPos = FoPosition.fromJson(Map<String, dynamic>.from(existingResponse as Map));
      }

      final int existingQty = existingPos?.netQty ?? 0;
      final double existingAvg = existingPos?.avgEntryPrice ?? 0.0;

      // Exit-order handling: force a deterministic opposite-side close.
      // Gated entirely behind isExitOrder so all non-exit (open/add) behavior
      // is byte-for-byte unchanged.
      if (isExitOrder) {
        // Resolve the held position first. A null/zero position means there is
        // nothing to close — fail clearly instead of silently opening a new
        // position (kills the position-lookup-miss class of the bug).
        if (existingPos == null || existingQty == 0) {
          throw Exception('No open position to exit');
        }
        // Force the trade onto the side opposite the held direction so that
        // (existingQty * tradeSideSign) < 0 and execution lands deterministically
        // in the reduce/close branch. Record the matching side: 'sell' to close a
        // long, 'buy' to cover a short.
        tradeSideSign = existingQty > 0 ? -1 : 1;
        side = existingQty > 0 ? 'sell' : 'buy';
        // Clamp the closing lots so newNetQty moves toward zero and never
        // overshoots into a reverse position (full close => 0).
        tradeQtyLots = math.min(tradeQtyLots.abs(), existingQty.abs());
      }

      final int newNetQty = existingQty + (tradeQtyLots * tradeSideSign);

      double newAvgEntryPrice = 0.0;
      double realizedPnl = 0.0;
      double walletDebit = 0.0;
      double walletCredit = 0.0;
      double marginBlocked = 0.0;

      // Check if opening/adding vs closing/reducing
      if (existingQty == 0 || (existingQty * tradeSideSign) > 0) {
        // Opening new position or adding to it
        newAvgEntryPrice = existingQty == 0
            ? execPrice
            : ((existingAvg * existingQty.abs()) + (execPrice * tradeQtyLots)) / (existingQty.abs() + tradeQtyLots);

        if (instrumentType == 'OPTION' && newNetQty > 0) {
          // Option buyer - pays 100% premium upfront, marginBlocked is 0
          marginBlocked = 0.0;
          walletDebit = execPrice * quantity;
        } else if (instrumentType == 'OPTION' && newNetQty < 0) {
          // Option seller - blocks 15% margin, receives premium
          marginBlocked = newAvgEntryPrice * newNetQty.abs() * lotSize * 0.15;
          final double oldMargin = existingPos?.marginBlocked ?? 0.0;
          final double marginDelta = marginBlocked - oldMargin;
          final double premiumReceived = execPrice * quantity;
          if (premiumReceived >= marginDelta) {
            walletCredit = premiumReceived - marginDelta;
            walletDebit = 0.0;
          } else {
            walletDebit = marginDelta - premiumReceived;
            walletCredit = 0.0;
          }
        } else {
          // Futures trader - blocks 15% margin
          marginBlocked = newAvgEntryPrice * newNetQty.abs() * lotSize * 0.15;
          final double oldMargin = existingPos?.marginBlocked ?? 0.0;
          walletDebit = marginBlocked - oldMargin;
        }
      } else {
        // Reducing or closing position
        newAvgEntryPrice = existingAvg;
        final int closedQtyLots = tradeQtyLots.abs() > existingQty.abs() ? existingQty.abs() : tradeQtyLots.abs();
        final int remainingQtyLots = tradeQtyLots.abs() - closedQtyLots;

        realizedPnl = (existingQty > 0 ? (execPrice - existingAvg) : (existingAvg - execPrice)) * closedQtyLots * lotSize;

        if (newNetQty == 0) {
          // Complete close
          marginBlocked = 0.0;
          if (instrumentType == 'OPTION' && existingQty > 0) {
            // Long option close - option buyer receives premium back
            walletCredit = execPrice * closedQtyLots * lotSize;
          } else if (instrumentType == 'OPTION' && existingQty < 0) {
            // Short option close - release margin, pay premium to buy back
            final double releasedMargin = existingPos?.marginBlocked ?? 0.0;
            final double netImpact = releasedMargin - (execPrice * closedQtyLots * lotSize);
            if (netImpact >= 0) {
              walletCredit = netImpact;
            } else {
              walletDebit = netImpact.abs();
            }
          } else {
            // Futures close - release margin + realizedPnl
            final double releasedMargin = existingPos?.marginBlocked ?? 0.0;
            final double netImpact = releasedMargin + realizedPnl;
            if (netImpact >= 0) {
              walletCredit = netImpact;
            } else {
              walletDebit = netImpact.abs();
            }
          }
        } else if (newNetQty * existingQty > 0) {
          // Partial reduction (same direction)
          if (instrumentType == 'OPTION' && existingQty > 0) {
            // Option buyer reduces long position
            marginBlocked = 0.0;
            walletCredit = execPrice * closedQtyLots * lotSize;
          } else if (instrumentType == 'OPTION' && existingQty < 0) {
            // Option seller reduces short position - release partial margin, pay premium to buy back
            marginBlocked = newAvgEntryPrice * newNetQty.abs() * lotSize * 0.15;
            final double releasedMargin = (existingPos?.marginBlocked ?? 0.0) - marginBlocked;
            final double netImpact = releasedMargin - (execPrice * closedQtyLots * lotSize);
            if (netImpact >= 0) {
              walletCredit = netImpact;
            } else {
              walletDebit = netImpact.abs();
            }
          } else {
            // Futures reduces position
            marginBlocked = newAvgEntryPrice * newNetQty.abs() * lotSize * 0.15;
            final double releasedMargin = (existingPos?.marginBlocked ?? 0.0) - marginBlocked;
            final double netImpact = releasedMargin + realizedPnl;
            if (netImpact >= 0) {
              walletCredit = netImpact;
            } else {
              walletDebit = netImpact.abs();
            }
          }
        } else {
          // Over-close: position switches direction
          // Closed portion first
          double closedPortionNetImpact = 0.0;
          if (instrumentType == 'OPTION' && existingQty > 0) {
            closedPortionNetImpact = execPrice * closedQtyLots * lotSize;
          } else if (instrumentType == 'OPTION' && existingQty < 0) {
            final double releasedMargin = existingPos?.marginBlocked ?? 0.0;
            closedPortionNetImpact = releasedMargin - (execPrice * closedQtyLots * lotSize);
          } else {
            final double releasedMargin = existingPos?.marginBlocked ?? 0.0;
            closedPortionNetImpact = releasedMargin + realizedPnl;
          }

          // Opened portion next
          newAvgEntryPrice = execPrice;
          double openedPortionDebit = 0.0;
          double openedPortionCredit = 0.0;
          if (instrumentType == 'OPTION' && newNetQty > 0) {
            marginBlocked = 0.0;
            openedPortionDebit = execPrice * remainingQtyLots * lotSize;
          } else if (instrumentType == 'OPTION' && newNetQty < 0) {
            // Opening short option - block margin, credit premium
            marginBlocked = newAvgEntryPrice * newNetQty.abs() * lotSize * 0.15;
            final double premiumReceived = execPrice * remainingQtyLots * lotSize;
            if (premiumReceived >= marginBlocked) {
              openedPortionCredit = premiumReceived - marginBlocked;
            } else {
              openedPortionDebit = marginBlocked - premiumReceived;
            }
          } else {
            marginBlocked = newAvgEntryPrice * newNetQty.abs() * lotSize * 0.15;
            openedPortionDebit = marginBlocked;
          }

          final double netImpact = closedPortionNetImpact + openedPortionCredit - openedPortionDebit;
          if (netImpact >= 0) {
            walletCredit = netImpact;
          } else {
            walletDebit = netImpact.abs();
          }
        }
      }

      // Check user balance and adjust credit/debit with charges
      double finalDebit = walletDebit;
      double finalCredit = walletCredit;
      if (totalCharges > 0) {
        if (walletCredit >= totalCharges) {
          finalCredit = walletCredit - totalCharges;
        } else {
          finalCredit = 0.0;
          finalDebit = walletDebit + (totalCharges - walletCredit);
        }
      }

      // Closing portion of an exit must never be blocked on balance — closing
      // reduces exposure and releases capital. Preserve the throw for non-exits.
      if (!isExitOrder && profile.walletBalance + finalCredit - finalDebit < 0) {
        throw Exception('Insufficient wallet balance. Required net impact (including charges): ₹${(finalDebit - finalCredit).toStringAsFixed(2)}');
      }

      final positionJson = {
        'symbol': symbol,
        'instrument_type': instrumentType,
        'option_type': optionType ?? '',
        'strike_price': strikePrice ?? 0.0,
        'expiry_date': expiryDate ?? '',
        'lot_size': lotSize,
        'net_qty': newNetQty,
        'avg_entry_price': newAvgEntryPrice,
      };

      final orderJson = {
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
        'instrument_type': instrumentType,
        'strike_price': strikePrice ?? 0.0,
        'option_type': optionType ?? '',
        'expiry_date': expiryDate ?? '',
        'execution_price_source': priceSource,
        'execution_reference_price': currentPrice,
        'nse_contract_date': nseContractDate,
        'charge_config_id': _activeChargeConfigId,
        'brokerage': charges['brokerage'],
        'stamp_duty': charges['stamp_duty'],
        'tax_charges': charges['tax_charges'],
        'total_charges': totalCharges,
      };

      // Released margin: with the forced exit routing the close branch sets
      // marginBlocked to the smaller (or zero) value, so oldMargin - newMargin is
      // the capital returned to the wallet. Stays 0.0 for non-exits (unchanged).
      final double marginReleased = isExitOrder
          ? math.max(0.0, (existingPos?.marginBlocked ?? 0.0) - marginBlocked)
          : 0.0;

      final Map<String, dynamic> rpcParams = {
        'p_user_id': user.id,
        'p_wallet_debit': finalDebit,
        'p_wallet_credit': finalCredit,
        'p_margin_blocked': marginBlocked,
        'p_margin_released': marginReleased,
        'p_position_data': positionJson,
        'p_order_data': orderJson,
      };
      // Bypass the RPC's internal balance guard only for exits. Omitted for
      // non-exits so their call signature is byte-for-byte identical (the RPC
      // param defaults to FALSE).
      if (isExitOrder) {
        rpcParams['p_skip_balance_check'] = true;
      }

      await client.rpc('place_fo_order_transaction', params: rpcParams);

      final orderResponse = await client
          .from('orders')
          .select()
          .eq('user_id', user.id)
          .eq('symbol', symbol)
          .order('executed_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (orderResponse == null) throw Exception('Could not place order');
      final placedOrder = Order.fromJson(Map<String, dynamic>.from(orderResponse as Map));

      return placedOrder;
    }

    final double marginPct = 1.0;
    final double marginRequired = total * marginPct;
    double realizedPnl = 0.0;

    // Exit-order handling (equity): force a deterministic opposite-side close.
    // Gated entirely behind isExitOrder so all non-exit (open/add/normal sell)
    // behavior is byte-for-byte unchanged. Resolve the held holding first and
    // derive the side from its sign: 'sell' closes a long (quantity > 0),
    // 'buy' covers a short (quantity < 0). A null/zero holding means there is
    // nothing to close — fail clearly instead of opening a new position.
    if (isExitOrder) {
      final existingExit = await client
          .from('holdings')
          .select()
          .eq('user_id', user.id)
          .eq('symbol', symbol)
          .eq('market', market)
          .maybeSingle();
      if (existingExit == null) {
        throw Exception('No open position to exit');
      }
      final exitQty =
          ((Map<String, dynamic>.from(existingExit as Map))['quantity'] as num)
              .toDouble();
      if (exitQty == 0) {
        throw Exception('No open position to exit');
      }
      // Oppose the held direction so execution lands in the close/reduce path.
      side = exitQty > 0 ? 'sell' : 'buy';
    }

    if (side == 'buy') {
      final existing = await client
          .from('holdings')
          .select()
          .eq('user_id', user.id)
          .eq('symbol', symbol)
          .eq('market', market)
          .maybeSingle();
      if (existing == null) {
        if (profile.walletBalance < marginRequired + totalCharges) {
          throw Exception('Insufficient wallet balance. Required (total + charges): ₹${(marginRequired + totalCharges).toStringAsFixed(2)}');
        }
        await client
            .from('profiles')
            .update({'wallet_balance': profile.walletBalance - total - totalCharges})
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
          // On an exit, never open a reverse position: clamp the closed lots to
          // the held quantity so no surplus buy remains.
          final remainingBuyQty = isExitOrder ? 0.0 : quantity - coverQty;

          // Margin model: covering returns the blocked margin plus realised P&L.
          // Closing never costs buyback cash, so it is not gated on balance.
          final double releasedMargin = coverQty * oldAvg;
          realizedPnl += (oldAvg - execPrice) * coverQty;

          final double resultingBalance = profile.walletBalance + releasedMargin + realizedPnl - totalCharges;

          await client
              .from('profiles')
              .update({
                'wallet_balance': resultingBalance,
                'total_realized_pnl': profile.totalRealizedPnl + realizedPnl - totalCharges,
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
                        updatedProfile.walletBalance - remainingTotal,
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
          if (profile.walletBalance < marginRequired + totalCharges) {
            throw Exception('Insufficient wallet balance. Required (total + charges): ₹${(marginRequired + totalCharges).toStringAsFixed(2)}');
          }
          await client
              .from('profiles')
              .update({'wallet_balance': profile.walletBalance - total - totalCharges})
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
        if (profile.walletBalance < marginRequired + totalCharges) {
          throw Exception('Insufficient margin to short sell (including charges). Required: ₹${(marginRequired + totalCharges).toStringAsFixed(2)}');
        }
        // Margin model: opening a short blocks margin (money out); it does NOT
        // credit the sale proceeds. marginRequired == notional for equity/crypto.
        await client
            .from('profiles')
            .update({'wallet_balance': profile.walletBalance - marginRequired - totalCharges})
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
          // On an exit, never open a reverse (short) position: clamp the closed
          // lots to the held quantity so no surplus sell remains.
          final remainingSellQty = isExitOrder ? 0.0 : quantity - sellQty;

          realizedPnl += (execPrice - oldAvg) * sellQty;
          await client
              .from('profiles')
              .update({
                'wallet_balance': profile.walletBalance + (sellQty * execPrice) - totalCharges,
                'total_realized_pnl': profile.totalRealizedPnl + realizedPnl - totalCharges,
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
          if (profile.walletBalance < marginRequired + totalCharges) {
            throw Exception('Insufficient margin to add to short. Required (total + charges): ₹${(marginRequired + totalCharges).toStringAsFixed(2)}');
          }
          // Margin model: adding to a short blocks additional margin (money out).
          await client
              .from('profiles')
              .update({'wallet_balance': profile.walletBalance - marginRequired - totalCharges})
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
          'execution_price_source': priceSource,
          'execution_reference_price': currentPrice,
          'nse_contract_date': nseContractDate,
          'charge_config_id': _activeChargeConfigId,
          'brokerage': charges['brokerage'],
          'stamp_duty': charges['stamp_duty'],
          'tax_charges': charges['tax_charges'],
          'total_charges': totalCharges,
        })
        .select()
        .maybeSingle();

    if (order == null) throw Exception('Could not place order');
    final placedOrder = Order.fromJson(Map<String, dynamic>.from(order as Map));

    return placedOrder;
  }

  // In-flight guard (same isolate): coalesce overlapping invocations from
  // getOrders() + getHoldings() + multiple screens into a single run so a
  // still-pending row cannot be read and executed by more than one pass.
  Future<List<Order>>? _pendingRun;

  Future<List<Order>> executePendingOrders() {
    // Step 3: execution is fully server-side. place-order triggers it on
    // placement and a cron runs every minute, so the phone no longer executes
    // orders or writes money rows. (Legacy on-device path kept behind the flag.)
    if (_serverExecOnly) return Future.value(<Order>[]);
    final running = _pendingRun;
    if (running != null) return running;
    final run = _executePendingOrdersInner()
        .whenComplete(() => _pendingRun = null);
    _pendingRun = run;
    return run;
  }

  Future<List<Order>> _executePendingOrdersInner() async {
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
    final pendingList = pending as List<dynamic>;
    if (pendingList.isEmpty) return [];

    // Pre-warm quotes for every unique underlying IN PARALLEL before the loop.
    // MarketService.quote caches results for a few seconds, so the per-order
    // pricing below then hits the cache instead of making serial network calls.
    // This is what removed the growing delay on buy/sell + refresh once pending
    // limit orders started accumulating.
    final underlyingsToWarm = <String>{};
    for (final raw in pendingList) {
      final row = Map<String, dynamic>.from(raw as Map);
      final sym = row['symbol'] as String? ?? '';
      final mkt = row['market'] as String? ?? 'stock';
      final itype = row['instrument_type'] as String? ?? 'EQUITY';
      String u = sym;
      if (itype == 'OPTION' && sym.contains('-')) {
        u = sym.split('-')[0];
      } else if (itype == 'FUTURE' && sym.contains(' ')) {
        u = sym.split(' ')[0];
      }
      underlyingsToWarm.add('$u\x1F$mkt');
    }
    await Future.wait(underlyingsToWarm.map((k) {
      final p = k.split('\x1F');
      return MarketService.quote(p[0], p[1]).then<void>((_) {}).catchError((_) {});
    }));

    for (final raw in pendingList) {
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
      final bool isExit = row['is_exit'] as bool? ?? false;

      if (!MarketHours.isOpen(market)) continue;

      // `claimed` is declared outside the try so the catch can inspect it:
      // a row claimed (pending -> executing) whose execution then fails is
      // marked 'failed' rather than being silently lost or left re-executable.
      bool claimed = false;
      try {
        // Atomic claim (cross-isolate/device): transition this row
        // pending -> executing before ANY mutation/RPC. Postgres serialises
        // the conditional update so exactly one pass claims the row; all
        // others match zero rows and skip. 'executing' is not in
        // ('filled','executed'), so it does NOT fire notify_order_executed().
        // Each order flows through exactly one branch below, so claimOrder()
        // is invoked at most once per row.
        Future<bool> claimOrder() async {
          final claim = await client
              .from('orders')
              .update({'status': 'executing'})
              .eq('id', id)
              .eq('status', 'pending')
              .select();
          if ((claim as List).isEmpty) return false;
          claimed = true;
          return true;
        }

        double execPrice = 0.0;
        String name = symbol;

        final bool isDerivative = instrumentType == 'FUTURE' || instrumentType == 'OPTION';
        final underlyingSymbol = (instrumentType == 'OPTION' && symbol.contains('-'))
            ? symbol.split('-')[0]
            : (instrumentType == 'FUTURE' && symbol.contains(' '))
                ? symbol.split(' ')[0]
                : symbol;

        final quote = await MarketService.quote(underlyingSymbol, market);
        if (quote == null) continue;
        name = quote.name;

        if (isDerivative) {
          if (instrumentType == 'FUTURE') {
            double daysLeft = 15.0;
            if (expiryDate != null && expiryDate != 'PERPETUAL') {
              try {
                daysLeft = DateTime.parse(expiryDate).difference(DateTime.now()).inHours / 24.0;
              } catch (_) {}
            }
            execPrice = OptionPricing.futurePrice(spot: quote.price, daysToExpiry: daysLeft);
          } else {
            // Option — same Black-Scholes estimator used for display, so a
            // limit fills exactly when the displayed LTP reaches the limit.
            final strike = strikePrice ?? 0.0;
            double daysLeft = 7.0;
            if (expiryDate != null) {
              try {
                daysLeft = DateTime.parse(expiryDate).difference(DateTime.now()).inHours / 24.0;
              } catch (_) {}
            }
            execPrice = OptionPricing.optionPremium(
              optionType: optionType ?? 'CE',
              spot: quote.price,
              strike: strike,
              daysToExpiry: daysLeft,
            );
          }
        } else {
          execPrice = quote.price;
        }

        if (orderType == 'limit') {
          if (side == 'buy' && execPrice > limitPrice) {
            continue;
          }
          if (side == 'sell' && execPrice < limitPrice) {
            continue;
          }
        }

        final total = execPrice * quantity;
        final double marginPct = isDerivative ? 0.15 : 1.0;
        final double marginRequired = total * marginPct;

        if (_activeChargeConfig == null) {
          await fetchActiveChargeConfig();
        }

        final Map<String, double> charges = (market == 'stock')
            ? calculateTransactionCharges(
                instrumentType: instrumentType,
                side: side,
                quantity: quantity,
                price: execPrice,
                isIntraday: false, // Pending orders are NRML/Delivery
              )
            : {
                'brokerage': 0.0,
                'stamp_duty': 0.0,
                'tax_charges': 0.0,
                'total_charges': 0.0,
              };
        final totalCharges = charges['total_charges'] ?? 0.0;

        final profile = await getUserProfile();
        if (profile == null) continue;

        double realizedPnl = 0.0;

        if (isDerivative) {
          final lotSize = await FoInstrumentsService().getLotSize(symbol);
          int tradeQtyLots = (quantity / lotSize).toInt();
          final tradeSideSign = side == 'buy' ? 1 : -1;

          // 1. Fetch existing position
          final existingResponse = await client
              .from('fo_positions')
              .select()
              .eq('user_id', user.id)
              .eq('symbol', symbol)
              .eq('instrument_type', instrumentType)
              .eq('option_type', optionType ?? '')
              .eq('strike_price', strikePrice ?? 0.0)
              .eq('expiry_date', expiryDate ?? '')
              .eq('is_settled', false)
              .maybeSingle();

          FoPosition? existingPos;
          if (existingResponse != null) {
            existingPos = FoPosition.fromJson(Map<String, dynamic>.from(existingResponse as Map));
          }

          final int existingQty = existingPos?.netQty ?? 0;
          final double existingAvg = existingPos?.avgEntryPrice ?? 0.0;

          // Exit orders must never flip into a reverse position when they fire.
          // When this fill closes against the held position, clamp the closing
          // lots to the held quantity so newNetQty stops at 0 (a full/partial
          // close) and can never overshoot into an opposite-side position.
          if (isExit && existingQty != 0 && (existingQty * tradeSideSign) < 0) {
            tradeQtyLots = math.min(tradeQtyLots.abs(), existingQty.abs());
          }

          final int newNetQty = existingQty + (tradeQtyLots * tradeSideSign);

          double newAvgEntryPrice = 0.0;
          double walletDebit = 0.0;
          double walletCredit = 0.0;
          double marginBlocked = 0.0;

          // Check if opening/adding vs closing/reducing
          if (existingQty == 0 || (existingQty * tradeSideSign) > 0) {
            // Opening new position or adding to it
            newAvgEntryPrice = existingQty == 0
                ? execPrice
                : ((existingAvg * existingQty.abs()) + (execPrice * tradeQtyLots)) / (existingQty.abs() + tradeQtyLots);

            if (instrumentType == 'OPTION' && newNetQty > 0) {
              // Option buyer - pays 100% premium upfront, marginBlocked is 0
              marginBlocked = 0.0;
              walletDebit = execPrice * quantity;
            } else if (instrumentType == 'OPTION' && newNetQty < 0) {
              // Option seller - blocks 15% margin, receives premium
              marginBlocked = newAvgEntryPrice * newNetQty.abs() * lotSize * 0.15;
              final double oldMargin = existingPos?.marginBlocked ?? 0.0;
              final double marginDelta = marginBlocked - oldMargin;
              final double premiumReceived = execPrice * quantity;
              if (premiumReceived >= marginDelta) {
                walletCredit = premiumReceived - marginDelta;
                walletDebit = 0.0;
              } else {
                walletDebit = marginDelta - premiumReceived;
                walletCredit = 0.0;
              }
            } else {
              // Futures trader - blocks 15% margin
              marginBlocked = newAvgEntryPrice * newNetQty.abs() * lotSize * 0.15;
              final double oldMargin = existingPos?.marginBlocked ?? 0.0;
              walletDebit = marginBlocked - oldMargin;
            }

            // Validate the FULL incremental capital required at execPrice for
            // the added lots against the CURRENT available balance (not the
            // blended-average margin delta, which can understate the true
            // requirement when adding below the existing average). This runs
            // BEFORE claimOrder(), so an underfunded open/add is never claimed
            // and simply stays 'pending'. Closes/reduces stay exempt (handled
            // in the reducing/closing branch below) to preserve the prior
            // exit-position-order-fix exemption (Req 3.6).
            final addedLots = tradeQtyLots; // opening/adding adds |addedLots|
            final double requiredCapital = (instrumentType == 'OPTION' && newNetQty > 0)
                ? execPrice * quantity                     // long option: full premium
                : execPrice * addedLots * lotSize * 0.15;  // futures / short option: full margin on added lots
            if (profile.walletBalance < requiredCapital + totalCharges) {
              continue; // leave pending; insufficient true funds (un-claimed)
            }
          } else {
            // Reducing or closing position
            newAvgEntryPrice = existingAvg;
            final int closedQtyLots = tradeQtyLots.abs() > existingQty.abs() ? existingQty.abs() : tradeQtyLots.abs();
            final int remainingQtyLots = tradeQtyLots.abs() - closedQtyLots;

            realizedPnl = (existingQty > 0 ? (execPrice - existingAvg) : (existingAvg - execPrice)) * closedQtyLots * lotSize;

            if (newNetQty == 0) {
              // Complete close
              marginBlocked = 0.0;
              if (instrumentType == 'OPTION' && existingQty > 0) {
                // Long option close - option buyer receives premium back
                walletCredit = execPrice * closedQtyLots * lotSize;
              } else if (instrumentType == 'OPTION' && existingQty < 0) {
                // Short option close - release margin, pay premium to buy back
                final double releasedMargin = existingPos?.marginBlocked ?? 0.0;
                final double netImpact = releasedMargin - (execPrice * closedQtyLots * lotSize);
                if (netImpact >= 0) {
                  walletCredit = netImpact;
                } else {
                  walletDebit = netImpact.abs();
                }
              } else {
                // Futures close - release margin + realizedPnl
                final double releasedMargin = existingPos?.marginBlocked ?? 0.0;
                final double netImpact = releasedMargin + realizedPnl;
                if (netImpact >= 0) {
                  walletCredit = netImpact;
                } else {
                  walletDebit = netImpact.abs();
                }
              }
            } else if (newNetQty * existingQty > 0) {
              // Partial reduction (same direction)
              if (instrumentType == 'OPTION' && existingQty > 0) {
                // Option buyer reduces long position
                marginBlocked = 0.0;
                walletCredit = execPrice * closedQtyLots * lotSize;
              } else if (instrumentType == 'OPTION' && existingQty < 0) {
                // Option seller reduces short position - release partial margin, pay premium to buy back
                marginBlocked = newAvgEntryPrice * newNetQty.abs() * lotSize * 0.15;
                final double releasedMargin = (existingPos?.marginBlocked ?? 0.0) - marginBlocked;
                final double netImpact = releasedMargin - (execPrice * closedQtyLots * lotSize);
                if (netImpact >= 0) {
                  walletCredit = netImpact;
                } else {
                  walletDebit = netImpact.abs();
                }
              } else {
                // Futures reduces position
                marginBlocked = newAvgEntryPrice * newNetQty.abs() * lotSize * 0.15;
                final double releasedMargin = (existingPos?.marginBlocked ?? 0.0) - marginBlocked;
                final double netImpact = releasedMargin + realizedPnl;
                if (netImpact >= 0) {
                  walletCredit = netImpact;
                } else {
                  walletDebit = netImpact.abs();
                }
              }
            } else {
              // Over-close: position switches direction
              // Closed portion first
              double closedPortionNetImpact = 0.0;
              if (instrumentType == 'OPTION' && existingQty > 0) {
                closedPortionNetImpact = execPrice * closedQtyLots * lotSize;
              } else if (instrumentType == 'OPTION' && existingQty < 0) {
                final double releasedMargin = existingPos?.marginBlocked ?? 0.0;
                closedPortionNetImpact = releasedMargin - (execPrice * closedQtyLots * lotSize);
              } else {
                final double releasedMargin = existingPos?.marginBlocked ?? 0.0;
                closedPortionNetImpact = releasedMargin + realizedPnl;
              }

              // Opened portion next
              newAvgEntryPrice = execPrice;
              double openedPortionDebit = 0.0;
              double openedPortionCredit = 0.0;
              if (instrumentType == 'OPTION' && newNetQty > 0) {
                marginBlocked = 0.0;
                openedPortionDebit = execPrice * remainingQtyLots * lotSize;
              } else if (instrumentType == 'OPTION' && newNetQty < 0) {
                // Opening short option - block margin, credit premium
                marginBlocked = newAvgEntryPrice * newNetQty.abs() * lotSize * 0.15;
                final double premiumReceived = execPrice * remainingQtyLots * lotSize;
                if (premiumReceived >= marginBlocked) {
                  openedPortionCredit = premiumReceived - marginBlocked;
                } else {
                  openedPortionDebit = marginBlocked - premiumReceived;
                }
              } else {
                marginBlocked = newAvgEntryPrice * newNetQty.abs() * lotSize * 0.15;
                openedPortionDebit = marginBlocked;
              }

              final double netImpact = closedPortionNetImpact + openedPortionCredit - openedPortionDebit;
              if (netImpact >= 0) {
                walletCredit = netImpact;
              } else {
                walletDebit = netImpact.abs();
              }
            }
          }

          // Check user balance and adjust credit/debit with charges
          double finalDebit = walletDebit;
          double finalCredit = walletCredit;
          if (totalCharges > 0) {
            if (walletCredit >= totalCharges) {
              finalCredit = walletCredit - totalCharges;
            } else {
              finalCredit = 0.0;
              finalDebit = walletDebit + (totalCharges - walletCredit);
            }
          }

          if (profile.walletBalance + finalCredit - finalDebit < 0) {
            continue;
          }

          final positionJson = {
            'symbol': symbol,
            'instrument_type': instrumentType,
            'option_type': optionType ?? '',
            'strike_price': strikePrice ?? 0.0,
            'expiry_date': expiryDate ?? '',
            'lot_size': lotSize,
            'net_qty': newNetQty,
            'avg_entry_price': newAvgEntryPrice,
          };

          final orderJson = {
            'symbol': symbol,
            'name': name,
            'market': market,
            'side': side,
            'quantity': quantity,
            'price': execPrice,
            'total': total,
            'realized_pnl': realizedPnl,
            'status': 'executed',
            'order_type': orderType,
            'instrument_type': instrumentType,
            'strike_price': strikePrice ?? 0.0,
            'option_type': optionType ?? '',
            'expiry_date': expiryDate ?? '',
            'charge_config_id': _activeChargeConfigId,
            'brokerage': charges['brokerage'],
            'stamp_duty': charges['stamp_duty'],
            'tax_charges': charges['tax_charges'],
            'total_charges': totalCharges,
          };

          // Claim the row (pending -> executing) before any mutation/RPC.
          // If another pass already claimed it, skip.
          if (!await claimOrder()) continue;

          await client.rpc('place_fo_order_transaction', params: {
            'p_user_id': user.id,
            'p_wallet_debit': finalDebit,
            'p_wallet_credit': finalCredit,
            'p_margin_blocked': marginBlocked,
            'p_margin_released': 0.0,
            'p_position_data': positionJson,
            'p_order_data': orderJson,
          });

          // RPC succeeded (it inserted the executed order, firing the trigger
          // once). Remove the claimed pending row. p_skip_balance_check stays
          // at its default FALSE so the RPC's FOR UPDATE balance guard remains
          // authoritative for opens/adds.
          await client.from('orders').delete().eq('id', id);

          // Fetch the newly inserted executed order to add to executedOrders list
          final orderResponse = await client
              .from('orders')
              .select()
              .eq('user_id', user.id)
              .eq('symbol', symbol)
              .order('executed_at', ascending: false)
              .limit(1)
              .maybeSingle();

          if (orderResponse != null) {
            final execOrder = Order.fromJson(Map<String, dynamic>.from(orderResponse as Map));
            executedOrders.add(execOrder);
          }
          continue;
        }

        if (side == 'buy') {
          final existing = await client
              .from('holdings')
              .select()
              .eq('user_id', user.id)
              .eq('symbol', symbol)
              .eq('market', market)
              .maybeSingle();
          if (existing == null) {
            if (profile.walletBalance < marginRequired + totalCharges) continue;
            if (!await claimOrder()) continue;
            await client
                .from('profiles')
                .update({'wallet_balance': profile.walletBalance - (isDerivative ? marginRequired : total) - totalCharges})
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

              if (profile.walletBalance < (coverQty * execPrice) + totalCharges) continue;
              if (!await claimOrder()) continue;

              realizedPnl += (oa - execPrice) * coverQty;

              await client
                  .from('profiles')
                  .update({
                    'wallet_balance':
                        profile.walletBalance - (coverQty * execPrice) - totalCharges,
                    'total_realized_pnl':
                        profile.totalRealizedPnl + realizedPnl - totalCharges,
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
              if (profile.walletBalance < marginRequired + totalCharges) continue;
              if (!await claimOrder()) continue;
              await client
                  .from('profiles')
                  .update({'wallet_balance': profile.walletBalance - (isDerivative ? marginRequired : total) - totalCharges})
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
            if (profile.walletBalance < marginRequired + totalCharges) continue;
            if (!await claimOrder()) continue;
            final double walletDelta = isDerivative ? -marginRequired : total;
            await client
                .from('profiles')
                .update({'wallet_balance': profile.walletBalance + walletDelta - totalCharges})
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
              if (!await claimOrder()) continue;
              await client
                  .from('profiles')
                  .update({
                    'wallet_balance':
                        profile.walletBalance + (isDerivative ? (sellQty * oa * marginPct + realizedPnl) : (sellQty * execPrice)) - totalCharges,
                    'total_realized_pnl':
                        profile.totalRealizedPnl + realizedPnl - totalCharges,
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
              if (profile.walletBalance < marginRequired + totalCharges) continue;
              if (!await claimOrder()) continue;
              await client
                  .from('profiles')
                  .update({'wallet_balance': profile.walletBalance - (isDerivative ? marginRequired : -total) - totalCharges})
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
              'charge_config_id': _activeChargeConfigId,
              'brokerage': charges['brokerage'],
              'stamp_duty': charges['stamp_duty'],
              'tax_charges': charges['tax_charges'],
              'total_charges': totalCharges,
            })
            .eq('id', id)
            .select()
            .maybeSingle();

        if (updatedOrder != null) {
          final execOrder = Order.fromJson(
            Map<String, dynamic>.from(updatedOrder as Map),
          );
          executedOrders.add(execOrder);
        }
      } catch (e) {
        if (claimed) {
          await client
              .from('orders')
              .update({'status': 'failed'})
              .eq('id', id)
              .eq('status', 'executing');
        }
        continue; // proceed to next pending order
      }
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
    // Wallet writes are server-only (Step 3). The validated RPC credits the
    // caller's wallet by the plan amount it determines server-side.
    await client.rpc('activate_subscription', params: {'p_plan_id': planId});

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
    // Wallet writes are server-only (Step 3): credit via the validated RPC.
    await client.rpc('credit_demo_cash', params: {'p_amount': amount});
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

    // 1. Credit the user's wallet (server-only via validated RPC — Step 3)
    await client.rpc('credit_demo_cash', params: {'p_amount': cashAmount});

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
    // Reward claim is server-only (Step 3): the validated RPC checks the reward
    // belongs to the caller and is unclaimed, then credits the wallet atomically.
    await client.rpc('claim_reward', params: {'p_reward_id': rewardId});
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

  // --- COMMUNITY WISHLIST METHODS ---

  Future<void> submitFeatureRequest({
    required String title,
    required String description,
    String? imageUrl,
  }) async {
    final user = currentUser;
    if (user == null) throw Exception('No authenticated user');
    await client.from('feature_requests').insert({
      'user_id': user.id,
      'title': title,
      'description': description,
      'image_url': imageUrl,
    });
  }

  Future<List<Map<String, dynamic>>> getFeatureRequests({
    String sortBy = 'trending',
    bool includeReported = false,
  }) async {
    final user = currentUser;
    if (user == null) return [];

    List<dynamic> rows;
    if (sortBy == 'trending') {
      final response = await client.rpc('get_trending_features');
      rows = response as List<dynamic>;
    } else {
      final query = client.from('feature_requests').select('*');
      if (sortBy == 'top') {
        final response = await query;
        rows = response as List<dynamic>;
      } else {
        // 'new'
        final response = await query.order('created_at', ascending: false);
        rows = response as List<dynamic>;
      }
    }

    List<Map<String, dynamic>> results = rows.map((row) {
      return Map<String, dynamic>.from(row as Map);
    }).toList();

    // Fetch upvotes for current user
    final userUpvotes = await client
        .from('feature_upvotes')
        .select('feature_id')
        .eq('user_id', user.id);
    final upvotedIds = (userUpvotes as List<dynamic>)
        .map((e) => e['feature_id'] as String)
        .toSet();

    // Fetch all upvote counts in case of non-trending sort
    Map<String, int> upvoteCounts = {};
    Map<String, int> reportCounts = {};
    
    final allUpvotes = await client.from('feature_upvotes').select('feature_id');
    for (var u in (allUpvotes as List<dynamic>)) {
      final fid = u['feature_id'] as String;
      upvoteCounts[fid] = (upvoteCounts[fid] ?? 0) + 1;
    }
    final allReports = await client.from('feature_reports').select('feature_id');
    for (var r in (allReports as List<dynamic>)) {
      final fid = r['feature_id'] as String;
      reportCounts[fid] = (reportCounts[fid] ?? 0) + 1;
    }

    List<Map<String, dynamic>> finalResults = [];
    for (var r in results) {
      final id = r['id'] as String;
      final upvotesCount = sortBy == 'trending' 
          ? (r['upvotes_count'] as num?)?.toInt() ?? 0
          : (upvoteCounts[id] ?? 0);
      
      final reportsCount = reportCounts[id] ?? 0;

      // Filter out reported requests if we are a regular user (not admin) and not includeReported
      final isOwner = r['user_id'] == user.id;
      final isModerated = r['is_moderated'] == true;
      
      // We will check if the user is admin. We can get this from user.isAdmin or by checking profile is_admin
      final profile = await getUserProfile();
      final isAdmin = profile?.isAdmin ?? false;

      if (!includeReported && reportsCount >= 3 && !isOwner && !isModerated && !isAdmin) {
        // Skip reported posts from public view
        continue;
      }

      finalResults.add({
        ...r,
        'upvotes_count': upvotesCount,
        'reports_count': reportsCount,
        'user_upvoted': upvotedIds.contains(id),
      });
    }

    if (sortBy == 'top') {
      finalResults.sort((a, b) {
        final cmp = (b['upvotes_count'] as int).compareTo(a['upvotes_count'] as int);
        if (cmp != 0) return cmp;
        return DateTime.parse(b['created_at'] as String)
            .compareTo(DateTime.parse(a['created_at'] as String));
      });
    }

    return finalResults;
  }

  Future<List<Map<String, dynamic>>> searchSimilarFeatures(String query) async {
    try {
      final response = await client.rpc('search_similar_features', params: {
        'search_title': query,
        'similarity_threshold': 0.35,
      });
      return (response as List<dynamic>)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (e) {
      return [];
    }
  }

  Future<void> toggleUpvote(String featureId, bool isUpvoted) async {
    final user = currentUser;
    if (user == null) throw Exception('No authenticated user');

    if (isUpvoted) {
      await client.from('feature_upvotes').insert({
        'feature_id': featureId,
        'user_id': user.id,
      });
    } else {
      await client.from('feature_upvotes').delete().match({
        'feature_id': featureId,
        'user_id': user.id,
      });
    }
  }

  Future<void> reportFeatureRequest(String featureId) async {
    final user = currentUser;
    if (user == null) throw Exception('No authenticated user');
    // Try insert report, ignore if already reported by this user (constraint error)
    try {
      await client.from('feature_reports').insert({
        'feature_id': featureId,
        'user_id': user.id,
      });
    } catch (e) {
      // already reported, safe to ignore
    }
  }

  Future<void> approveFeatureRequest(String featureId) async {
    await client.from('feature_requests').update({
      'is_moderated': true,
    }).eq('id', featureId);

    try {
      await client.from('feature_reports').delete().eq('feature_id', featureId);
    } catch (e) {
      // ignore
    }
  }

  Future<void> updateFeatureStatus(
    String featureId,
    String status, {
    String? releasedInVersion,
  }) async {
    await client.from('feature_requests').update({
      'status': status,
      'released_in_version': releasedInVersion,
    }).eq('id', featureId);
  }

  Future<void> deleteFeatureRequest(String featureId) async {
    await client.from('feature_requests').delete().eq('id', featureId);
  }
}
