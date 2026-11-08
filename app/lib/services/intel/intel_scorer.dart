import 'intel_ids.dart';
import 'intel_store.dart';

/// Launch windows (IST wall clock on the device), named as in the catalogue.
String launchWindow(DateTime t) {
  if (t.weekday == DateTime.saturday || t.weekday == DateTime.sunday) return 'weekend_sat_sun';
  final m = t.hour * 60 + t.minute;
  if (m >= 7 * 60 && m < 9 * 60 + 15) return 'pre_market_07_09';
  if (m >= 9 * 60 + 15 && m < 9 * 60 + 45) return 'opening_bell_0915_0945';
  if (m >= 9 * 60 + 45 && m < 14 * 60 + 30) return 'mid_day_0945_1430';
  if (m >= 14 * 60 + 30 && m < 15 * 60 + 35) return 'closing_bell_1430_1535';
  if (m >= 15 * 60 + 35 && m < 19 * 60) return 'post_market_1535_1900';
  if (m >= 19 * 60 && m < 23 * 60) return 'evening_comfort_1900_2300';
  return 'late_night_2300_0300';
}

const kLaunchWindows = [
  'pre_market_07_09', 'opening_bell_0915_0945', 'mid_day_0945_1430', 'closing_bell_1430_1535',
  'post_market_1535_1900', 'evening_comfort_1900_2300', 'late_night_2300_0300', 'weekend_sat_sun',
];

/// Launch sources the app can actually detect (no widget, deep links or alarms exist).
const kLaunchSources = ['icon', 'notification'];

/// Health metrics with a current/today/7d/30d series, all derived from events or live state.
const kHealthMetrics = [
  'crashed_since_last_open', 'crash_during_order_submission', 'crash_during_payment_checkout',
  'cold_start_under_1500ms', 'cold_start_slow_over_4000ms', 'login_streak_current_days',
  'login_streak_broken_yesterday', 'wallet_balance_to_starting_ratio', 'guest_account_unconverted_status',
  'google_or_apple_verified_oauth', 'dark_mode_active_preference', 'font_scale_enlarged_accessibility',
];

const kPaywallSteps = ['pack_view', 'checkout_start', 'purchase_success', 'purchase_failed'];

num _n(Object? v) => v is num ? v : num.tryParse('$v') ?? 0;
DateTime _day(DateTime t) => DateTime(t.year, t.month, t.day);

/// Every metric the analytics dashboard shows for one user, computed only from
/// recorded [events] (oldest first), [live] state (wallet ratio, guest, theme…)
/// and daily [snapshots]. Keys follow the catalogue names where one exists;
/// `x_` keys are extra product metrics with no catalogue name.
///
/// [includeZeros] emits every key the scorer can produce (for the coverage
/// count and per-user drill-down); uploads leave it off to stay small.
Map<String, num> scoreIntel(
  List<IntelEvent> events, {
  required DateTime now,
  Map<String, num> live = const {},
  Map<String, Map<String, num>> snapshots = const {},
  bool includeZeros = false,
}) {
  final out = <String, num>{};
  void put(String k, num v) {
    if (includeZeros || v != 0) out[k] = v;
  }

  void inc(Map<String, num> m, String k, [num by = 1]) => m[k] = (m[k] ?? 0) + by;
  final today = _day(now);
  final d7 = now.subtract(const Duration(days: 7));
  final d30 = now.subtract(const Duration(days: 30));
  bool isToday(DateTime t) => !t.isBefore(today);
  bool in7(DateTime t) => !t.isBefore(d7);
  bool in30(DateTime t) => !t.isBefore(d30);

  // ── Launches ────────────────────────────────────────────────────────────
  final launches = <String, num>{};
  final openDays = <DateTime>{};
  num lastColdStart = 0;
  var appOpens7 = 0, appOpens30 = 0;
  for (final e in events.where((e) => e.name == 'app_open' && in30(e.ts))) {
    openDays.add(_day(e.ts));
    appOpens30++;
    if (in7(e.ts)) appOpens7++;
    final src = '${e.props['source']}';
    if (kLaunchSources.contains(src)) inc(launches, 'launch_${src}_${launchWindow(e.ts)}');
    if (e.props['cold_start_ms'] != null) lastColdStart = _n(e.props['cold_start_ms']);
  }
  for (final s in kLaunchSources) {
    for (final w in kLaunchWindows) {
      put('launch_${s}_$w', launches['launch_${s}_$w'] ?? 0);
    }
  }
  put('x_app_opens_7d', appOpens7);
  put('x_app_opens_30d', appOpens30);

  // ── Health (current values; series come from snapshots) ─────────────────
  var streak = 0;
  for (var d = today; openDays.contains(d); d = d.subtract(const Duration(days: 1))) {
    streak++;
  }
  final yesterday = today.subtract(const Duration(days: 1));
  final crash = events.lastWhere((e) => e.name == 'crash_detected', orElse: () => IntelEvent('', {}, DateTime(0), ''));
  final lastOpen = events.lastWhere((e) => e.name == 'app_open' && e.props['source'] != 'resume',
      orElse: () => IntelEvent('', {}, DateTime(0), ''));
  // A crash counts "since last open" when it was detected at the latest cold open.
  final crashedNow = crash.name.isNotEmpty && lastOpen.name.isNotEmpty && crash.session == lastOpen.session;
  final crashScreen = '${crash.props['screen'] ?? ''}';
  final current = <String, num>{
    'crashed_since_last_open': crashedNow ? 1 : 0,
    'crash_during_order_submission': crashedNow && crashScreen == 'order_entry_screen' ? 1 : 0,
    'crash_during_payment_checkout': crashedNow && crashScreen == 'subscribe_screen' ? 1 : 0,
    'cold_start_under_1500ms': lastColdStart > 0 && lastColdStart < 1500 ? 1 : 0,
    'cold_start_slow_over_4000ms': lastColdStart > 4000 ? 1 : 0,
    'login_streak_current_days': streak,
    'login_streak_broken_yesterday':
        !openDays.contains(yesterday) && openDays.contains(yesterday.subtract(const Duration(days: 1))) ? 1 : 0,
    for (final k in ['wallet_balance_to_starting_ratio', 'guest_account_unconverted_status',
        'google_or_apple_verified_oauth', 'dark_mode_active_preference', 'font_scale_enlarged_accessibility'])
      k: live[k] ?? 0,
  };
  for (final k in kHealthMetrics) {
    final series = [
      for (var i = 1; i <= 30; i++) snapshots[IntelStore.dayKey(today.subtract(Duration(days: i)))]?['hw_$k'],
    ];
    final last7 = series.take(7).whereType<num>().toList();
    final last30 = series.whereType<num>().toList();
    final v = current[k]!;
    put('hw_${k}_current', v);
    put('hw_${k}_today', snapshots[IntelStore.dayKey(today)]?['hw_$k'] ?? v);
    put('hw_${k}_7d_trend', last7.isEmpty ? 0 : v - last7.reduce((a, b) => a + b) / last7.length);
    put('hw_${k}_30d_baseline', last30.isEmpty ? v : last30.reduce((a, b) => a + b) / last30.length);
  }
  put('x_cold_start_ms_last', lastColdStart);

  // ── Screens ─────────────────────────────────────────────────────────────
  final opensToday = <String, num>{}, opens7 = <String, num>{}, opens30 = <String, num>{}, everOpened = <String>{};
  final dwellToday = <String, num>{}, dwell30 = <String, num>{}, exits30 = <String, num>{};
  final bounces = <String, num>{}, scroll = <String, num>{}, rageScr = <String, num>{}, dropOff = <String, num>{};
  final sessionScreens = <String, Set<String>>{};
  final purchaseSessions = <String>{};
  String? lastScreen;
  for (final e in events) {
    final s = '${e.props['screen'] ?? ''}';
    switch (e.name) {
      case 'screen_view':
        everOpened.add(s);
        lastScreen = s;
        if (in30(e.ts)) {
          inc(opens30, s);
          (sessionScreens[e.session] ??= {}).add(s);
        }
        if (in7(e.ts)) inc(opens7, s);
        if (isToday(e.ts)) inc(opensToday, s);
      case 'screen_exit':
        final ms = _n(e.props['dwell_ms']);
        if (isToday(e.ts)) inc(dwellToday, s, ms / 1000);
        if (in30(e.ts)) {
          inc(dwell30, s, ms / 1000);
          inc(exits30, s);
          final pct = _n(e.props['scroll_pct']);
          if (pct > (scroll[s] ?? 0)) scroll[s] = pct;
        }
        if (in7(e.ts) && ms < 1500) inc(bounces, s);
      case 'rage_tap':
        if (in7(e.ts)) inc(rageScr, s);
      case 'app_pause':
        if (lastScreen != null && in30(e.ts)) inc(dropOff, lastScreen);
      case 'paywall_step':
        if (e.props['step'] == 'purchase_success' && in30(e.ts)) purchaseSessions.add(e.session);
    }
  }
  final allSessions = sessionScreens.length;
  final baseRate = allSessions == 0 ? 0 : purchaseSessions.length / allSessions;
  for (final s in kIntelScreens) {
    final p = 'scr_$s';
    put('${p}_opens_today', opensToday[s] ?? 0);
    put('${p}_opens_7d', opens7[s] ?? 0);
    put('${p}_never_opened_bool', everOpened.contains(s) ? 0 : 1);
    put('${p}_total_dwell_sec_today', (dwellToday[s] ?? 0).round());
    put('${p}_avg_dwell_sec_per_visit', (exits30[s] ?? 0) == 0 ? 0 : ((dwell30[s]! / exits30[s]!) * 10).round() / 10);
    put('${p}_pogo_bounce_under_1500ms', bounces[s] ?? 0);
    put('${p}_max_scroll_depth_pct', (scroll[s] ?? 0).round());
    put('${p}_rage_tap_bursts', rageScr[s] ?? 0);
    put('${p}_session_exit_drop_off', dropOff[s] ?? 0);
    // Percentage points: purchase rate of sessions that opened this screen minus all sessions.
    final withS = sessionScreens.entries.where((x) => x.value.contains(s)).map((x) => x.key).toList();
    final rate = withS.isEmpty ? 0 : withS.where(purchaseSessions.contains).length / withS.length;
    put('${p}_paid_conversion_lift_score', withS.isEmpty ? 0 : ((rate - baseRate) * 1000).round() / 10);
  }

  // ── Buttons ─────────────────────────────────────────────────────────────
  final tapsToday = <String, num>{}, taps7 = <String, num>{}, taps30 = <String, num>{}, rageBtn = <String, num>{};
  final latencySum = <String, num>{}, latencyN = <String, num>{}, led = <String, num>{};
  final lastViewAt = <String, DateTime>{};
  final tappedSinceView = <String, Set<String>>{};
  DateTime? lastAppOpen;
  final outcomes = events.where((e) =>
      e.name == 'trade_placed' || (e.name == 'paywall_step' && e.props['step'] == 'purchase_success')).map((e) => e.ts).toList();
  for (final e in events) {
    if (e.name == 'app_open') {
      lastAppOpen = e.ts;
      tappedSinceView['_app'] = {};
    } else if (e.name == 'screen_view') {
      final s = '${e.props['screen']}';
      lastViewAt[s] = e.ts;
      tappedSinceView[s] = {};
    } else if (e.name == 'tap' || e.name == 'rage_tap') {
      final b = '${e.props['button']}';
      if (e.name == 'rage_tap') {
        if (in30(e.ts)) inc(rageBtn, b);
        continue;
      }
      if (in30(e.ts)) {
        inc(taps30, b);
        final until = e.ts.add(const Duration(minutes: 5));
        if (outcomes.any((t) => !t.isBefore(e.ts) && !t.isAfter(until))) inc(led, b);
      }
      if (in7(e.ts)) inc(taps7, b);
      if (isToday(e.ts)) inc(tapsToday, b);
      final scr = buttonScreen(b) ?? '_app';
      final since = scr == '_app' ? lastAppOpen : lastViewAt[scr];
      final seen = tappedSinceView[scr] ??= {};
      if (since != null && seen.add(b) && in30(e.ts)) {
        inc(latencySum, b, e.ts.difference(since).inMilliseconds);
        inc(latencyN, b);
      }
    }
  }
  for (final b in kIntelButtons) {
    final p = 'btn_$b';
    final scr = buttonScreen(b);
    final denom7 = scr == null ? appOpens7 : (opens7[scr] ?? 0);
    final denom30 = scr == null ? appOpens30 : (opens30[scr] ?? 0);
    put('${p}_clicks_today', tapsToday[b] ?? 0);
    put('${p}_clicks_7d', taps7[b] ?? 0);
    put('${p}_clicks_30d', taps30[b] ?? 0);
    put('${p}_ctr_pct_7d', denom7 == 0 ? 0 : (((taps7[b] ?? 0) / denom7) * 1000).round() / 10);
    // Catalogue definition: its screen opened 10+ times in 30 days, button never tapped.
    put('${p}_zero_click_dead_button_flag', denom30 >= 10 && (taps30[b] ?? 0) == 0 ? 1 : 0);
    put('${p}_first_click_latency_ms', (latencyN[b] ?? 0) == 0 ? 0 : (latencySum[b]! / latencyN[b]!).round());
    put('${p}_rage_double_taps', rageBtn[b] ?? 0);
    put('${p}_led_to_revenue_or_trade_5m', led[b] ?? 0);
  }

  // ── Symbols ─────────────────────────────────────────────────────────────
  final views7 = <String, num>{}, placedToday = <String, num>{}, won7 = <String, num>{}, lost7 = <String, num>{};
  final won30 = <String, num>{}, closed30 = <String, num>{}, pnl30 = <String, num>{}, shortfalls = <String, num>{};
  final revenge = <String, num>{}, holdSum = <String, num>{}, holdN = <String, num>{}, strikes = <String, num>{}, whatif = <String, num>{};
  final winStreak = <String, num>{}, lossStreak = <String, num>{};
  final openedAt = <String, DateTime>{}, lastLossAt = <String, DateTime>{};
  var revengeAny24h = false;
  for (final e in events) {
    final slug = symbolSlug('${e.props['sym'] ?? ''}');
    if (slug == null) continue;
    switch (e.name) {
      case 'chart_view':
        if (in7(e.ts)) inc(views7, slug);
      case 'trade_placed':
        if (isToday(e.ts)) inc(placedToday, slug);
        openedAt.putIfAbsent(slug, () => e.ts);
        final loss = lastLossAt[slug];
        if (loss != null && e.ts.difference(loss).inSeconds <= 120) {
          if (in30(e.ts)) inc(revenge, slug);
          if (now.difference(e.ts).inHours < 24) revengeAny24h = true;
        }
      case 'trade_closed':
        final pnl = _n(e.props['pnl']);
        final win = pnl >= 0;
        winStreak[slug] = win ? (winStreak[slug] ?? 0) + 1 : 0;
        lossStreak[slug] = win ? 0 : (lossStreak[slug] ?? 0) + 1;
        if (!win) lastLossAt[slug] = e.ts;
        final opened = openedAt.remove(slug);
        if (in30(e.ts)) {
          inc(closed30, slug);
          if (win) inc(won30, slug);
          inc(pnl30, slug, pnl);
          if (opened != null) {
            inc(holdSum, slug, e.ts.difference(opened).inMinutes);
            inc(holdN, slug);
          }
        }
        if (in7(e.ts)) inc(win ? won7 : lost7, slug);
      case 'margin_shortfall':
        if (in30(e.ts)) inc(shortfalls, slug);
      case 'tap':
        if (!in30(e.ts)) break;
        final b = '${e.props['button']}';
        if (b == 'option_chain_call_ce_cell_tap' || b == 'option_chain_put_pe_cell_tap') inc(strikes, slug);
        if (b == 'whatif_run_simulation_cta') inc(whatif, slug);
    }
  }
  for (final s in kIntelSymbols) {
    final p = 'sym_$s';
    put('${p}_chart_views_7d', views7[s] ?? 0);
    put('${p}_trades_placed_today', placedToday[s] ?? 0);
    put('${p}_trades_won_7d', won7[s] ?? 0);
    put('${p}_trades_lost_7d', lost7[s] ?? 0);
    put('${p}_consecutive_losses_streak', lossStreak[s] ?? 0);
    put('${p}_consecutive_wins_streak', winStreak[s] ?? 0);
    put('${p}_net_realized_pnl_inr', (pnl30[s] ?? 0).round());
    put('${p}_margin_shortfall_rejections', shortfalls[s] ?? 0);
    put('${p}_revenge_trade_under_120s', revenge[s] ?? 0);
    put('${p}_avg_hold_time_minutes', (holdN[s] ?? 0) == 0 ? 0 : (holdSum[s]! / holdN[s]!).round());
    put('${p}_user_personal_win_prob_0_to_1', (closed30[s] ?? 0) == 0 ? 0 : ((won30[s] ?? 0) / closed30[s]! * 100).round() / 100);
    put('${p}_option_chain_strikes_tapped', strikes[s] ?? 0);
    put('${p}_whatif_time_machine_runs', whatif[s] ?? 0);
  }
  put('x_revenge_reentry_24h', revengeAny24h ? 1 : 0);

  // ── Paywall funnel ──────────────────────────────────────────────────────
  final steps = <String, num>{};
  for (final e in events.where((e) => e.name == 'paywall_step' && in30(e.ts))) {
    inc(steps, '${e.props['step']}');
  }
  for (final s in kPaywallSteps) {
    put('x_paywall_${s}_30d', steps[s] ?? 0);
  }
  final starts = steps['checkout_start'] ?? 0;
  put('x_paywall_checkout_dropoff_pct', starts == 0 ? 0 : ((1 - (steps['purchase_success'] ?? 0) / starts) * 100).round());
  final views = steps['pack_view'] ?? 0;
  put('x_paywall_view_to_checkout_pct', views == 0 ? 0 : (starts / views * 100).round());
  return out;
}
