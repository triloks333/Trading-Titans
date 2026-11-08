import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'analytics_service.dart';
import 'churn_telemetry_service.dart';
import 'market_service.dart';
import 'intel/intel_ids.dart';

/// What the UI should show for a reaction. [action] names where its button
/// goes ('autopsy', 'subscribe', 'topup') or is null for no button.
class Reaction {
  final String key;
  final String text;
  final String? actionLabel;
  final String? action;
  const Reaction(this.key, this.text, {this.actionLabel, this.action});
}

/// Reactions to what the user just did. Every message here is literally true:
/// no disguised pushes, no fake credits, and no upsell for a user who just
/// re-entered within 120s of a loss or has under ₹1,000 left.
///
/// Every decision (delivered or suppressed, with the reason) is written to
/// `intel_reaction_firings`, so admins can audit it.
class ActionReactionEngine {
  ActionReactionEngine._();
  static final ActionReactionEngine instance = ActionReactionEngine._();

  static const lowWalletFloor = 1000.0;
  static const _bigWallet = 500000.0;
  final _inr = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

  ChurnTelemetryService get _t => ChurnTelemetryService.instance;

  /// Why an upsell must not be shown now, or null when it may be.
  @visibleForTesting
  static String? upsellBlockReason({required bool revengeReentry, required num? walletBalance}) {
    if (revengeReentry) return 'revenge_reentry_120s';
    if (walletBalance != null && walletBalance < lowWalletFloor) return 'wallet_under_1000';
    return null;
  }

  String? _upsellBlock(num? wallet) =>
      upsellBlockReason(revengeReentry: _t.recentRevengeReentry, walletBalance: wallet ?? _t.walletBalance);

  /// After a position is fully closed. Returns at most one message:
  /// - 2 losses in a row on the symbol → recap with a Trade Autopsy link (never an upsell);
  /// - 2+ wins in a row → the same win scaled to a ₹5,00,000 wallet (an upsell, so guarded).
  ///
  /// Wins that aren't streaks still get a factual note: a 10%+ "textbook"
  /// close, or a 2–5% close held under 15 minutes.
  Future<Reaction?> onTradeClosed({
    required String symbol,
    required double pnl,
    required double walletAfter,
    double? pnlPct,
  }) async {
    final r = await _streakReaction(symbol: symbol, pnl: pnl, walletAfter: walletAfter);
    if (r != null || pnl <= 0 || pnlPct == null) return r;
    final name = symbol.toUpperCase();
    final props = {'sym': symbol, 'slug': symbolSlug(symbol), 'pnl': pnl, 'pct': pnlPct};
    if (pnlPct >= 10) {
      final w = Reaction('textbook_win', 'Closed $name +${pnlPct.toStringAsFixed(1)}% (${_inr.format(pnl)}). '
          'Trade Autopsy grades this A+.', actionLabel: 'Autopsy', action: 'autopsy');
      await _fire(w.key, delivered: true, reason: 'win_over_10pct', props: props);
      return w;
    }
    final hold = _holdMinutes(symbol);
    if (pnlPct >= 2 && pnlPct < 5 && hold != null && hold < 15) {
      final w = Reaction('quick_win', 'Closed $name +${pnlPct.toStringAsFixed(1)}% in $hold min (${_inr.format(pnl)}).');
      await _fire(w.key, delivered: true, reason: 'quick_win_under_15m', props: {...props, 'hold_min': hold});
      return w;
    }
    return null;
  }

  /// Minutes between the first buy on [symbol] after its previous close and now.
  int? _holdMinutes(String symbol) {
    DateTime? opened;
    final closes = _t.intel.events.where((e) => e.name == 'trade_closed' && e.props['sym'] == symbol).toList();
    // The close just recorded is the last one; look for buys after the one before it.
    final since = closes.length >= 2 ? closes[closes.length - 2].ts : DateTime(0);
    for (final e in _t.intel.events) {
      if (e.name == 'trade_placed' && e.props['sym'] == symbol && e.ts.isAfter(since)) {
        opened = e.ts;
        break;
      }
    }
    return opened == null ? null : DateTime.now().difference(opened).inMinutes;
  }

  Future<Reaction?> _streakReaction({required String symbol, required double pnl, required double walletAfter}) async {
    final (wins, losses) = _t.symbolStreak(symbol);
    final name = symbol.toUpperCase();
    final props = {'sym': symbol, 'slug': symbolSlug(symbol), 'pnl': pnl};
    if (pnl < 0 && losses == 2) {
      final r = Reaction('two_loss_recap',
          'Recap: 2 losing trades in a row on $name (latest ${_inr.format(pnl)}). Trade Autopsy shows what happened in each.',
          actionLabel: 'Autopsy', action: 'autopsy');
      await _fire(r.key, delivered: true, reason: 'loss_streak_2', props: props);
      return r;
    }
    if (pnl > 0 && wins >= 2 && walletAfter > 0 && walletAfter < _bigWallet) {
      final share = pnl / walletAfter;
      final scaled = share * _bigWallet;
      final block = _upsellBlock(walletAfter);
      if (block != null) {
        await _fire('win_streak_scaled', delivered: false, reason: block, props: {...props, 'wins': wins});
        return null;
      }
      final r = Reaction('win_streak_scaled',
          '$wins wins in a row on $name. This ${_inr.format(pnl)} win was ${(share * 100).toStringAsFixed(2)}% of your '
          '${_inr.format(walletAfter)} wallet; the same share of a ₹5,00,000 wallet is ${_inr.format(scaled)}.',
          actionLabel: 'See packs', action: 'subscribe');
      await _fire(r.key, delivered: true, reason: 'win_streak_$wins', props: {...props, 'wins': wins, 'scaled': scaled.round()});
      return r;
    }
    return null;
  }

  /// On an "insufficient funds" order rejection: whether to show the inline
  /// TOP UP offer. Logged either way.
  Future<bool> offerMarginTopUp({required String symbol, required double required, required double available}) async {
    final block = _upsellBlock(available);
    await _fire('margin_topup_offer',
        delivered: block == null,
        reason: block ?? 'margin_shortfall',
        props: {'sym': symbol, 'slug': symbolSlug(symbol), 'shortfall': (required - available).round()});
    return block == null;
  }

  /// After a launch that followed an unclean exit: asks the server to credit
  /// ₹2,500 demo cash (at most once per 7 days). Only says "added" when the
  /// RPC returned the new balance.
  Future<Reaction?> claimCrashApologyIfPending() async {
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool(ChurnTelemetryService.pendingApologyKey) ?? false)) return null;
    final client = Supabase.instance.client;
    if (client.auth.currentUser == null) return null; // keep it pending until signed in
    try {
      final res = await client.rpc('intel_claim_crash_apology');
      await prefs.remove(ChurnTelemetryService.pendingApologyKey);
      if (res is num) {
        final r = Reaction('crash_apology',
            'Sorry, the app closed unexpectedly last time. We added ₹2,500 demo cash — your balance is now ${_inr.format(res)}.');
        await _fire(r.key, delivered: true, reason: 'credited', props: {'balance': res});
        return r;
      }
      await _fire('crash_apology', delivered: false, reason: 'not_credited_guest_or_7d_limit');
    } catch (e) {
      // Network failure: stays pending, retried next launch. Nothing shown.
      debugPrint('[ActionReactionEngine] crash apology RPC failed: $e');
    }
    return null;
  }

  /// A rage-tap burst: flagged for admins, nothing shown to the user.
  Future<void> flagRageButton(String buttonId, String screen) =>
      _fire('rage_button_flag', delivered: true, reason: 'admin_flag', props: {'button': buttonId, 'screen': screen});

  /// Admin flags, at most once a day each: dead buttons (screen opened 10+
  /// times in 30 days, never tapped) and power buttons (5+ taps in 7 days).
  Future<void> flagButtons(Map<String, num> metrics) async {
    List<String> ids(String suffix, bool Function(num) test) => [
          for (final e in metrics.entries)
            if (e.key.startsWith('btn_') && e.key.endsWith(suffix) && test(e.value))
              e.key.substring(4, e.key.length - suffix.length),
        ];
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().substring(0, 10);
    for (final (key, list) in [
      ('dead_button_flag', ids('_zero_click_dead_button_flag', (v) => v == 1)),
      ('power_button_flag', ids('_clicks_7d', (v) => v >= 5)),
    ]) {
      if (list.isEmpty || prefs.getString('intel_${key}_day') == today) continue;
      await prefs.setString('intel_${key}_day', today);
      await _fire(key, delivered: true, reason: 'admin_flag', props: {'buttons': list, 'count': list.length});
    }
  }

  /// Checks run once after sign-in. Returns at most one message so the user
  /// isn't hit with a stack of snackbars.
  Future<Reaction?> startupReactions({required bool isGuest}) async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final events = _t.intel.events;
    final closes = events.where((e) => e.name == 'trade_closed').toList();

    // Profitable week: from Friday after the NSE close, once per week.
    final weekStart = DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));
    final weekKey = weekStart.toIso8601String().substring(0, 10);
    final afterFridayClose = now.weekday > DateTime.friday ||
        (now.weekday == DateTime.friday && now.hour * 60 + now.minute >= 15 * 60 + 30);
    if (afterFridayClose && prefs.getString('intel_week_recap') != weekKey) {
      final week = closes.where((e) => !e.ts.isBefore(weekStart)).toList();
      final total = week.fold<num>(0, (a, e) => a + ((e.props['pnl'] as num?) ?? 0));
      await prefs.setString('intel_week_recap', weekKey);
      if (week.isNotEmpty && total > 0) {
        final r = Reaction('profitable_week', 'Your week: +${_inr.format(total)} across ${week.length} closed trades.');
        await _fire(r.key, delivered: true, reason: 'week_pnl_positive', props: {'pnl': total, 'trades': week.length});
        return r;
      }
    }

    // Login streak of 5+ days broke yesterday: say so once, plainly.
    final days = {for (final e in events.where((e) => e.name == 'app_open')) DateTime(e.ts.year, e.ts.month, e.ts.day)};
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    var prior = 0;
    for (var d = yesterday.subtract(const Duration(days: 1)); days.contains(d); d = d.subtract(const Duration(days: 1))) {
      prior++;
    }
    final todayKey = today.toIso8601String().substring(0, 10);
    if (!days.contains(yesterday) && prior >= 5 && prefs.getString('intel_streak_note') != todayKey) {
      await prefs.setString('intel_streak_note', todayKey);
      final r = Reaction('streak_broken', 'Your $prior-day streak ended yesterday. Opening today starts a new one.');
      await _fire(r.key, delivered: true, reason: 'streak_5plus_broken', props: {'prior_days': prior});
      return r;
    }

    // Guest with real history: their trades live on this account only.
    final pnl = closes.fold<num>(0, (a, e) => a + ((e.props['pnl'] as num?) ?? 0));
    final trades = events.where((e) => e.name == 'trade_placed').length;
    final lastGuestNote = DateTime.tryParse(prefs.getString('intel_guest_note') ?? '');
    if (isGuest && (pnl >= 2000 || trades >= 3) && (lastGuestNote == null || now.difference(lastGuestNote).inDays >= 3)) {
      await prefs.setString('intel_guest_note', now.toIso8601String());
      final r = Reaction('guest_save_account',
          "You're on a guest account, so your trades can't be recovered on a new phone. A free login keeps them.",
          actionLabel: 'Save', action: 'convert');
      await _fire(r.key, delivered: true, reason: pnl >= 2000 ? 'guest_profit_2000' : 'guest_3_trades', props: {'pnl': pnl, 'trades': trades});
      return r;
    }

    // Sold a winner that has since rallied 5%+ (closed in the last 3 days, checked once).
    final checked = prefs.getStringList('intel_early_checked') ?? [];
    for (final e in closes.reversed) {
      if (now.difference(e.ts).inDays > 3) break;
      final price = (e.props['price'] as num?)?.toDouble();
      final market = e.props['market'] as String?;
      final id = '${e.props['sym']}@${e.ts.millisecondsSinceEpoch}';
      if (((e.props['pnl'] as num?) ?? 0) <= 0 || price == null || market == null || checked.contains(id)) continue;
      await prefs.setStringList('intel_early_checked', [...checked.take(50), id]);
      final q = await MarketService.quote('${e.props['sym']}', market);
      if (q == null || q.price < price * 1.05) continue;
      final up = (q.price / price - 1) * 100;
      final r = Reaction('sold_too_early',
          'Since you sold ${'${e.props['sym']}'.toUpperCase()} at ${_inr.format(price)}, it is up ${up.toStringAsFixed(1)}%. '
          'Trade Autopsy shows the exit.',
          actionLabel: 'Autopsy', action: 'autopsy');
      await _fire(r.key, delivered: true, reason: 'rallied_5pct_after_exit', props: {'sym': e.props['sym'], 'up_pct': up});
      return r;
    }
    return null;
  }

  /// A search came back empty: the screen shows a hint; logged for admins.
  Future<void> onZeroResultSearch(String query, String market) =>
      _fire('zero_result_search_help', delivered: true, reason: 'no_results', props: {'query': query, 'market': market});

  /// The delete-account dialog opened: it offers Support, never blocks deletion.
  Future<void> onDeleteAccountOpened() =>
      _fire('delete_account_support_offer', delivered: true, reason: 'delete_dialog_opened');

  Future<void> _fire(String reaction, {required bool delivered, required String reason, Map<String, Object?> props = const {}}) async {
    _t.intel.add('reaction', {'reaction': reaction, 'delivered': delivered, 'reason': reason});
    AnalyticsService.log('reaction_$reaction', {'delivered': delivered, 'reason': reason});
    try {
      final client = Supabase.instance.client;
      final user = client.auth.currentUser;
      if (user == null) return;
      await client.from('intel_reaction_firings').insert({
        'user_id': user.id,
        'reaction': reaction,
        'delivered': delivered,
        'reason': reason,
        'props': props,
      });
    } catch (e) {
      // The matching 'reaction' event above still reaches intel_events.
      debugPrint('[ActionReactionEngine] firing log failed: $e');
    }
  }
}
