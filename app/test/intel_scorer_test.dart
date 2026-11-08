import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/services/action_reaction_engine.dart';
import 'package:mobile/services/intel/intel_ids.dart';
import 'package:mobile/services/intel/intel_scorer.dart';
import 'package:mobile/services/intel/intel_store.dart';

void main() {
  final now = DateTime(2026, 11, 10, 11, 0); // Tuesday, mid-day
  var t = now.subtract(const Duration(minutes: 30));
  final events = <IntelEvent>[];
  void ev(String name, Map<String, Object?> props, {int sec = 1, String session = 's1'}) {
    t = t.add(Duration(seconds: sec));
    events.add(IntelEvent(name, props, t, session));
  }

  ev('app_open', {'source': 'icon', 'cold_start_ms': 1200});
  ev('screen_view', {'screen': 'trade_screen'});
  ev('tap', {'screen': 'trade_screen', 'button': 'trade_movers_top_gainers_pill'}, sec: 3);
  ev('screen_exit', {'screen': 'trade_screen', 'dwell_ms': 4000, 'scroll_pct': 60});
  ev('screen_view', {'screen': 'order_entry_screen'});
  ev('trade_placed', {'sym': 'RELIANCE.NS', 'side': 'buy', 'qty': 1, 'segment': 'EQUITY'}, sec: 10);
  ev('screen_exit', {'screen': 'order_entry_screen', 'dwell_ms': 900, 'scroll_pct': 0});
  ev('trade_closed', {'sym': 'RELIANCE.NS', 'pnl': -200}, sec: 600);
  ev('trade_placed', {'sym': 'RELIANCE', 'side': 'buy', 'qty': 1, 'segment': 'EQUITY'}, sec: 60); // revenge
  ev('trade_closed', {'sym': 'RELIANCE', 'pnl': -100}, sec: 300);
  ev('margin_shortfall', {'sym': 'NIFTY25NOV24000CE', 'required': 9000, 'available': 1000});
  ev('rage_tap', {'screen': 'trade_screen', 'button': 'trade_search_input_box', 'count': 3});
  ev('paywall_step', {'step': 'checkout_start', 'sku': 'plus'});
  ev('app_pause', {});

  final m = scoreIntel(events, now: now, live: const {'wallet_balance_to_starting_ratio': 0.5});

  test('launches, screens, buttons and symbols come from the events', () {
    expect(m['launch_icon_mid_day_0945_1430'], 1);
    expect(m['hw_cold_start_under_1500ms_current'], 1);
    expect(m['hw_login_streak_current_days_current'], 1);
    expect(m['hw_wallet_balance_to_starting_ratio_current'], 0.5);
    expect(m['scr_trade_screen_opens_today'], 1);
    expect(m['scr_trade_screen_max_scroll_depth_pct'], 60);
    expect(m['scr_order_entry_screen_pogo_bounce_under_1500ms'], 1);
    expect(m['scr_order_entry_screen_session_exit_drop_off'], 1);
    expect(m['btn_trade_movers_top_gainers_pill_clicks_today'], 1);
    expect(m['btn_trade_movers_top_gainers_pill_first_click_latency_ms'], 3000);
    expect(m['btn_trade_movers_top_gainers_pill_ctr_pct_7d'], 100);
    expect(m['btn_trade_search_input_box_rage_double_taps'], 1);
    expect(m['sym_reliance_trades_lost_7d'], 2);
    expect(m['sym_reliance_consecutive_losses_streak'], 2);
    expect(m['sym_reliance_net_realized_pnl_inr'], -300);
    expect(m['sym_reliance_revenge_trade_under_120s'], 1);
    expect(m['sym_reliance_avg_hold_time_minutes'], 8); // 10 min and 5 min, rounded
    expect(m['sym_reliance_user_personal_win_prob_0_to_1'] ?? 0, 0);
    expect(m['sym_nifty_margin_shortfall_rejections'], 1);
    expect(m['x_revenge_reentry_24h'], 1);
    expect(m['x_paywall_checkout_dropoff_pct'], 100);
    expect(m.containsKey('scr_welcome_screen_opens_today'), isFalse, reason: 'zeros are dropped for upload');
  });

  test('symbol slugs', () {
    expect(symbolSlug('RELIANCE.NS'), 'reliance');
    expect(symbolSlug('BANKNIFTY25NOV52000PE'), 'banknifty');
    expect(symbolSlug('NIFTY25NOVFUT'), 'nifty');
    expect(symbolSlug('BTCUSDT'), 'btc');
    expect(symbolSlug('ENI.MI'), 'eni_mi');
    expect(symbolSlug('ZOMATO'), 'eternal');
    expect(symbolSlug('V'), 'v');
    expect(symbolSlug('VEDL'), isNull);
    expect(screenSlug('OrderEntryScreen'), 'order_entry_screen');
    expect(screenSlug('_OrderEntryScreenState'), 'order_entry_screen');
  });

  test('upsell guard: revenge re-entry or under ₹1,000 blocks upsells', () {
    expect(ActionReactionEngine.upsellBlockReason(revengeReentry: true, walletBalance: 50000), 'revenge_reentry_120s');
    expect(ActionReactionEngine.upsellBlockReason(revengeReentry: false, walletBalance: 999), 'wallet_under_1000');
    expect(ActionReactionEngine.upsellBlockReason(revengeReentry: false, walletBalance: 1000), isNull);
  });

  test('catalogue coverage: every emitted key that has a catalogue name is real', () {
    final cat = jsonDecode(File('test/fixtures/intel_catalog_slim.json').readAsStringSync()) as Map<String, dynamic>;
    final names = {for (final i in cat['indicators'] as List) i as String};
    final keys = scoreIntel(const [], now: now, includeZeros: true).keys.where((k) => !k.startsWith('x_')).toSet();
    final unknown = keys.difference(names);
    expect(unknown, isEmpty, reason: 'scorer emits names not in the catalogue: ${unknown.take(5)}');
    // ignore: avoid_print
    print('INTEL COVERAGE: ${keys.length} of ${names.length} catalogue indicators computed');
  });
}
