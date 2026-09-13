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
import '../models/challenge.dart';
import '../core/market_hours.dart';
import '../core/option_pricing.dart';
import '../core/app_constants.dart';
import 'market_service.dart';
import 'fo_instruments_service.dart';
import 'firebase_service.dart';
import 'diagnostics_service.dart';
import 'plan_service.dart' show PlanOption;

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
      // profiles is no longer world-readable; resolve the referrer via a
      // SECURITY DEFINER RPC that only returns the id for a valid code.
      final referrerId = await client.rpc(
        'get_referrer_id_by_code',
        params: {'p_code': codeUpper},
      );
      if (referrerId == null) {
        throw Exception(
          'Invalid referral code. Please check the code and try again.',
        );
      }
      referredById = referrerId as String;
    }

    final Map<String, dynamic> userData = {};
    // Name is optional now. When omitted, handle_new_user() falls back to the
    // email prefix, so don't send an empty string (which would override that).
    if (name.trim().isNotEmpty) {
      userData['name'] = name.trim();
    }
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

  /// Signs out of THIS device only.
  ///
  /// [SignOutScope.local] matters: the SDK default is `global`, which revokes
  /// every refresh token the account has. That made signing out of the app also
  /// sign the user out of the web app, and the web app sign them out of the
  /// phone. Nobody expects logging out on one device to end their session on
  /// another.
  ///
  /// `global` is still the right tool for "sign out everywhere" after a password
  /// change or a suspected compromise — a separate, deliberate action, not this.
  /// Kept in step with `signOut()` in web/src/lib/auth.tsx.
  Future<void> signOut() async {
    await client.auth.signOut(scope: SignOutScope.local);
  }

  /// Applies a referral code to the currently signed-in user via the
  /// idempotent `apply_referral_code` RPC. Used for OAuth (Google) signups,
  /// where the referral cannot be passed through auth signUp metadata.
  ///
  /// Returns true only when the referral was actually applied (credited).
  /// Safe to call more than once: the RPC no-ops when the user is already
  /// referred or the new-signup window has passed.
  Future<bool> applyReferralCode(String code) async {
    final result = await client.rpc(
      'apply_referral_code',
      params: {'p_code': code.trim()},
    );
    if (result is Map && result['applied'] == true) return true;
    return false;
  }

  /// Finalises a guest → permanent conversion server-side: syncs the profile's
  /// email (and name, if it is still the placeholder) from the identity that
  /// was just attached, and credits the one-time ₹6,000 top-up.
  ///
  /// `converted` is false while the identity is not fully attached yet — an
  /// email change that has not been confirmed, for instance. That is an
  /// ordinary state, not an error.
  ///
  /// `bonus` is 0 for an account that was already converted, or that belongs to
  /// the guest cohort from before the ₹5,000 starting balance (they already
  /// hold ₹11,000). Safe to call repeatedly: the RPC is guarded by
  /// profiles.converted_at, so the bonus can only ever be paid once.
  Future<({bool converted, num bonus})> convertGuestAccount() async {
    DiagnosticsService.noteDbCall('rpc.convert_guest_account');
    final result = await client.rpc('convert_guest_account');
    final map = result is Map ? result : const <String, dynamic>{};
    final bonus = map['bonus'];
    return (
      converted: map['converted'] == true,
      bonus: bonus is num ? bonus : 0,
    );
  }

  User? get currentUser => client.auth.currentUser;

  Future<app_models.User?> getUserProfile() async {
    final user = currentUser;
    if (user == null) return null;

    try {
      DiagnosticsService.noteDbCall('profiles.select');
      var profile = await client
          .from('profiles')
          .select()
          .eq('id', user.id)
          .maybeSingle();

      // Self-heal: a signed-in user with no profile row would otherwise be
      // stuck at login (this is exactly what stranded an early user whose row
      // was dropped by a maintenance op). ensure_profile() recreates a default
      // profile server-side and logs the event, then we re-fetch once.
      if (profile == null) {
        try {
          await client.rpc('ensure_profile');
          profile = await client
              .from('profiles')
              .select()
              .eq('id', user.id)
              .maybeSingle();
        } catch (e) {
          debugPrint('ensure_profile self-heal failed: $e');
        }
        if (profile == null) return null;
      }

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
      DiagnosticsService.noteDbCall('app_config.select');
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

  /// Returns the user's orders, newest first.
  ///
  /// With [onIstDate] null this returns the most recent [limit] orders across
  /// all time — the behaviour the wallet and autopsy screens rely on.
  ///
  /// With [onIstDate] set, only orders created on that IST calendar day are
  /// returned (see [MarketHours.istDayRangeUtc] for why the boundary is IST and
  /// not the device timezone). When that day is today, orders still `pending`
  /// from an earlier day are included as well: `expire_pending_stock_orders()`
  /// excludes crypto, so a crypto limit order stays live indefinitely, and
  /// date-scoping it out of the current view would hide the only Edit/Cancel
  /// controls it has.
  Future<List<Order>> getOrders({int limit = 50, DateTime? onIstDate}) async {
    await executePendingOrders();
    final user = currentUser;
    if (user == null) return [];

    try {
      DiagnosticsService.noteDbCall('orders.select');
      var filter = client.from('orders').select().eq('user_id', user.id);
      if (onIstDate != null) {
        final range = MarketHours.istDayRangeUtc(onIstDate);
        final startIso = range.start.toIso8601String();
        if (onIstDate == MarketHours.istDate()) {
          // No upper bound needed for today, so one OR covers "created today"
          // plus any still-live pending order carried over from a past day.
          filter = filter.or('created_at.gte.$startIso,status.eq.pending');
        } else {
          filter = filter
              .gte('created_at', startIso)
              .lt('created_at', range.end.toIso8601String());
        }
      }
      final data = await filter
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
    DiagnosticsService.noteDbCall('holdings+fo_positions.select');
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
          'margin_blocked': f['margin_blocked'],
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
      // Cost basis in the instrument's own currency, for US positions. NULL on
      // INR markets, where avg_price is already native.
      final double? nativeAvgPrice =
          (activeRow?['native_avg_price'] as num?)?.toDouble();
      final String? nativeCurrency = activeRow?['native_currency'] as String?;
      double? nativeCurrentPrice;
      double? nativePreviousClose;

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
      } else if (market == MarketHours.usStock) {
        // A US quote is in USD but avg_price came from the engine in INR, so
        // every figure computed below would mix currencies. Convert the quote to
        // INR here and keep the USD pair aside for the dollar display.
        final normKey = '${MarketService.normalizeSymbol(symbol, market)}\x1F$market';
        final currentQuote = quotesMap[key] ?? quotesMap[normKey];
        nativeCurrentPrice = currentQuote?.price;
        nativePreviousClose = currentQuote?.previousClose ?? nativeCurrentPrice;
        final fx = currentQuote?.fxRate;
        if (nativeCurrentPrice != null && fx != null && fx > 0) {
          currentPrice = nativeCurrentPrice * fx;
          previousClose = (nativePreviousClose ?? nativeCurrentPrice) * fx;
        } else {
          // No quote or no rate: show the position flat rather than off by ~88x.
          currentPrice = avgPrice;
          previousClose = avgPrice;
          nativeCurrentPrice ??= nativeAvgPrice;
          nativePreviousClose ??= nativeAvgPrice;
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

      // Capital actually deployed. For F&O futures and SHORT options you only
      // block margin (~15% of notional), not the full contract value — so the
      // "invested" base must be the blocked margin. This makes the dashboard
      // reconcile with the portfolio screen: wallet + positions == total value.
      // (Long options already use premium paid = notional, so they're correct.)
      final double? marginBlocked =
          (activeRow?['margin_blocked'] as num?)?.toDouble();
      final bool foMarginBased =
          (instType == 'FUTURE' || (instType == 'OPTION' && quantity < 0)) &&
              marginBlocked != null &&
              marginBlocked > 0;
      final double capitalBase = foMarginBased ? marginBlocked : invested;

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
          ? (capitalBase != 0 ? (pnl / capitalBase) * 100 : 0.0)
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
          invested: capitalBase,
          current: capitalBase + pnl,
          pnl: pnl,
          pnlPct: pnlPct,
          dayPnl: dayPnl,
          dayPnlPct: dayPnlPct,
          instrumentType: activeRow?['instrument_type'] as String? ?? 'EQUITY',
          optionType: activeRow?['option_type'] as String?,
          strikePrice: (activeRow?['strike_price'] as num?)?.toDouble(),
          expiryDate: activeRow?['expiry_date'] as String?,
          productType: activeRow?['product_type'] as String? ?? 'CNC',
          nativeAvgPrice: nativeAvgPrice,
          nativeCurrentPrice: nativeCurrentPrice,
          nativePreviousClose: nativePreviousClose,
          nativeCurrency: nativeCurrency,
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
    DiagnosticsService.noteDbCall('watchlist.select');
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

  Future<Quote?> getQuote(String symbol, String market, {String? expiryDate}) async {
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
        // Use the contract's ACTUAL days-to-expiry so the LTP matches the
        // portfolio screen and the fill engine (previously hardcoded 15 days,
        // which made the same future show a different price across screens).
        double daysToExpiry = 15.0;
        final fExpiry = expiryDate != null ? DateTime.tryParse(expiryDate) : null;
        if (fExpiry != null) {
          daysToExpiry = fExpiry.difference(DateTime.now()).inHours / 24.0;
        }
        price = OptionPricing.futurePrice(spot: spotQuote.price, daysToExpiry: daysToExpiry);
        previousClose = OptionPricing.futurePrice(spot: spotQuote.previousClose, daysToExpiry: daysToExpiry + 1.0);
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

  /// Builds an option chain from REAL NSE strikes (the `instruments` table),
  /// priced with the same Black-Scholes estimator the fill engine + portfolio
  /// use — so the chain price always matches the fill/position price. Returns
  /// null when no F&O instruments exist for the symbol (caller then falls back
  /// to the live providers / mock chain).
  Future<Map<String, dynamic>?> getOptionChainFromDb(
    String symbol, {
    String market = 'stock',
    int strikeCount = 25,
  }) async {
    if (market != 'stock') return null;

    final clean =
        symbol.toUpperCase().trim().replaceAll('.NS', '').replaceAll('.BO', '');
    String und = clean;
    if (clean == '^NSEI' || clean == 'NIFTY' || clean == 'NIFTY50' || clean == 'NIFTY 50') {
      und = 'NIFTY';
    } else if (clean == '^NSEBANK' || clean == 'BANKNIFTY' || clean == 'BANK NIFTY') {
      und = 'BANKNIFTY';
    } else if (clean == '^BSESN' || clean == 'SENSEX') {
      und = 'SENSEX';
    }

    final spotQuote = await MarketService.quote(symbol, market);
    if (spotQuote == null || spotQuote.price <= 0) return null;
    final double spot = spotQuote.price;
    final double prevClose =
        spotQuote.previousClose > 0 ? spotQuote.previousClose : spot;

    List<dynamic> rows;
    try {
      // Prefer REAL open interest + EOD close from the daily NSE bhavcopy.
      final q = await client.rpc('get_option_chain_quotes', params: {
        'p_underlying': und,
        'p_spot': spot,
        'p_strike_count': strikeCount,
      });
      rows = (q as List<dynamic>?) ?? [];
      if (rows.isEmpty) {
        // Fallback: real strikes from the instruments table (no OI/close).
        final s = await client.rpc('get_option_chain_strikes', params: {
          'p_underlying': und,
          'p_spot': spot,
          'p_strike_count': strikeCount,
        });
        rows = (s as List<dynamic>?) ?? [];
      }
    } catch (e) {
      debugPrint('getOptionChainFromDb RPC failed: $e');
      return null;
    }
    if (rows.isEmpty) return null;

    final Map<String, List<Map<String, dynamic>>> byExpiry = {};
    for (final r in rows) {
      final m = Map<String, dynamic>.from(r as Map);
      final ed = m['expiry_date'].toString();
      (byExpiry[ed] ??= []).add(m);
    }

    final now = DateTime.now();
    final chains = <Map<String, dynamic>>[];
    for (final entry in byExpiry.entries) {
      final expiry = entry.key;
      final expDate = DateTime.tryParse(expiry) ?? now;
      final daysLeft = expDate.difference(now).inHours / 24.0;
      final strikes = <Map<String, dynamic>>[];
      for (final row in entry.value) {
        final strike = (row['strike_price'] as num).toDouble();
        strikes.add({
          'strike_price': strike,
          'call': _buildDbOption(clean, expiry, strike, 'CE', spot, prevClose, daysLeft,
              realOi: row['ce_oi'] as num?, realClose: row['ce_close'] as num?),
          'put': _buildDbOption(clean, expiry, strike, 'PE', spot, prevClose, daysLeft,
              realOi: row['pe_oi'] as num?, realClose: row['pe_close'] as num?),
        });
      }
      chains.add({
        'expiry_date': expiry,
        'days_to_expiry': daysLeft.ceil().clamp(0, 100000),
        'strikes': strikes,
      });
    }
    if (chains.isEmpty) return null;

    final result = <String, dynamic>{
      'underlying': clean,
      'spot_price': spot,
      'change': spotQuote.change,
      'change_pct': spotQuote.changePct,
      'expiries': chains.map((c) => c['expiry_date']).toList(),
      'chains': chains,
      'futures': _buildDbFutures(clean, spot, spotQuote.change, spotQuote.changePct),
      'derivative_type': 'options',
      'source': 'nse_db',
    };
    // Normalize to plain JSON types (List<dynamic>/Map<String,dynamic>) so the
    // UI's firstWhere(orElse: () => null) and `as List<dynamic>` casts behave
    // exactly as they do for the provider/mock chain. Avoids reified-generic
    // type errors from the strongly-typed maps built above.
    return jsonDecode(jsonEncode(result)) as Map<String, dynamic>;
  }

  Map<String, dynamic> _buildDbOption(
    String clean, String expiry, double strike, String optType,
    double spot, double prevClose, double daysToExpiry,
    {num? realOi, num? realClose}
  ) {
    final price = OptionPricing.optionPremium(
        optionType: optType, spot: spot, strike: strike, daysToExpiry: daysToExpiry);
    final prev = OptionPricing.optionPremium(
        optionType: optType, spot: prevClose, strike: strike, daysToExpiry: daysToExpiry + 1.0);
    final change = price - prev;
    final changePct = prev > 0 ? (change / prev) * 100.0 : 0.0;
    // Open interest: use the REAL value from the NSE bhavcopy when available
    // (so PCR / Max-Pain / OI bars are genuine market data). Only fall back to
    // a deterministic, ATM-peaked estimate when no real OI exists for a strike.
    final int oi;
    if (realOi != null) {
      oi = realOi.round();
    } else {
      final moneyness = spot > 0 ? (strike - spot) / (0.06 * spot) : 0.0;
      oi = (60000 * math.exp(-(moneyness * moneyness))).round();
    }
    final strikeLabel =
        strike == strike.roundToDouble() ? strike.toInt().toString() : strike.toString();
    return {
      'symbol': '$clean-$expiry-$strikeLabel-$optType',
      'provider_symbol': '$clean-$expiry-$strikeLabel-$optType',
      'underlying': clean,
      'strike_price': strike,
      'expiry_date': expiry,
      'option_type': optType,
      'name': '$clean $expiry $strikeLabel $optType',
      'price': price,
      'previous_close': prev,
      // Real NSE end-of-day close for this contract (null if not in bhavcopy).
      'nse_close': realClose,
      'change': change,
      'change_pct': changePct,
      'open_interest': oi,
      'volume': (oi * 0.4).round(),
      'bid': (price * 0.98 * 100).round() / 100,
      'ask': (price * 1.02 * 100).round() / 100,
      'source': realOi != null ? 'nse_bhavcopy' : 'nse_db',
    };
  }

  List<Map<String, dynamic>> _buildDbFutures(
    String clean, double spot, double change, double changePct,
  ) {
    const months = ['JAN','FEB','MAR','APR','MAY','JUN','JUL','AUG','SEP','OCT','NOV','DEC'];
    final now = DateTime.now();
    final futures = <Map<String, dynamic>>[];
    int monthOffset = 0;
    while (futures.length < 3 && monthOffset < 6) {
      final d = DateTime(now.year, now.month + monthOffset, 1);
      final lastDay = DateTime(d.year, d.month + 1, 0);
      var diff = lastDay.weekday - DateTime.thursday;
      if (diff < 0) diff += 7;
      final lastThu = lastDay.subtract(Duration(days: diff));
      final expiryDt = DateTime(lastThu.year, lastThu.month, lastThu.day, 15, 30);
      monthOffset++;
      if (expiryDt.isBefore(now)) continue;
      final daysLeft = expiryDt.difference(now).inHours / 24.0;
      final fut = OptionPricing.futurePrice(spot: spot, daysToExpiry: daysLeft);
      final futRounded = (fut * 100).round() / 100;
      final futChange = (change * (spot > 0 ? fut / spot : 1.0) * 100).round() / 100;
      final expiryStr =
          '${lastThu.year}-${lastThu.month.toString().padLeft(2, '0')}-${lastThu.day.toString().padLeft(2, '0')}';
      futures.add({
        'symbol': '$clean ${months[lastThu.month - 1]} FUT',
        'name': 'NSE FUTURES · $expiryStr',
        'price': futRounded,
        'previous_close': ((futRounded - futChange) * 100).round() / 100,
        'change': futChange,
        'change_pct': changePct,
        'expiry_date': expiryStr,
        'currency': 'INR',
        'source': 'nse_db',
        'low': (futRounded * 0.985 * 100).round() / 100,
        'high': (futRounded * 1.015 * 100).round() / 100,
        'volume': 150000,
      });
    }
    return futures;
  }

  Future<List<Map<String, dynamic>>> getLeaderboard() async {
    // Reads from the `leaderboard` view (safe columns only — no email),
    // since profiles is now restricted to owner/admin reads.
    final data = await client
        .from('leaderboard')
        .select('id, name, wallet_balance, total_realized_pnl')
        .order('total_realized_pnl', ascending: false)
        .limit(20);
    final rows = (data as List<dynamic>)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    // Plan badges come from `user_tiers`, in one follow-up query for the whole
    // page. The view's `plan` column is not used: it is `profiles.plan`, which
    // nothing has ever written, so it labelled every account "free_starter".
    final tiers = await _tiersFor(
      rows.map((r) => r['id'] as String?).whereType<String>().toList(),
    );

    return rows
        .map((row) {
          return {
            'user_id': row['id'],
            'name': row['name'],
            'wallet_balance':
                (row['wallet_balance'] as num?)?.toDouble() ?? 0.0,
            'tier': tiers[row['id']] ?? 'free',
            'realized_pnl':
                (row['total_realized_pnl'] as num?)?.toDouble() ?? 0.0,
          };
        })
        .toList();
  }

  /// Tier per user id, for a set of users.
  ///
  /// Never throws: a leaderboard that fails to load because a decorative badge
  /// could not be fetched would be a bad trade. On failure everyone reads as
  /// free, which shows no badge at all.
  Future<Map<String, String>> _tiersFor(List<String> userIds) async {
    if (userIds.isEmpty) return {};
    try {
      DiagnosticsService.noteDbCall('user_tiers.select');
      final data = await client
          .from('user_tiers')
          .select('user_id, tier')
          .inFilter('user_id', userIds);
      final map = <String, String>{};
      for (final row in data as List<dynamic>) {
        final r = Map<String, dynamic>.from(row as Map);
        final id = r['user_id'] as String?;
        final tier = r['tier'] as String?;
        if (id != null && tier != null) map[id] = tier;
      }
      return map;
    } catch (e) {
      debugPrint('getLeaderboard: tier lookup failed, showing no badges: $e');
      return {};
    }
  }

  /// Everything currently on sale, cheapest first. The database is the only
  /// place prices are written down.
  Future<List<PlanOption>> getPlanCatalogue() async {
    DiagnosticsService.noteDbCall('plan_catalogue.select');
    final data = await client
        .from('plan_catalogue')
        .select()
        .eq('is_active', true)
        .order('sort_order');
    return (data as List<dynamic>)
        .map((e) => PlanOption.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// Opens a checkout for [sku] and returns the Razorpay-hosted page to send the
  /// user to.
  ///
  /// `mode: 'hosted'` is what removes the second sign-in. The app used to deep
  /// link to the web app's plans page, where the user had to authenticate all over
  /// again before they could pay. Now the server creates the Razorpay order or
  /// subscription and returns a URL for the standalone checkout page at
  /// `/app/pay`, which runs Razorpay in the browser with no login. The URL carries
  /// only opaque provider ids — no session, token or user id ever goes into it.
  ///
  /// Currency and price are decided server-side from `profiles.location` and
  /// `plan_catalogue`. Nothing here can influence either — the SKU is the whole
  /// request.
  ///
  /// Throws with the server's own message for the cases a user needs to read:
  /// already subscribed, checkout already in progress, plan withdrawn, too many
  /// attempts.
  Future<String> startHostedCheckout(String sku) async {
    DiagnosticsService.noteDbCall('create-payment-order');
    final data = await _invokeOrderFunction(
      'create-payment-order',
      {'sku': sku, 'mode': 'hosted'},
      fallbackError: 'We could not start the payment. Please try again.',
    );
    final url = (data['url'] as String?)?.trim();
    // https only. A payment handoff is exactly the wrong place to follow whatever
    // scheme a response happens to contain.
    if (url == null || !url.startsWith('https://')) {
      throw Exception('We could not start the payment. Please try again.');
    }
    return url;
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
      DiagnosticsService.noteDbCall('price_alerts.select');
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
  /// target is crossed, writes one `notifications` row — which reaches the phone
  /// tray via the push trigger — and marks the alert 'triggered'. Safe to call on
  /// every refresh cycle: it returns early when the user has no active alerts
  /// and never throws on network errors.
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
      final fetched = await MarketService.quotes(
        uniqueKeys.values
            .map((a) => (symbol: a.symbol, market: a.market))
            .toList(),
      );
      fetched.forEach((key, q) {
        if (q.price > 0) priceBySymbol[key] = q.price;
      });

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

        // This insert is the ONLY notification needed: the row appears in the
        // notifications screen, and trg_push_on_notification pushes it to the
        // tray via FCM on the 'price_alert' channel (so it keeps its dedicated
        // sound). A local push used to be posted here as well, which delivered
        // every triggered alert twice — the same duplicate the order path had.
        // The server-side evaluate-price-alerts cron already relies on this row
        // alone, so both paths now behave identically.
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
            // Mirrors place-order: `price` is overwritten with the fill price at
            // execution, so the requested trigger only survives here. Required
            // by orders_pending_limit_has_trigger for a resting limit order.
            'limit_price': isMarket ? null : limitPrice,
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
          marginBlocked = newAvgEntryPrice * newNetQty.abs() * lotSize * AppConstants.fnoMarginPct;
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
          marginBlocked = newAvgEntryPrice * newNetQty.abs() * lotSize * AppConstants.fnoMarginPct;
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
            marginBlocked = newAvgEntryPrice * newNetQty.abs() * lotSize * AppConstants.fnoMarginPct;
            final double releasedMargin = (existingPos?.marginBlocked ?? 0.0) - marginBlocked;
            final double netImpact = releasedMargin - (execPrice * closedQtyLots * lotSize);
            if (netImpact >= 0) {
              walletCredit = netImpact;
            } else {
              walletDebit = netImpact.abs();
            }
          } else {
            // Futures reduces position
            marginBlocked = newAvgEntryPrice * newNetQty.abs() * lotSize * AppConstants.fnoMarginPct;
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
            marginBlocked = newAvgEntryPrice * newNetQty.abs() * lotSize * AppConstants.fnoMarginPct;
            final double premiumReceived = execPrice * remainingQtyLots * lotSize;
            if (premiumReceived >= marginBlocked) {
              openedPortionCredit = premiumReceived - marginBlocked;
            } else {
              openedPortionDebit = marginBlocked - premiumReceived;
            }
          } else {
            marginBlocked = newAvgEntryPrice * newNetQty.abs() * lotSize * AppConstants.fnoMarginPct;
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
      // Same precedence as the server executor: `limit_price` is the trigger and
      // `price` is only a fallback for rows written before that column existed.
      // Reading `price` first is what let this path disagree with the server
      // about the same order after a modification.
      final limitPrice = (row['limit_price'] as num?)?.toDouble() ??
          (row['price'] as num?)?.toDouble() ??
          0.0;
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
        final double marginPct = isDerivative ? AppConstants.fnoMarginPct : AppConstants.equityMarginPct;
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
              marginBlocked = newAvgEntryPrice * newNetQty.abs() * lotSize * AppConstants.fnoMarginPct;
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
              marginBlocked = newAvgEntryPrice * newNetQty.abs() * lotSize * AppConstants.fnoMarginPct;
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
                : execPrice * addedLots * lotSize * AppConstants.fnoMarginPct;  // futures / short option: full margin on added lots
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
                marginBlocked = newAvgEntryPrice * newNetQty.abs() * lotSize * AppConstants.fnoMarginPct;
                final double releasedMargin = (existingPos?.marginBlocked ?? 0.0) - marginBlocked;
                final double netImpact = releasedMargin - (execPrice * closedQtyLots * lotSize);
                if (netImpact >= 0) {
                  walletCredit = netImpact;
                } else {
                  walletDebit = netImpact.abs();
                }
              } else {
                // Futures reduces position
                marginBlocked = newAvgEntryPrice * newNetQty.abs() * lotSize * AppConstants.fnoMarginPct;
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
                marginBlocked = newAvgEntryPrice * newNetQty.abs() * lotSize * AppConstants.fnoMarginPct;
                final double premiumReceived = execPrice * remainingQtyLots * lotSize;
                if (premiumReceived >= marginBlocked) {
                  openedPortionCredit = premiumReceived - marginBlocked;
                } else {
                  openedPortionDebit = marginBlocked - premiumReceived;
                }
              } else {
                marginBlocked = newAvgEntryPrice * newNetQty.abs() * lotSize * AppConstants.fnoMarginPct;
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

  /// Calls a server-side order endpoint and surfaces its message verbatim.
  ///
  /// Cancel and modify used to be direct table PATCHes. They could not stay that
  /// way: the RLS policy that permitted them (`USING (auth_uid() = user_id)`,
  /// no WITH CHECK, no column restriction) made "edit my order" and "rewrite my
  /// realized_pnl" the same privilege. The server is now the only writer.
  Future<Map<String, dynamic>> _invokeOrderFunction(
    String name,
    Map<String, dynamic> body, {
    // Only used when the server gave us nothing readable, which for a payment
    // must not say "order".
    String fallbackError = 'Could not update that order. Please try again.',
  }) async {
    Map<String, dynamic> data;
    try {
      final response = await client.functions.invoke(name, body: body);
      final raw = response.data;
      if (raw is Map) {
        data = Map<String, dynamic>.from(raw);
      } else if (raw is String && raw.isNotEmpty) {
        data = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      } else {
        throw Exception('The order service returned an empty response');
      }
    } on FunctionException catch (e) {
      // The server's own wording ("That order has already been filled.") is more
      // use to a user than a generic failure, so pass it through unchanged.
      final details = e.details;
      String msg = fallbackError;
      if (details is Map && details['error'] != null) {
        msg = details['error'].toString();
      } else if (details is String && details.isNotEmpty) {
        try {
          final parsed = jsonDecode(details);
          msg = (parsed is Map && parsed['error'] != null)
              ? parsed['error'].toString()
              : details;
        } catch (_) {
          msg = details;
        }
      }
      throw Exception(msg);
    }

    if (data['error'] != null) throw Exception(data['error'].toString());
    return data;
  }

  Future<void> cancelOrder(String orderId) async {
    await _invokeOrderFunction('cancel-order', {'orderId': orderId});
  }

  /// Edits a resting order's quantity and limit.
  ///
  /// Keeping `price` and `limit_price` in step is now the server's job, and it is
  /// not optional: the executor reads the trigger as `limit_price ?? price` while
  /// the app displays `price`, so letting them drift is what made a correct engine
  /// look broken. AEROENTER sell 500 was placed at 149 and modified to 145.80,
  /// but only `price` moved, so it went on being tested against 149 while the
  /// card read 145.80 — an LTP of 146.03 looked like a missed fill and was not.
  Future<void> modifyOrder({
    required String orderId,
    required double quantity,
    required double price,
    required bool isLimit,
  }) async {
    await _invokeOrderFunction('modify-order', {
      'orderId': orderId,
      'quantity': quantity,
      // Omitted for a market order: it has no trigger, and the server rejects a
      // price change on one rather than storing a limit it should not have.
      if (isLimit) 'price': price,
    });
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

  /// The user's wallet statement, newest first: every change to their demo cash
  /// balance, from the append-only `wallet_transactions` ledger.
  ///
  /// This is deliberately NOT the orders list. The Wallet tab used to render
  /// `getOrders()` under a "Transaction History" heading, which duplicated the
  /// Orders screen and still omitted every non-trade movement (signup bonus,
  /// referral credit, claimed rewards) because no record of those existed.
  ///
  /// Returns an empty list on ANY failure, including the table not existing.
  /// That is load-bearing: the ledger arrives in a migration, so a build can
  /// ship before it is applied and the Wallet tab must still work.
  Future<List<Map<String, dynamic>>> getWalletTransactions({int limit = 50}) async {
    final user = currentUser;
    if (user == null) return [];
    try {
      DiagnosticsService.noteDbCall('wallet_transactions.select');
      final rows = await client
          .from('wallet_transactions')
          .select(
              'id, amount, balance_before, balance_after, kind, description, created_at')
          .eq('user_id', user.id)
          .order('created_at', ascending: false)
          .limit(limit);
      return (rows as List<dynamic>)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (e) {
      debugPrint(
          'getWalletTransactions failed (ledger may not be migrated yet): $e');
      return [];
    }
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

  // ── Gamification ──────────────────────────────────────────────────────────
  // Challenge conditions are evaluated entirely server-side. The client can ask
  // for a re-evaluation but cannot choose what it earns, and repeat grants are
  // blocked by a UNIQUE(user_id, challenge_key, cycle) index rather than by
  // client-side bookkeeping.

  /// Catalogue plus this user's progress, in one round trip.
  Future<List<Challenge>> getMyChallenges() async {
    try {
      final rows = await client.rpc('get_my_challenges');
      return (rows as List<dynamic>)
          .map((e) => Challenge.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (e) {
      debugPrint('getMyChallenges failed: $e');
      return [];
    }
  }

  /// Recomputes every challenge for the signed-in user and grants what is newly
  /// earned. Returns the number of grants made. Cheap and idempotent, so it is
  /// safe to call after an order fills or when the Challenges screen opens.
  Future<int> evaluateChallenges() async {
    try {
      final result = await client.rpc('evaluate_challenges');
      return result is int ? result : int.tryParse('$result') ?? 0;
    } catch (e) {
      debugPrint('evaluateChallenges failed: $e');
      return 0;
    }
  }

  /// Advances the daily login streak (no-op if already counted today) and
  /// evaluates challenges. Returns the current streak length.
  Future<int> touchLoginStreak() async {
    try {
      final result = await client.rpc('touch_login_streak');
      return result is int ? result : int.tryParse('$result') ?? 0;
    } catch (e) {
      debugPrint('touchLoginStreak failed: $e');
      return 0;
    }
  }

  /// Grants the Glossary Graduate challenge. The quiz is marked in the app but
  /// the reward amount and the one-shot limit stay server-side.
  Future<bool> awardGlossaryQuiz() async {
    try {
      final result = await client.rpc('award_glossary_quiz');
      return result == true;
    } catch (e) {
      debugPrint('awardGlossaryQuiz failed: $e');
      return false;
    }
  }

  // ── User preferences (display currency, preferred markets, onboarding) ─────
  // Writes go through a validated RPC because `profiles` has no user UPDATE
  // policy — money columns live on the same row, so the RPC is the only path and
  // it can only touch the three preference columns.

  Future<Map<String, dynamic>?> getUserPreferences() async {
    try {
      final rows = await client.rpc('get_user_preferences');
      if (rows is List && rows.isNotEmpty) {
        return Map<String, dynamic>.from(rows.first as Map);
      }
      return null;
    } catch (e) {
      debugPrint('getUserPreferences failed: $e');
      return null;
    }
  }

  /// Saves any subset of the preferences. Nulls are left untouched server-side.
  Future<Map<String, dynamic>?> saveUserPreferences({
    String? displayCurrency,
    List<String>? preferredMarkets,
    String? location,
    bool completeOnboarding = false,
  }) async {
    try {
      final rows = await client.rpc('save_user_preferences', params: {
        'p_display_currency': displayCurrency,
        'p_preferred_markets': preferredMarkets,
        'p_location': location,
        'p_complete_onboarding': completeOnboarding,
      });
      if (rows is List && rows.isNotEmpty) {
        return Map<String, dynamic>.from(rows.first as Map);
      }
      return null;
    } catch (e) {
      debugPrint('saveUserPreferences failed: $e');
      return null;
    }
  }

  /// Records that the signed-in user accepted the Terms and Privacy Policy.
  ///
  /// Goes through a validated RPC because client UPDATE on `profiles` is revoked
  /// (see migration 20260827000000 — clients could otherwise set their own
  /// is_admin / wallet_balance). The RPC derives the user from auth.uid(), so a
  /// caller cannot record consent for anyone else, and it is idempotent for a
  /// given version.
  ///
  /// Best-effort by design: the checkbox has already gated the UI, so a failure
  /// here must not strand a user who just created an account. It is logged and
  /// retried on the next sign-in rather than surfaced as a blocking error.
  Future<void> acceptTerms(String version) async {
    try {
      await client.rpc('accept_terms', params: {'p_version': version});
    } catch (e) {
      debugPrint('acceptTerms failed: $e');
    }
  }

  /// Streak and XP counters for the Challenges header.
  Future<Map<String, int>> getGamificationStats() async {
    final user = currentUser;
    if (user == null) return const {'total_xp': 0, 'login_streak': 0, 'longest_login_streak': 0};
    try {
      final row = await client
          .from('profiles')
          .select('total_xp, login_streak, longest_login_streak')
          .eq('id', user.id)
          .maybeSingle();
      if (row == null) return const {'total_xp': 0, 'login_streak': 0, 'longest_login_streak': 0};
      final map = Map<String, dynamic>.from(row as Map);
      int asInt(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
      return {
        'total_xp': asInt(map['total_xp']),
        'login_streak': asInt(map['login_streak']),
        'longest_login_streak': asInt(map['longest_login_streak']),
      };
    } catch (e) {
      debugPrint('getGamificationStats failed: $e');
      return const {'total_xp': 0, 'login_streak': 0, 'longest_login_streak': 0};
    }
  }

  Future<void> sendCustomNotification({
    required String email,
    required String title,
    required String body,
    String? imageUrl,
    String? ctaLabel,
    String? ctaRoute,
    String? ctaUrl,
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
      'action_data': ?_notificationActionData(imageUrl, ctaLabel, ctaRoute, ctaUrl),
    });
  }

  /// Builds `action_data`, or null when there is nothing to attach.
  ///
  /// Returns null rather than `{}` so a plain notification stores a NULL column
  /// exactly as before — an empty object would read as "has an action" to anything
  /// checking for presence rather than contents.
  ///
  /// The label is dropped unless a destination came with it: `ctaLabel()` in
  /// notifications_screen.dart already refuses to draw a button without one, so
  /// storing a lone label would just be a row that promises something it cannot do.
  static Map<String, dynamic>? _notificationActionData(
    String? imageUrl,
    String? ctaLabel,
    String? ctaRoute,
    String? ctaUrl,
  ) {
    final label = ctaLabel?.trim();
    final route = ctaRoute?.trim();
    final url = ctaUrl?.trim();
    final hasDestination =
        (route != null && route.isNotEmpty) || (url != null && url.isNotEmpty);
    final data = <String, dynamic>{
      if (imageUrl != null && imageUrl.isNotEmpty) 'image_url': imageUrl,
      if (label != null && label.isNotEmpty && hasDestination) ...{
        'cta_label': label,
        if (route != null && route.isNotEmpty) 'cta_route': route,
        if (url != null && url.isNotEmpty) 'cta_url': url,
      },
    };
    return data.isEmpty ? null : data;
  }

  Future<void> sendBroadcastNotification({
    required String title,
    required String body,
    String? imageUrl,
    String? ctaLabel,
    String? ctaRoute,
    String? ctaUrl,
  }) async {
    final profiles = await client.from('profiles').select('id');
    final list = profiles as List<dynamic>;
    if (list.isEmpty) return;

    final actionData =
        _notificationActionData(imageUrl, ctaLabel, ctaRoute, ctaUrl);

    final inserts = list.map((profile) {
      final userId = profile['id'] as String;
      return {
        'user_id': userId,
        'title': title,
        'body': body,
        'is_read': false,
        'action_type': 'broadcast',
        'action_data': ?actionData,
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
