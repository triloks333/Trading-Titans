import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'action_reaction_engine.dart';
import 'analytics_service.dart';
import 'intel/intel_ids.dart';
import 'intel/intel_scorer.dart';
import 'intel/intel_store.dart';

/// Product analytics: records what the user does (launches, screens, taps,
/// trades, paywall steps) into [IntelStore], batch-uploads raw events to
/// `intel_events`, and uploads the computed metrics ([scoreIntel]) to
/// `intel_user_state` for the admin dashboard.
///
/// Read-only with respect to money: never touches wallets, orders or prices.
/// No permissions, no device fingerprinting, no location.
class ChurnTelemetryService {
  ChurnTelemetryService._();
  static final ChurnTelemetryService instance = ChurnTelemetryService._();

  /// Set as the first line of `main()`; cold start = first frame minus this.
  static DateTime processStart = DateTime.now();

  bool _initialized = false;
  SharedPreferences? _prefs;

  final IntelStore intel = IntelStore();
  Timer? _uploadTimer;
  int _ticks = 0;
  bool _uploading = false;

  String _currentScreenId = 'unknown';
  DateTime _currentScreenStartTime = DateTime.now();
  double _currentScrollPct = 0;

  /// Screen shown by the root route (welcome, onboarding, or the active tab).
  String homeScreenId = 'unknown';

  final Map<String, List<DateTime>> _tapTimestamps = {};
  DateTime? _notificationTapAt;
  final Map<String, num> _live = {};

  bool get isInitialized => _initialized;
  String get currentScreenId => _currentScreenId;

  Future<void> init() async {
    if (_initialized) return;
    try {
      _prefs = await SharedPreferences.getInstance();
      await intel.load();
      _uploadTimer ??= Timer.periodic(const Duration(seconds: 60), (_) {
        uploadEvents();
        if (++_ticks % 5 == 0) uploadState();
      });
      _initialized = true;
    } catch (e) {
      debugPrint('[ChurnTelemetryService] Init error (non-fatal): $e');
    }
  }

  // ── Launches ──────────────────────────────────────────────────────────────
  /// `source`: 'app_launch' (cold start from the icon) or 'resume'. A
  /// notification tap within 10s relabels either one as 'notification'.
  void recordAppLaunch({required String source}) {
    final cold = source == 'app_launch';
    final viaPush = _notificationTapAt != null && DateTime.now().difference(_notificationTapAt!).inSeconds < 10;
    final e = intel.add('app_open', {'source': viaPush ? 'notification' : (cold ? 'icon' : 'resume')});
    if (cold) {
      WidgetsBinding.instance.addPostFrameCallback(
          (_) => e.props['cold_start_ms'] = DateTime.now().difference(processStart).inMilliseconds);
    }
    AnalyticsService.log('telemetry_launch', {'source': '${e.props['source']}'});
  }

  /// Called when a notification tap opens the app (cold or from background).
  void markLaunchFromNotification() {
    _notificationTapAt = DateTime.now();
    final last = intel.events.lastWhere((e) => e.name == 'app_open', orElse: () => IntelEvent('', {}, DateTime(0), ''));
    if (last.name.isNotEmpty && DateTime.now().difference(last.ts).inSeconds < 30) last.props['source'] = 'notification';
  }

  // ── Crash sentinel ────────────────────────────────────────────────────────
  static const pendingApologyKey = 'intel_pending_crash_apology';

  /// The previous run never reached `paused` (crash, ANR or force-kill while
  /// in the foreground): log it and queue the crash apology check.
  Future<void> recordSessionStart() async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    if (!(prefs.getBool('telemetry_clean_session_exit') ?? true)) {
      final screen = prefs.getString('telemetry_last_screen') ?? 'unknown';
      intel.add('crash_detected', {'screen': screen});
      await prefs.setBool(pendingApologyKey, true);
      AnalyticsService.log('telemetry_crash_sentinel_detected', {'last_screen': screen});
    }
    await prefs.setBool('telemetry_clean_session_exit', false);
  }

  Future<void> recordCleanExit() async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    await prefs.setBool('telemetry_clean_session_exit', true);
  }

  // ── Screens ───────────────────────────────────────────────────────────────
  void recordScreenOpen(String screen) {
    final screenId = screenSlug(screen);
    if (screenId == _currentScreenId) return;
    final now = DateTime.now();
    if (_currentScreenId != 'unknown') {
      final dwellMs = now.difference(_currentScreenStartTime).inMilliseconds;
      intel.add('screen_exit', {'screen': _currentScreenId, 'dwell_ms': dwellMs, 'scroll_pct': _currentScrollPct.round()});
    }
    _currentScreenId = screenId;
    _currentScreenStartTime = now;
    _currentScrollPct = 0;
    intel.add('screen_view', {'screen': screenId});
    _prefs?.setString('telemetry_last_screen', screenId);
    AnalyticsService.log('telemetry_screen_open', {'screen_id': screenId});
  }

  /// Root-level screens (welcome, onboarding, main tabs) call this; the route
  /// observer replays it when the user pops back to the root route.
  void recordHomeScreen(String screen) {
    homeScreenId = screenSlug(screen);
    recordScreenOpen(homeScreenId);
  }

  /// Fed by a global scroll listener; keeps the deepest point on this screen.
  void recordScroll(ScrollMetrics m) {
    if (m.axis != Axis.vertical || m.maxScrollExtent <= 0) return;
    final pct = (m.pixels / m.maxScrollExtent * 100).clamp(0, 100).toDouble();
    if (pct > _currentScrollPct) _currentScrollPct = pct;
  }

  // ── Buttons ───────────────────────────────────────────────────────────────
  /// [buttonId] is a catalogue id from `kIntelButtons` (e.g.
  /// 'order_ticket_type_limit_btn'). Pass `sym` in [extra] for symbol-scoped taps.
  void recordButtonTap(String buttonId, {String? screenId, Map<String, Object>? extra}) {
    final sid = screenId == null ? _currentScreenId : screenSlug(screenId);
    final now = DateTime.now();
    final ts = (_tapTimestamps[buttonId] ??= [])..add(now);
    ts.removeWhere((t) => now.difference(t).inMilliseconds > 800);
    final isRageTap = ts.length >= 3;
    intel.add('tap', {'screen': sid, 'button': buttonId, if (extra != null) ...extra});
    if (isRageTap) {
      intel.add('rage_tap', {'screen': sid, 'button': buttonId, 'count': ts.length});
      ts.clear(); // one burst per three taps, not one per tap after the third
      ActionReactionEngine.instance.flagRageButton(buttonId, sid);
    }
    AnalyticsService.log('telemetry_button_tap', {'button_id': buttonId, 'screen_id': sid, 'is_rage_tap': isRageTap});
  }

  // ── Trading ───────────────────────────────────────────────────────────────
  void recordSymbolChartView(String symbol) {
    intel.add('chart_view', {'sym': symbol});
    AnalyticsService.log('telemetry_symbol_view', {'symbol': symbol});
  }

  void recordTradePlaced({required String symbol, required String side, required num qty, required String segment}) =>
      intel.add('trade_placed', {'sym': symbol, 'side': side, 'qty': qty, 'segment': segment});

  void recordTradeOutcome({required String symbol, required bool isProfit, double? pnl}) {
    intel.add('trade_closed', {'sym': symbol, 'pnl': pnl ?? (isProfit ? 0 : -1)});
    AnalyticsService.log('telemetry_trade_outcome', {'symbol': symbol, 'is_profit': isProfit});
  }

  /// Consecutive (wins, losses) ending at the latest close on [symbol].
  (int, int) symbolStreak(String symbol) {
    var wins = 0, losses = 0;
    for (final e in intel.events.reversed) {
      if (e.name != 'trade_closed' || e.props['sym'] != symbol) continue;
      final win = ((e.props['pnl'] as num?) ?? 0) >= 0;
      if (win && losses == 0) {
        wins++;
      } else if (!win && wins == 0) {
        losses++;
      } else {
        break;
      }
    }
    return (wins, losses);
  }

  /// A trade placed within 120s of a losing close, in the last 24 hours.
  bool get recentRevengeReentry => scoreIntel(intel.events, now: DateTime.now())['x_revenge_reentry_24h'] == 1;

  void recordMarginShortfall({required String symbol, required double requiredMargin, required double availableCash}) {
    intel.add('margin_shortfall', {'sym': symbol, 'required': requiredMargin, 'available': availableCash});
    AnalyticsService.log('telemetry_margin_shortfall', {
      'symbol': symbol,
      'shortfall_inr': requiredMargin - availableCash,
    });
  }

  // ── Paywall ───────────────────────────────────────────────────────────────
  void recordPaywallStep(String step, {String? sku}) => intel.add('paywall_step', {'step': step, 'sku': sku});

  void recordPaywallPackView(String sku) {
    recordPaywallStep('pack_view', sku: sku);
    AnalyticsService.log('telemetry_pack_view', {'sku': sku});
  }

  // ── Live account state (for health metrics) ───────────────────────────────
  void updateLive({
    required double walletBalance,
    required double startingCash,
    required bool isGuest,
    required bool oauth,
    required bool darkMode,
    required double textScale,
  }) {
    _live
      ..['wallet_balance'] = walletBalance
      ..['wallet_balance_to_starting_ratio'] = startingCash <= 0 ? 0 : (walletBalance / startingCash * 100).round() / 100
      ..['guest_account_unconverted_status'] = isGuest ? 1 : 0
      ..['google_or_apple_verified_oauth'] = oauth ? 1 : 0
      ..['dark_mode_active_preference'] = darkMode ? 1 : 0
      ..['font_scale_enlarged_accessibility'] = textScale > 1.1 ? 1 : 0;
  }

  num? get walletBalance => _live['wallet_balance'];

  /// The full metric set for this user right now.
  Map<String, num> computeMetrics({bool includeZeros = false}) =>
      scoreIntel(intel.events, now: DateTime.now(), live: _live, snapshots: intel.snapshots, includeZeros: includeZeros);

  // ── Upload ────────────────────────────────────────────────────────────────
  /// Batch-inserts unsent events into `intel_events` (max 500 per call).
  /// Failed batches stay queued; never throws.
  Future<void> uploadEvents() async {
    if (_uploading) return;
    _uploading = true;
    try {
      final client = Supabase.instance.client;
      final user = client.auth.currentUser;
      if (user == null) return;
      await intel.upload((batch) => client.from('intel_events').insert([
            for (final e in batch)
              {
                'user_id': user.id,
                'session_id': e.session,
                'name': e.name,
                'props': e.props,
                'client_ts': e.ts.toUtc().toIso8601String(),
              },
          ]));
    } catch (e) {
      debugPrint('[ChurnTelemetryService] uploadEvents non-fatal error: $e');
    } finally {
      _uploading = false;
    }
  }

  /// Upserts the computed metrics into `intel_user_state` and snapshots
  /// today's health values for the 7d/30d series. Never throws.
  Future<void> uploadState() async {
    try {
      final metrics = computeMetrics();
      for (final k in kHealthMetrics) {
        intel.snapshot('hw_$k', metrics['hw_${k}_current'] ?? 0);
      }
      final client = Supabase.instance.client;
      final user = client.auth.currentUser;
      if (user == null) return;
      await client.from('intel_user_state').upsert({
        'user_id': user.id,
        'metrics': metrics,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
      await ActionReactionEngine.instance.flagDeadButtons(metrics);
    } catch (e) {
      debugPrint('[ChurnTelemetryService] uploadState non-fatal error: $e');
    }
  }

  /// On pause: close the current screen's dwell, persist, upload everything.
  Future<void> flushToBackend() async {
    if (_currentScreenId != 'unknown') {
      final dwellMs = DateTime.now().difference(_currentScreenStartTime).inMilliseconds;
      intel.add('screen_exit', {'screen': _currentScreenId, 'dwell_ms': dwellMs, 'scroll_pct': _currentScrollPct.round()});
      _pausedScreen = _currentScreenId;
      _currentScreenId = 'unknown';
    }
    intel.add('app_pause');
    await intel.persist();
    await uploadEvents();
    await uploadState();
  }

  String? _pausedScreen;

  /// Back from background: the screen that was on top is visible again.
  void resumeAfterPause() {
    final s = _pausedScreen;
    _pausedScreen = null;
    if (s != null) recordScreenOpen(s);
  }
}

/// Feeds page route changes into [ChurnTelemetryService] under the screen
/// widget's name (`MaterialPageRoute` → `order_entry_screen`). Popups
/// (dialogs, sheets) are not screens and are ignored.
class ChurnTelemetryNavigatorObserver extends RouteObserver<PageRoute<dynamic>> {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    _record(route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    if (newRoute != null) _record(newRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    if (route is PageRoute && previousRoute != null) _record(previousRoute);
  }

  void _record(Route<dynamic> route) {
    if (route is! PageRoute) return;
    final t = ChurnTelemetryService.instance;
    // The root route hosts welcome/onboarding/main tabs; they report themselves.
    final name = route.isFirst ? t.homeScreenId : screenNameOf(route);
    t.recordScreenOpen(name);
  }

  /// `MaterialPageRoute(builder: (_) => const OrderEntryScreen())` → 'order_entry_screen'.
  @visibleForTesting
  static String screenNameOf(Route<dynamic> route) {
    final ctx = route.navigator?.context;
    if (route is MaterialPageRoute && ctx != null) {
      try {
        // Builders here only construct the screen widget; no side effects.
        return screenSlug(route.builder(ctx).runtimeType.toString());
      } catch (_) {}
    }
    return screenSlug(route.settings.name ?? route.runtimeType.toString());
  }
}
