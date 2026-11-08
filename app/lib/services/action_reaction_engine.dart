import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'analytics_service.dart';
import 'churn_telemetry_service.dart';
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
  Future<Reaction?> onTradeClosed({required String symbol, required double pnl, required double walletAfter}) async {
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

  /// Dead buttons (screen opened 10+ times in 30 days, never tapped), flagged
  /// for admins at most once a day.
  Future<void> flagDeadButtons(Map<String, num> metrics) async {
    final dead = [
      for (final e in metrics.entries)
        if (e.key.endsWith('_zero_click_dead_button_flag') && e.value == 1)
          e.key.substring(4, e.key.length - '_zero_click_dead_button_flag'.length),
    ];
    if (dead.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().substring(0, 10);
    if (prefs.getString('intel_dead_flag_day') == today) return;
    await prefs.setString('intel_dead_flag_day', today);
    await _fire('dead_button_flag', delivered: true, reason: 'admin_flag', props: {'buttons': dead, 'count': dead.length});
  }

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
