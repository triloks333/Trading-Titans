import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme.dart';
import '../../services/intel/intel_scorer.dart';

/// Admin → Intelligence. Live from four realtime streams: `intel_events` (raw
/// events, last 24h), `intel_user_state` (per-user computed metrics),
/// `intel_reaction_firings` (every reaction, delivered or suppressed) and
/// `intel_offer_grants` (downshift offers), plus the overview and offers RPCs
/// every 30s. Every number on screen comes from those sources.
///
/// Layout follows the Claude Design canvas "Intelligence" (8 tabs, sticky-column
/// tables, one problem-highlight rule, master-detail on wide windows).
class AdminCustomerIntelligenceScreen extends StatefulWidget {
  final bool embedded;
  const AdminCustomerIntelligenceScreen({super.key, this.embedded = false});

  @override
  State<AdminCustomerIntelligenceScreen> createState() => _AdminCustomerIntelligenceScreenState();
}

// ── Store ───────────────────────────────────────────────────────────────────

/// Shared live store for every tab and drill-down.
class _Store extends ChangeNotifier {
  static const _cap = 10000;
  final List<Map<String, dynamic>> events = [];
  final Set<Object> _ids = {};
  final Map<String, String> names = {};
  final Map<String, Map<String, dynamic>> states = {}; // user_id → {metrics, updated_at}
  final List<Map<String, dynamic>> firings = [];
  final Set<Object> _firingIds = {};
  final Map<String, Map<String, dynamic>> grants = {}; // id → grant row
  final Map<String, Map<String, dynamic>> plans = {}; // sku → {title, price_paise}
  Map<String, dynamic>? overview, offers;
  DateTime? updatedAt;

  void _touch() {
    updatedAt = DateTime.now();
    notifyListeners();
  }

  void loadEvents(List<Map<String, dynamic>> rows) {
    for (final r in rows) {
      if (_ids.add(r['id'])) events.add(r);
    }
    events.sort((a, b) => _ts(b).compareTo(_ts(a)));
    _touch();
  }

  bool addEvent(Map<String, dynamic> row) {
    if (!_ids.add(row['id'])) return false;
    events.insert(0, row);
    if (events.length > _cap) _ids.remove(events.removeLast()['id']);
    _touch();
    return true;
  }

  void putState(Map<String, dynamic> row) {
    states['${row['user_id']}'] = row;
    _touch();
  }

  void addFirings(Iterable<Map<String, dynamic>> rows) {
    for (final r in rows) {
      if (_firingIds.add(r['id'])) firings.add(r);
    }
    firings.sort((a, b) => _ts(b).compareTo(_ts(a)));
    _touch();
  }

  void putGrant(Map<String, dynamic> row) {
    grants['${row['id']}'] = row;
    _touch();
  }

  void setNames(Map<String, String> m) {
    names.addAll(m);
    notifyListeners();
  }

  void setOverview(Map<String, dynamic>? o, Map<String, dynamic>? off) {
    if (o != null) overview = o;
    if (off != null) offers = off;
    notifyListeners();
  }

  String nameOf(String? uid) => uid == null ? 'anonymous' : (names[uid] ?? '${uid.substring(0, math.min(8, uid.length))}…');

  Map<String, num> metricsOf(String uid) {
    final m = states[uid]?['metrics'];
    return m is Map ? {for (final e in m.entries) '${e.key}': _num(e.value)} : const {};
  }

  num sum(String key) => states.keys.fold<num>(0, (a, u) => a + (metricsOf(u)[key] ?? 0));
  int usersWith(String key) => states.keys.where((u) => (metricsOf(u)[key] ?? 0) > 0).length;
  num avgOfUsers(String key) {
    final n = usersWith(key);
    return n == 0 ? 0 : sum(key) / n;
  }

  /// Distinct entity ids in metric keys, e.g. `btn_<id>_clicks_7d` → id.
  Set<String> entities(String prefix, String suffix) => {
        for (final u in states.keys)
          for (final k in metricsOf(u).keys)
            if (k.startsWith(prefix) && k.endsWith(suffix)) k.substring(prefix.length, k.length - suffix.length),
      };

  Map<String, int> liveCount(String event, String prop) {
    final m = <String, int>{};
    for (final e in events.where((e) => e['name'] == event)) {
      final k = '${_props(e)[prop]}';
      m[k] = (m[k] ?? 0) + 1;
    }
    return m;
  }
}

DateTime _ts(Map<String, dynamic> e) =>
    DateTime.tryParse('${e['created_at'] ?? e['updated_at'] ?? e['granted_at']}')?.toLocal() ?? DateTime.fromMillisecondsSinceEpoch(0);
Map<String, dynamic> _props(Map<String, dynamic> e) => e['props'] is Map ? Map<String, dynamic>.from(e['props'] as Map) : const {};
num _num(Object? v) => v is num ? v : num.tryParse('$v') ?? 0;
String _fmt(num v) => v == v.roundToDouble() ? '${v.round()}' : v.toStringAsFixed(v.abs() < 10 ? 2 : 1);
String _inr(num paise) => '₹${(paise / 100).toStringAsFixed(paise % 100 == 0 ? 0 : 2)}';

String _ago(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inSeconds < 60) return '${d.inSeconds.clamp(0, 59)}s ago';
  if (d.inMinutes < 60) return '${d.inMinutes}m ago';
  if (d.inHours < 24) return '${d.inHours}h ago';
  return '${d.inDays}d ago';
}

String _left(DateTime t) {
  final d = t.difference(DateTime.now());
  if (d.isNegative) return 'expired';
  if (d.inHours < 1) return '${d.inMinutes}m';
  if (d.inHours < 24) return '${d.inHours}h ${d.inMinutes % 60}m';
  return '${d.inDays}d ${d.inHours % 24}h';
}

/// Percent off a grant has right now: 50, then 75, then 0 (same rule as the server).
int _grantPct(Map<String, dynamic> g) {
  final now = DateTime.now();
  if (g['redeemed_at'] != null) return 0;
  final exp = DateTime.tryParse('${g['expires_at']}');
  final s2 = DateTime.tryParse('${g['stage2_at']}');
  if (exp == null || !now.isBefore(exp)) return 0;
  return s2 != null && !now.isBefore(s2) ? 75 : 50;
}

// ── Problem rule (one place) ────────────────────────────────────────────────

bool _screenProblem(_Store s, String x) =>
    s.sum('scr_${x}_error_state_views') > 0 || s.sum('scr_${x}_dead_tap_non_clickable') >= 3 || s.sum('scr_${x}_rage_tap_bursts') > 0;
bool _buttonProblem(_Store s, String b) =>
    s.sum('btn_${b}_rage_double_taps') > 0 || s.usersWith('btn_${b}_zero_click_dead_button_flag') > 0 || s.sum('btn_${b}_error_after_click') > 0;
bool _symbolProblem(_Store s, String x) => s.sum('sym_${x}_margin_shortfall_rejections') >= 3 || s.sum('sym_${x}_revenge_trade_under_120s') >= 2;

/// Metric names that count as a problem when non-zero (detail chips).
const _problemWords = ['rage', 'dead', 'error', 'bounce', 'shortfall', 'revenge', 'crash', 'grade_d', 'bag_holding', 'premature'];
bool _isProblemMetric(String k, num v) => v > 0 && _problemWords.any(k.contains);

List<String> _buttonsIn(_Store s) => {
      ...s.entities('btn_', '_clicks_30d'),
      ...s.entities('btn_', '_zero_click_dead_button_flag'),
      ...s.entities('btn_', '_rage_double_taps'),
      ...s.entities('btn_', '_error_after_click'),
    }.toList();

// ── Screen ──────────────────────────────────────────────────────────────────

class _AdminCustomerIntelligenceScreenState extends State<AdminCustomerIntelligenceScreen> {
  final _db = Supabase.instance.client;
  final _store = _Store();
  RealtimeChannel? _channel;
  Timer? _overviewTimer, _clockTimer;
  String? _error;
  bool _loading = true;
  bool _closing = false;
  bool _everLive = false;
  String _status = 'connecting';
  bool _paused = false;
  int _pausedAtCount = 0;
  int _tab = 0;

  static const _tabs = ['Overview', 'Live', 'Users', 'Reactions', 'Discounts', 'Screens', 'Buttons', 'Symbols'];
  static const _icons = [
    Icons.dashboard_outlined, Icons.bolt_outlined, Icons.people_outline, Icons.campaign_outlined,
    Icons.sell_outlined, Icons.phone_android_outlined, Icons.touch_app_outlined, Icons.candlestick_chart_outlined,
  ];

  @override
  void initState() {
    super.initState();
    _subscribe();
    _overviewTimer = Timer.periodic(const Duration(seconds: 30), (_) => _loadOverview());
    // Keeps the "x ago" labels honest without refetching.
    _clockTimer = Timer.periodic(const Duration(seconds: 15), (_) => mounted ? setState(() {}) : null);
    _refresh();
  }

  void _subscribe() {
    final old = _channel;
    if (old != null) _db.removeChannel(old);
    // Subscribe first so no row falls between the snapshot and the stream; the store dedupes.
    _channel = _db
        .channel('admin-intel-${DateTime.now().millisecondsSinceEpoch}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'intel_events',
          callback: (p) {
            final row = Map<String, dynamic>.from(p.newRecord);
            if (_store.addEvent(row)) _resolveNames([row['user_id'] as String?]);
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'intel_user_state',
          callback: (p) {
            if (p.newRecord.isEmpty) return;
            final row = Map<String, dynamic>.from(p.newRecord);
            _store.putState(row);
            _resolveNames([row['user_id'] as String?]);
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'intel_reaction_firings',
          callback: (p) {
            final row = Map<String, dynamic>.from(p.newRecord);
            _store.addFirings([row]);
            _resolveNames([row['user_id'] as String?]);
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'intel_offer_grants',
          callback: (p) {
            if (p.newRecord.isEmpty) return;
            final row = Map<String, dynamic>.from(p.newRecord);
            _store.putGrant(row);
            _resolveNames([row['user_id'] as String?]);
          },
        )
        .subscribe((status, err) {
      // removeChannel() in dispose fires this synchronously; ignore it then.
      if (!mounted || _closing) return;
      final live = status == RealtimeSubscribeStatus.subscribed;
      if (live) _everLive = true;
      setState(() => _status = live ? 'live' : (_everLive ? 'reconnecting' : 'connecting'));
    });
  }

  Future<void> _refresh() async {
    final errors = <String>[];
    Future<void> guard(String what, Future<void> Function() f) async {
      try {
        await f();
      } catch (e) {
        errors.add('$what ($e)');
      }
    }

    await Future.wait([
      guard('events', _loadEvents),
      guard('user metrics', _loadStates),
      guard('reactions', _loadFirings),
      guard('discounts', _loadGrants),
      _loadOverview(),
    ]);
    if (mounted) {
      setState(() {
        _loading = false;
        _error = errors.isEmpty ? null : 'Could not load ${errors.join('; ')}';
      });
    }
  }

  Future<void> _loadEvents() async {
    final since = DateTime.now().toUtc().subtract(const Duration(hours: 24)).toIso8601String();
    final rows = await _db
        .from('intel_events')
        .select('id, user_id, session_id, name, props, client_ts, created_at')
        .gte('created_at', since)
        .order('created_at', ascending: false)
        .limit(5000);
    _store.loadEvents(List<Map<String, dynamic>>.from(rows));
    await _resolveNames(_store.events.map((e) => e['user_id'] as String?));
  }

  Future<void> _loadStates() async {
    final rows = await _db.from('intel_user_state').select('user_id, metrics, updated_at').order('updated_at', ascending: false).limit(1000);
    for (final r in rows) {
      _store.putState(Map<String, dynamic>.from(r));
    }
    await _resolveNames(_store.states.keys);
  }

  Future<void> _loadFirings() async {
    final since = DateTime.now().toUtc().subtract(const Duration(days: 7)).toIso8601String();
    final rows = await _db
        .from('intel_reaction_firings')
        .select('id, user_id, reaction, delivered, reason, props, created_at')
        .gte('created_at', since)
        .order('created_at', ascending: false)
        .limit(2000);
    _store.addFirings(List<Map<String, dynamic>>.from(rows));
    await _resolveNames(_store.firings.map((e) => e['user_id'] as String?));
  }

  Future<void> _loadGrants() async {
    final since = DateTime.now().toUtc().subtract(const Duration(days: 30)).toIso8601String();
    final plans = await _db.from('plan_catalogue').select('sku, title, price_paise');
    for (final p in plans) {
      _store.plans['${p['sku']}'] = Map<String, dynamic>.from(p);
    }
    final rows = await _db.from('intel_offer_grants').select().gte('granted_at', since).order('granted_at', ascending: false).limit(1000);
    for (final r in rows) {
      _store.putGrant(Map<String, dynamic>.from(r));
    }
    await _resolveNames(_store.grants.values.map((g) => g['user_id'] as String?));
  }

  Future<void> _loadOverview() async {
    Map<String, dynamic>? o, off;
    try {
      final res = await _db.rpc('intel_admin_overview');
      if (res is Map) o = Map<String, dynamic>.from(res);
    } catch (_) {}
    try {
      final res = await _db.rpc('intel_admin_offers');
      if (res is Map) off = Map<String, dynamic>.from(res);
    } catch (_) {}
    // Tiles keep their last real value when a call fails; the streams still update.
    _store.setOverview(o, off);
  }

  Future<void> _resolveNames(Iterable<String?> uids) async {
    final missing = uids.whereType<String>().where((u) => !_store.names.containsKey(u)).toSet().toList();
    if (missing.isEmpty) return;
    try {
      final m = <String, String>{};
      for (var i = 0; i < missing.length; i += 100) {
        final rows = await _db.from('profiles').select('id, name, email').inFilter('id', missing.sublist(i, math.min(i + 100, missing.length)));
        for (final r in rows) {
          final n = '${r['name'] ?? ''}'.trim();
          m['${r['id']}'] = n.isNotEmpty ? n : '${r['email'] ?? r['id']}';
        }
      }
      _store.setNames(m);
    } catch (_) {
      // Falls back to the short uid.
    }
  }

  void _retry() {
    setState(() => _status = 'connecting');
    _subscribe();
    _refresh();
  }

  @override
  void dispose() {
    _closing = true;
    _overviewTimer?.cancel();
    _clockTimer?.cancel();
    final ch = _channel;
    if (ch != null) _db.removeChannel(ch);
    _store.dispose();
    super.dispose();
  }

  int get _problemButtons => _buttonsIn(_store).where((b) => _buttonProblem(_store, b)).length;
  int get _activeGrants => _store.grants.values.where((g) => _grantPct(g) > 0).length;

  @override
  Widget build(BuildContext context) {
    final content = LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth >= 1024;
      final body = ListenableBuilder(
        listenable: _store,
        builder: (context, _) => Column(children: [
          if (!wide) _tabBar(),
          if (_status == 'reconnecting') _staleBanner(),
          Expanded(child: _loading ? const _Skeleton() : _tabBody(wide)),
        ]),
      );
      return Container(
        color: AppColors.parchment,
        child: Column(children: [
          ListenableBuilder(listenable: _store, builder: (_, _) => _header()),
          Expanded(
            child: wide
                ? Row(children: [
                    SizedBox(width: 220, child: ListenableBuilder(listenable: _store, builder: (_, _) => _rail())),
                    VerticalDivider(width: 1, color: AppColors.birch),
                    Expanded(child: body),
                  ])
                : body,
          ),
        ]),
      );
    });
    if (widget.embedded) return content;
    return Scaffold(
      appBar: AppBar(title: const Text('Intelligence'), backgroundColor: AppColors.pureWhite, foregroundColor: AppColors.ink, elevation: 0),
      body: content,
    );
  }

  Widget _badge(int i) {
    final (n, bg, fg) = switch (i) {
      6 => (_problemButtons, AppColors.bearLight, AppColors.bear),
      4 => (_activeGrants, AppColors.blueLight, AppColors.blue),
      _ => (0, Colors.transparent, Colors.transparent),
    };
    if (n == 0) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(AppRadius.pill)),
      child: Text('$n', style: AppFonts.mono(size: 11, weight: FontWeight.w600, color: fg)),
    );
  }

  Widget _tabBar() => Container(
        height: 44,
        decoration: BoxDecoration(color: AppColors.pureWhite, border: Border(bottom: BorderSide(color: AppColors.birch))),
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          children: [
            for (var i = 0; i < _tabs.length; i++)
              InkWell(
                onTap: () => setState(() => _tab = i),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: _tab == i ? AppColors.blue : Colors.transparent, width: 2)),
                  ),
                  child: Row(children: [
                    Text(_tabs[i], style: AppFonts.sans(size: 13, weight: FontWeight.w600, color: _tab == i ? AppColors.blue : AppColors.ink3)),
                    _badge(i),
                  ]),
                ),
              ),
          ],
        ),
      );

  Widget _rail() => Container(
        color: AppColors.pureWhite,
        child: ListView(padding: const EdgeInsets.symmetric(vertical: 8), children: [
          for (var i = 0; i < _tabs.length; i++)
            ListTile(
              dense: true,
              selected: _tab == i,
              selectedColor: AppColors.blue,
              selectedTileColor: AppColors.blueLight,
              leading: Icon(_icons[i], size: 20),
              title: Row(children: [
                Text(_tabs[i], style: AppFonts.sans(size: 13, weight: FontWeight.w600)),
                _badge(i),
              ]),
              onTap: () => setState(() => _tab = i),
            ),
        ]),
      );

  Widget _livePill() {
    final (label, bg, fg) = _paused
        ? ('PAUSED · ${math.max(0, _store.events.length - _pausedAtCount)} NEW', AppColors.blueLight, AppColors.blue)
        : switch (_status) {
            'live' => ('LIVE', AppColors.bullLight, AppColors.bull),
            'reconnecting' => ('RECONNECTING', AppColors.titanGoldSoft, AppColors.titanGold),
            _ => ('CONNECTING', AppColors.cream, AppColors.ink3),
          };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(AppRadius.pill)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 6, height: 6, decoration: BoxDecoration(color: fg, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text(label, style: AppFonts.mono(size: 10, weight: FontWeight.w600, color: fg, spacing: 0.4)),
      ]),
    );
  }

  Widget _header() {
    final upd = _store.updatedAt;
    return Container(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 10, 8, 10),
      decoration: BoxDecoration(color: AppColors.pureWhite, border: Border(bottom: BorderSide(color: AppColors.birch))),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Intelligence', style: AppFonts.sans(size: 17, weight: FontWeight.w700, color: AppColors.ink)),
            Text(upd == null ? 'Loading…' : 'updated ${_ago(upd)}', style: AppFonts.mono(size: 11, color: AppColors.ink4)),
          ]),
        ),
        _livePill(),
        IconButton(
          tooltip: _paused ? 'Resume live updates' : 'Pause live updates',
          icon: Icon(_paused ? Icons.play_arrow_rounded : Icons.pause_rounded, color: AppColors.ink3),
          onPressed: () => setState(() {
            _paused = !_paused;
            _pausedAtCount = _store.events.length;
          }),
        ),
      ]),
    );
  }

  Widget _staleBanner() {
    final upd = _store.updatedAt;
    return Container(
      color: AppColors.titanGoldSoft,
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 6, 8, 6),
      child: Row(children: [
        Icon(Icons.wifi_off_rounded, size: 16, color: AppColors.titanGold),
        const SizedBox(width: 8),
        Expanded(
          child: Text(upd == null ? 'Live updates disconnected' : 'Showing data from ${_ago(upd)}',
              style: AppFonts.sans(size: 12, weight: FontWeight.w600, color: AppColors.ink)),
        ),
        TextButton(onPressed: _retry, child: const Text('Retry')),
      ]),
    );
  }

  Widget _tabBody(bool wide) {
    final s = _store;
    final page = switch (_tab) {
      0 => _OverviewTab(store: s),
      1 => _LiveTab(store: s, frozenCount: _paused ? _pausedAtCount : null),
      2 => _UsersTab(store: s),
      3 => _ReactionsTab(store: s),
      4 => _DiscountsTab(store: s),
      5 => _EntityTable(key: const ValueKey('scr'), store: s, kind: _Kind.screens, wide: wide),
      6 => _EntityTable(key: const ValueKey('btn'), store: s, kind: _Kind.buttons, wide: wide),
      _ => _EntityTable(key: const ValueKey('sym'), store: s, kind: _Kind.symbols, wide: wide),
    };
    return RefreshIndicator(
      onRefresh: _refresh,
      child: Column(children: [
        if (_error != null) _errorCard(_error!, _refresh),
        Expanded(child: page),
      ]),
    );
  }
}

// ── Shared pieces ───────────────────────────────────────────────────────────

Widget _errorCard(String msg, Future<void> Function() retry) => Container(
      margin: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppColors.bearLight, borderRadius: BorderRadius.circular(AppRadius.lg)),
      child: Row(children: [
        Expanded(child: Text(msg, maxLines: 3, overflow: TextOverflow.ellipsis, style: AppFonts.sans(size: 12, color: AppColors.bear))),
        TextButton(onPressed: retry, child: const Text('Retry')),
      ]),
    );

Widget _card({required Widget child, EdgeInsets padding = const EdgeInsets.all(14)}) => Container(
      margin: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.md),
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.pureWhite,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.birch),
      ),
      child: child,
    );

Widget _label(String t) => Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.sm),
      child: Text(t.toUpperCase(), style: AppFonts.sans(size: 12, weight: FontWeight.w600, color: AppColors.ink3, spacing: 0.7)),
    );

Widget _chip(String t, {Color? bg, Color? fg, bool mono = true}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: bg ?? AppColors.cream, borderRadius: BorderRadius.circular(6)),
      child: Text(t,
          style: mono
              ? AppFonts.mono(size: 11, weight: FontWeight.w600, color: fg ?? AppColors.ink3)
              : AppFonts.sans(size: 11, weight: FontWeight.w600, color: fg ?? AppColors.ink3)),
    );

Widget _problemChip(String t) => _chip(t, bg: AppColors.bearLight, fg: AppColors.bear);

/// A tile; [tone] 'gold', 'bear' or 'bull' tints it when its value deserves attention.
Widget _tile(String label, String value, {String? tone}) {
  final (bg, fg) = switch (tone) {
    'bear' => (AppColors.bearLight, AppColors.bear),
    'gold' => (AppColors.titanGoldSoft, AppColors.titanGold),
    'bull' => (AppColors.bullLight, AppColors.bull),
    _ => (AppColors.pureWhite, AppColors.ink),
  };
  return Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(AppRadius.lg), border: Border.all(color: AppColors.birch)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label.toUpperCase(),
          maxLines: 2, overflow: TextOverflow.ellipsis, style: AppFonts.sans(size: 10, weight: FontWeight.w600, color: AppColors.ink3, spacing: 0.5)),
      const SizedBox(height: 6),
      Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppFonts.mono(size: 21, weight: FontWeight.w600, color: fg)),
    ]),
  );
}

Widget _tileGrid(List<Widget> tiles, {int cols = 2}) => Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, 0),
      child: LayoutBuilder(builder: (context, c) {
        final n = c.maxWidth > 700 ? cols + 2 : cols;
        final w = (c.maxWidth - (n - 1) * 8) / n;
        return Wrap(spacing: 8, runSpacing: 8, children: [for (final t in tiles) SizedBox(width: w, child: t)]);
      }),
    );

Widget _emptyCard(IconData icon, String title, String why) => _card(
      child: Column(children: [
        Icon(icon, color: AppColors.ink5, size: 28),
        const SizedBox(height: 6),
        Text(title, textAlign: TextAlign.center, style: AppText.bodyBold),
        const SizedBox(height: 2),
        Text(why, textAlign: TextAlign.center, style: AppFonts.sans(size: 12, color: AppColors.ink4)),
      ]),
    );

TextStyle get _headStyle => AppFonts.sans(size: 11, weight: FontWeight.w600, color: AppColors.ink3, spacing: 0.5);
TextStyle get _cellStyle => AppFonts.mono(size: 13, color: AppColors.ink);

/// Plain 3–4 column grid for short tables.
Widget _grid(List<String> head, List<List<String>> rows, {Set<int> problemRows = const {}}) => _card(
      padding: EdgeInsets.zero,
      child: Column(children: [
        Container(
          color: AppColors.cream,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(children: [
            Expanded(flex: 3, child: Text(head.first, style: _headStyle)),
            for (final h in head.skip(1)) Expanded(child: Text(h, textAlign: TextAlign.right, style: _headStyle)),
          ]),
        ),
        for (var i = 0; i < rows.length; i++)
          Container(
            decoration: BoxDecoration(border: Border(top: BorderSide(color: AppColors.cream))),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Row(children: [
              Expanded(
                flex: 3,
                child: Row(children: [
                  if (problemRows.contains(i))
                    Container(width: 6, height: 6, margin: const EdgeInsets.only(right: 6), decoration: BoxDecoration(color: AppColors.bear, shape: BoxShape.circle)),
                  Expanded(child: Text(rows[i].first, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppFonts.sans(size: 13, color: AppColors.ink))),
                ]),
              ),
              for (final c in rows[i].skip(1)) Expanded(child: Text(c, textAlign: TextAlign.right, style: _cellStyle)),
            ]),
          ),
      ]),
    );

Widget _bar(double frac, Color color, {double height = 8, Color? rest}) {
  final f = frac.isNaN ? 0.0 : frac.clamp(0.0, 1.0);
  return ClipRRect(
    borderRadius: BorderRadius.circular(4),
    child: SizedBox(
      height: height,
      child: Row(children: [
        if (f > 0) Expanded(flex: (f * 1000).round(), child: Container(color: color)),
        if (f < 1) Expanded(flex: ((1 - f) * 1000).round(), child: Container(color: rest ?? AppColors.cream)),
      ]),
    ),
  );
}

class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(AppSpacing.lg), children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (var i = 0; i < 6; i++)
            Container(width: 160, height: 70, decoration: BoxDecoration(color: AppColors.sand, borderRadius: BorderRadius.circular(AppRadius.lg))),
        ]),
        const SizedBox(height: 16),
        for (var i = 0; i < 3; i++)
          Container(height: 120, margin: const EdgeInsets.only(bottom: 12), decoration: BoxDecoration(color: AppColors.sand, borderRadius: BorderRadius.circular(AppRadius.lg))),
      ]);
}

bool _isErrorEvent(String n) => n.contains('error') || n.contains('crash') || n == 'rage_tap' || n == 'dead_tap' || n == 'quote_fail';

Widget _eventRow(Map<String, dynamic> e, {String? who}) {
  final name = '${e['name']}';
  final props = _props(e);
  return Container(
    decoration: BoxDecoration(color: AppColors.pureWhite, border: Border(bottom: BorderSide(color: AppColors.cream))),
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 9),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        if (who != null) ...[
          Flexible(child: Text(who, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppFonts.sans(size: 13, weight: FontWeight.w600, color: AppColors.ink))),
          const SizedBox(width: 6),
        ],
        Text(name, style: AppFonts.mono(size: 12, weight: FontWeight.w600, color: _isErrorEvent(name) ? AppColors.bear : AppColors.blue)),
        const Spacer(),
        Text(_ago(_ts(e)), style: AppFonts.mono(size: 11, color: AppColors.ink4)),
      ]),
      if (props.isNotEmpty) ...[
        const SizedBox(height: 4),
        Wrap(spacing: 4, runSpacing: 4, children: [for (final p in props.entries.take(6)) _chip('${p.key}=${p.value}')]),
      ],
    ]),
  );
}

/// Single-select filter chips.
Widget _chips(List<String> options, String selected, ValueChanged<String> onPick) => SizedBox(
      height: 40,
      child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg), children: [
        for (final o in options)
          Padding(
            padding: const EdgeInsets.only(right: 6, top: 4, bottom: 4),
            child: ChoiceChip(
              label: Text(o, style: AppFonts.sans(size: 12, weight: FontWeight.w600)),
              selected: o == selected,
              onSelected: (_) => onPick(o),
              visualDensity: VisualDensity.compact,
              showCheckmark: false,
            ),
          ),
      ]),
    );

Widget _search(String hint, ValueChanged<String> onChanged) => Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, 4),
      child: TextField(
        decoration: InputDecoration(prefixIcon: const Icon(Icons.search, size: 20), hintText: hint, isDense: true),
        onChanged: (v) => onChanged(v.trim().toLowerCase()),
      ),
    );

// ── Overview ────────────────────────────────────────────────────────────────

class _OverviewTab extends StatefulWidget {
  const _OverviewTab({required this.store});
  final _Store store;

  @override
  State<_OverviewTab> createState() => _OverviewTabState();
}

class _OverviewTabState extends State<_OverviewTab> {
  bool _allEvents = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.store;
    final o = s.overview;
    String v(String k) => o == null ? '–' : '${o[k] ?? 0}';
    final crashed = s.usersWith('hw_crashed_since_last_open_current');
    final slow = s.usersWith('hw_cold_start_slow_over_4000ms_current');
    final perMin = (o?['events_per_minute_60m'] as List?) ?? const [];
    final peak = perMin.fold<num>(0, (a, e) => math.max(a, _num((e as List)[1])));
    final byName = ((o?['events_by_name_24h'] as Map?) ?? const {}).entries.toList()..sort((a, b) => _num(b.value).compareTo(_num(a.value)));
    final pv = s.sum('x_paywall_pack_view_30d'), cs = s.sum('x_paywall_checkout_start_30d');
    final ps = s.sum('x_paywall_purchase_success_30d'), pf = s.sum('x_paywall_purchase_failed_30d');
    final payments = [for (final p in (o?['payments_recent'] as List?) ?? const []) if (p is Map) Map<String, dynamic>.from(p)];
    final launches = {for (final src in kLaunchSources) src: kLaunchWindows.fold<num>(0, (a, w) => a + s.sum('launch_${src}_$w'))};
    final launchTotal = launches.values.fold<num>(0, (a, b) => a + b);

    return ListView(padding: const EdgeInsets.only(bottom: AppSpacing.xxl), children: [
      _tileGrid([
        _tile('Active 5m', v('users_active_5m')),
        _tile('Active 24h', v('users_active_24h')),
        _tile('Users scored', '${s.states.length}'),
        _tile('Events 1h', v('events_1h')),
        _tile('Events 24h', v('events_24h')),
        _tile('Reactions sent 24h', v('reactions_delivered_24h')),
        _tile('Suppressed 24h', v('reactions_suppressed_24h')),
        _tile('Crash credits 7d', v('apologies_7d'), tone: _num(o?['apologies_7d']) > 0 ? 'gold' : null),
        _tile('Crashed since open', '$crashed', tone: crashed > 0 ? 'bear' : null),
        _tile('Slow cold starts', '$slow', tone: slow > 0 ? 'gold' : null),
      ]),
      _label('Events per minute · last 60 min'),
      _card(
        child: perMin.isEmpty
            ? Text('No events in the last hour', style: AppText.bodySmall)
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('peak ${_fmt(peak)}/min', style: AppFonts.mono(size: 11, color: AppColors.ink4)),
                const SizedBox(height: 6),
                SizedBox(
                  height: 64,
                  child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    for (var i = 0; i < perMin.length; i++)
                      Expanded(
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 0.5),
                          height: math.max(2, 64 * _num((perMin[i] as List)[1]) / math.max(1, peak)).toDouble(),
                          color: i == perMin.length - 1 ? AppColors.bull : AppColors.blue.withValues(alpha: 0.55),
                        ),
                      ),
                  ]),
                ),
              ]),
      ),
      _label('Payments · Razorpay'),
      _tileGrid([
        _tile('Paid 24h', v('payments_paid_24h'), tone: _num(o?['payments_paid_24h']) > 0 ? 'bull' : null),
        _tile('Paid 30d', v('payments_paid_30d')),
        _tile('Revenue 30d', o == null ? '–' : _inr(_num(o['payments_revenue_paise_30d']))),
        _tile('Checkouts 30d', v('payments_checkouts_30d')),
      ]),
      _card(
        child: payments.isEmpty
            ? Text(o == null ? 'Loading payments…' : 'No paid orders yet', style: AppText.bodySmall)
            : Column(children: [
                for (final p in payments.take(10))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${p['name'] ?? s.nameOf(p['user_id'] as String?)}',
                              maxLines: 1, overflow: TextOverflow.ellipsis, style: AppFonts.sans(size: 13, color: AppColors.ink)),
                          Text(
                            '${s.plans['${p['sku']}']?['title'] ?? p['sku']}'
                            '${p['credited'] == true || p['kind'] != 'one_time' ? '' : ' · not credited'}',
                            style: AppFonts.mono(size: 11, color: p['credited'] == true || p['kind'] != 'one_time' ? AppColors.ink4 : AppColors.bear),
                          ),
                        ]),
                      ),
                      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Text(_inr(_num(p['amount_paise'])), style: _cellStyle),
                        if (DateTime.tryParse('${p['at']}') case final at?)
                          Text(_ago(at.toLocal()), style: AppFonts.mono(size: 11, color: AppColors.ink4)),
                      ]),
                    ]),
                  ),
              ]),
      ),
      _label('Paywall funnel · 30d · app telemetry'),
      _card(
        child: Column(children: [
          for (final (label, count, color) in [
            ('Pack viewed', pv, AppColors.blue),
            ('Checkout started', cs, AppColors.blue),
            ('Purchase succeeded', ps, AppColors.bull),
            ('Purchase failed', pf, AppColors.bear),
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text(label, style: AppFonts.sans(size: 13, color: AppColors.ink)),
                  const Spacer(),
                  Text('${_fmt(count)}  ${pv == 0 ? '–' : '${(count / pv * 100).round()}%'}', style: _cellStyle),
                ]),
                const SizedBox(height: 4),
                _bar(pv == 0 ? 0 : (count / pv).toDouble(), color),
              ]),
            ),
        ]),
      ),
      _label('Account & paywall drop-offs'),
      _grid(['EVENT', 'TODAY', '7D', '30D'], [
        for (final b in kFunnelBases)
          [
            b.replaceAll('_', ' '),
            _fmt(s.sum('mon_${b}_today_ist')),
            _fmt(s.sum('mon_${b}_rolling_7d_window')),
            _fmt(s.sum('mon_${b}_rolling_30d_window')),
          ],
      ]),
      _label('App health'),
      _grid([
        'FLAG',
        'USERS',
        'AVERAGE'
      ], [
        for (final k in kHealthMetrics)
          [
            k.replaceAll('_', ' '),
            '${s.usersWith('hw_${k}_current')}',
            s.usersWith('hw_${k}_current') == 0 ? '–' : _fmt(s.avgOfUsers('hw_${k}_current')),
          ],
      ], problemRows: {
        for (var i = 0; i < kHealthMetrics.length; i++)
          if (kHealthMetrics[i].contains('crash') && s.usersWith('hw_${kHealthMetrics[i]}_current') > 0) i,
      }),
      _label('Launches by source · 30d'),
      _card(
        child: launchTotal == 0
            ? Text('No launches recorded yet', style: AppText.bodySmall)
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _bar((launches['icon']! / launchTotal).toDouble(), AppColors.blue, height: 12, rest: AppColors.violet),
                const SizedBox(height: 8),
                Row(children: [
                  _chip('icon ${_fmt(launches['icon']!)}', bg: AppColors.blueLight, fg: AppColors.blue),
                  const SizedBox(width: 6),
                  _chip('notification ${_fmt(launches['notification']!)}', bg: AppColors.violetLight, fg: AppColors.violet),
                ]),
              ]),
      ),
      _label('Top events · 24h'),
      _card(
        child: byName.isEmpty
            ? Text('No events yet', style: AppText.bodySmall)
            : Column(children: [
                for (final e in byName.take(_allEvents ? 40 : 8))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(children: [
                      SizedBox(width: 130, child: Text('${e.key}', overflow: TextOverflow.ellipsis, style: AppFonts.mono(size: 12, color: AppColors.ink))),
                      Expanded(child: _bar(_num(e.value) / math.max(1, _num(byName.first.value)), AppColors.blue, height: 6)),
                      SizedBox(width: 50, child: Text('${e.value}', textAlign: TextAlign.right, style: _cellStyle)),
                    ]),
                  ),
                if (byName.length > 8)
                  TextButton(onPressed: () => setState(() => _allEvents = !_allEvents), child: Text(_allEvents ? 'Show fewer' : 'Show all')),
              ]),
      ),
    ]);
  }
}

// ── Live ────────────────────────────────────────────────────────────────────

class _LiveTab extends StatefulWidget {
  const _LiveTab({required this.store, this.frozenCount});
  final _Store store;
  final int? frozenCount; // set while paused: the list stops growing

  @override
  State<_LiveTab> createState() => _LiveTabState();
}

class _LiveTabState extends State<_LiveTab> {
  String _q = '', _filter = 'All';

  bool _match(Map<String, dynamic> e) {
    final n = '${e['name']}';
    final ok = switch (_filter) {
      'Errors' => _isErrorEvent(n),
      'Paywall' => n == 'paywall_step',
      'Orders' => n.startsWith('trade_') || n == 'margin_shortfall',
      'Reactions' => n == 'reaction',
      _ => true,
    };
    if (!ok) return false;
    if (_q.isEmpty) return true;
    return '${widget.store.nameOf(e['user_id'] as String?)} $n ${_props(e)}'.toLowerCase().contains(_q);
  }

  @override
  Widget build(BuildContext context) {
    final all = widget.store.events; // newest first
    final frozen = widget.frozenCount;
    final src = frozen == null ? all : all.sublist(math.max(0, all.length - frozen));
    final ev = src.where(_match).take(500).toList();
    return Column(children: [
      _search('Search user, event or value', (v) => setState(() => _q = v)),
      _chips(const ['All', 'Errors', 'Paywall', 'Orders', 'Reactions'], _filter, (v) => setState(() => _filter = v)),
      if (frozen != null && all.length > frozen)
        Padding(padding: const EdgeInsets.only(bottom: 4), child: _chip('↑ ${all.length - frozen} new events · paused', bg: AppColors.blueLight, fg: AppColors.blue)),
      Expanded(
        child: ev.isEmpty
            ? ListView(children: [
                _emptyCard(Icons.bolt_outlined, _q.isEmpty ? 'No events yet' : 'No events match "$_q"',
                    'Events appear here within a minute of users opening the new build.'),
              ])
            : ListView.builder(
                itemCount: ev.length,
                itemBuilder: (_, i) => _eventRow(ev[i], who: widget.store.nameOf(ev[i]['user_id'] as String?)),
              ),
      ),
    ]);
  }
}

// ── Users ───────────────────────────────────────────────────────────────────

class _UsersTab extends StatefulWidget {
  const _UsersTab({required this.store});
  final _Store store;

  @override
  State<_UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends State<_UsersTab> {
  String _q = '', _sort = 'Online first';

  @override
  Widget build(BuildContext context) {
    final s = widget.store;
    final latest = <String, DateTime>{};
    final counts = <String, int>{};
    for (final e in s.events) {
      final u = e['user_id'] as String?;
      if (u == null) continue;
      latest.putIfAbsent(u, () => _ts(e));
      counts[u] = (counts[u] ?? 0) + 1;
    }
    for (final u in s.states.keys) {
      final t = _ts(s.states[u]!);
      if (t.isAfter(latest[u] ?? DateTime(0))) latest[u] = t;
    }
    bool online(String u) => DateTime.now().difference(latest[u]!).inMinutes < 5;
    num streak(String u) => s.metricsOf(u)['hw_login_streak_current_days_current'] ?? 0;
    final users = latest.keys.where((u) => _q.isEmpty || s.nameOf(u).toLowerCase().contains(_q) || u.contains(_q)).toList()
      ..sort((a, b) => switch (_sort) {
            'Most events' => (counts[b] ?? 0).compareTo(counts[a] ?? 0),
            'Longest streak' => streak(b).compareTo(streak(a)),
            'Last seen' => latest[b]!.compareTo(latest[a]!),
            _ => online(a) == online(b) ? latest[b]!.compareTo(latest[a]!) : (online(a) ? -1 : 1),
          });
    final onlineN = latest.keys.where(online).length;
    return Column(children: [
      _search('Search users by name or id', (v) => setState(() => _q = v)),
      _chips(const ['Online first', 'Most events', 'Longest streak', 'Last seen'], _sort, (v) => setState(() => _sort = v)),
      Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, 6),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text('${latest.length} users · $onlineN online · ${s.states.length} scored', style: AppFonts.mono(size: 11, color: AppColors.ink4)),
        ),
      ),
      Expanded(
        child: users.isEmpty
            ? ListView(children: [_emptyCard(Icons.people_outline, _q.isEmpty ? 'No users yet' : 'No users match "$_q"', 'Users appear once they open a build with analytics.')])
            : ListView.builder(
                itemCount: users.length,
                itemBuilder: (context, i) {
                  final u = users[i];
                  final on = online(u);
                  final name = s.nameOf(u);
                  return _card(
                    padding: EdgeInsets.zero,
                    child: ListTile(
                      leading: Stack(clipBehavior: Clip.none, children: [
                        CircleAvatar(radius: 16, backgroundColor: AppColors.cream, child: Text(name.isEmpty ? '?' : name.characters.first.toUpperCase(), style: AppText.bodyBold)),
                        if (on)
                          Positioned(
                            right: -1,
                            bottom: -1,
                            child: Container(width: 10, height: 10, decoration: BoxDecoration(color: AppColors.bull, shape: BoxShape.circle, border: Border.all(color: AppColors.pureWhite, width: 2))),
                          ),
                      ]),
                      title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppFonts.sans(size: 14, weight: FontWeight.w600, color: AppColors.ink)),
                      subtitle: Text('${counts[u] ?? 0} ev · ${s.metricsOf(u).length} metrics · streak ${_fmt(streak(u))}d', style: AppFonts.mono(size: 11, color: AppColors.ink4)),
                      trailing: Text(on ? 'online' : _ago(latest[u]!), style: AppFonts.mono(size: 11, color: on ? AppColors.bull : AppColors.ink4)),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => _UserDetail(store: s, userId: u))),
                    ),
                  );
                },
              ),
      ),
    ]);
  }
}

class _UserDetail extends StatefulWidget {
  const _UserDetail({required this.store, required this.userId});
  final _Store store;
  final String userId;

  @override
  State<_UserDetail> createState() => _UserDetailState();
}

class _UserDetailState extends State<_UserDetail> {
  String _q = '', _group = 'All';
  int _seg = 0;

  static const _sections = {
    'launch_': 'Launches', 'hw_': 'App health', 'scr_': 'Screens', 'btn_': 'Buttons', 'sym_': 'Symbols', 'mon_': 'Funnel', 'x_': 'Other',
  };

  String _sectionOf(String k) => _sections.entries.firstWhere((e) => k.startsWith(e.key), orElse: () => const MapEntry('', 'Other')).value;

  @override
  Widget build(BuildContext context) {
    final s = widget.store;
    return Scaffold(
      backgroundColor: AppColors.parchment,
      appBar: AppBar(
        backgroundColor: AppColors.pureWhite,
        foregroundColor: AppColors.ink,
        elevation: 0,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(s.nameOf(widget.userId), style: AppFonts.sans(size: 16, weight: FontWeight.w700, color: AppColors.ink)),
          Text(widget.userId, style: AppFonts.mono(size: 10, color: AppColors.ink4)),
        ]),
      ),
      body: ListenableBuilder(
        listenable: s,
        builder: (_, _) {
          final m = s.metricsOf(widget.userId);
          final ev = s.events.where((e) => e['user_id'] == widget.userId).toList();
          final fi = s.firings.where((e) => e['user_id'] == widget.userId).toList();
          final upd = s.states[widget.userId];
          return Column(children: [
            _tileGrid([
              _tile('Events 24h', '${ev.length}'),
              _tile('Metrics', '${m.length}'),
              _tile('Streak', '${_fmt(m['hw_login_streak_current_days_current'] ?? 0)}d'),
              _tile('Updated', upd == null ? '–' : _ago(_ts(upd))),
            ], cols: 4),
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, 4),
              child: SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 0, label: Text('Metrics')),
                  ButtonSegment(value: 1, label: Text('Events')),
                  ButtonSegment(value: 2, label: Text('Reactions')),
                ],
                selected: {_seg},
                onSelectionChanged: (v) => setState(() => _seg = v.first),
                showSelectedIcon: false,
              ),
            ),
            Expanded(
              child: switch (_seg) {
                0 => _metrics(m, upd == null),
                1 => ev.isEmpty
                    ? ListView(children: [_emptyCard(Icons.bolt_outlined, 'No events in the last 24h', 'This user has not opened the app today.')])
                    : ListView.builder(itemCount: ev.length, itemBuilder: (_, i) => _eventRow(ev[i])),
                _ => fi.isEmpty
                    ? ListView(children: [_emptyCard(Icons.campaign_outlined, 'No reactions in 7 days', 'Nothing has been shown to or held back from this user.')])
                    : ListView.builder(itemCount: fi.length, itemBuilder: (_, i) => _firingRow(fi[i])),
              },
            ),
          ]);
        },
      ),
    );
  }

  Widget _metrics(Map<String, num> m, bool none) {
    if (none) {
      return ListView(children: [_emptyCard(Icons.insights_outlined, 'No computed metrics yet', 'The app uploads metrics every 5 minutes and when it goes to the background.')]);
    }
    final grouped = <String, List<String>>{};
    for (final k in m.keys.toList()..sort()) {
      if (_q.isNotEmpty && !k.contains(_q)) continue;
      (grouped[_sectionOf(k)] ??= []).add(k);
    }
    final total = grouped.values.fold<int>(0, (a, l) => a + l.length);
    final names = _sections.values.toSet().toList();
    return ListView(children: [
      _search('Search ${m.length} metrics', (v) => setState(() => _q = v)),
      _chips(['All', for (final g in names) '$g ${grouped[g]?.length ?? 0}'], _group == 'All' ? 'All' : '$_group ${grouped[_group]?.length ?? 0}',
          (v) => setState(() => _group = v == 'All' ? 'All' : v.substring(0, v.lastIndexOf(' ')))),
      if (total == 0)
        Column(children: [
          _emptyCard(Icons.search_off_rounded, 'No metrics match "$_q"', 'Try a symbol, screen or button name.'),
        ]),
      for (final g in names)
        if (grouped[g] != null && (_group == 'All' || _group == g))
          _card(
            padding: EdgeInsets.zero,
            child: ExpansionTile(
              key: PageStorageKey('grp_$g$_q$_group'),
              initiallyExpanded: grouped[g]!.length <= 30 || _q.isNotEmpty || _group == g,
              shape: const Border(),
              title: Text('$g · ${grouped[g]!.length}', style: AppText.bodyBold),
              children: [
                for (final k in grouped[g]!)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                    child: Row(children: [
                      Expanded(child: Text(k, style: AppFonts.mono(size: 11, color: AppColors.ink3))),
                      _isProblemMetric(k, m[k]!)
                          ? _problemChip(_fmt(m[k]!))
                          : Text(_fmt(m[k]!), style: AppFonts.mono(size: 12, weight: FontWeight.w600, color: AppColors.ink)),
                    ]),
                  ),
              ],
            ),
          ),
      const SizedBox(height: AppSpacing.xxl),
    ]);
  }
}

// ── Reactions ───────────────────────────────────────────────────────────────

const _reactionGroups = {
  'Trade coaching': ['two_loss_recap', 'win_streak_scaled', 'textbook_win', 'quick_win', 'sold_too_early', 'profitable_week', 'streak_broken'],
  'Education': ['option_chain_helper', 'stop_loss_tip', 'analytics_leak_tip', 'league_near_miss', 'market_closed_note'],
  'Account & support': ['guest_save_account', 'crash_apology', 'zero_result_search_help', 'delete_account_support_offer', 'margin_topup_offer'],
  'Offers': ['offer_stage1', 'offer_stage2', 'offer_redeemed'],
  'Product flags': ['rage_button_flag', 'dead_button_flag', 'power_button_flag'],
  'Win-back': ['winback_3d', 'winback_7d'],
};

Widget _firingRow(Map<String, dynamic> f, {String? who}) {
  final delivered = f['delivered'] == true;
  final props = _props(f);
  return Container(
    decoration: BoxDecoration(color: AppColors.pureWhite, border: Border(bottom: BorderSide(color: AppColors.cream))),
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 9),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        if (who != null) ...[
          Flexible(child: Text(who, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppFonts.sans(size: 13, weight: FontWeight.w600, color: AppColors.ink))),
          const SizedBox(width: 6),
        ],
        Text('${f['reaction']}', style: AppFonts.mono(size: 12, weight: FontWeight.w600, color: AppColors.ink)),
        const Spacer(),
        Text(_ago(_ts(f)), style: AppFonts.mono(size: 11, color: AppColors.ink4)),
      ]),
      const SizedBox(height: 4),
      Wrap(spacing: 4, runSpacing: 4, children: [
        delivered
            ? _chip('delivered · ${f['reason']}', bg: AppColors.bullLight, fg: AppColors.bull)
            : _chip('suppressed · ${f['reason']}', bg: AppColors.titanGoldSoft, fg: AppColors.titanGold),
        for (final p in props.entries.take(4)) _chip('${p.key}=${p.value}'),
      ]),
    ]),
  );
}

class _ReactionsTab extends StatefulWidget {
  const _ReactionsTab({required this.store});
  final _Store store;

  @override
  State<_ReactionsTab> createState() => _ReactionsTabState();
}

class _ReactionsTabState extends State<_ReactionsTab> {
  String _filter = 'All';

  @override
  Widget build(BuildContext context) {
    final s = widget.store;
    final f = s.firings;
    if (f.isEmpty) {
      return ListView(children: [_emptyCard(Icons.campaign_outlined, 'No reactions in the last 7 days', 'Reactions are logged when the app shows or holds back a message.')]);
    }
    final counts = <String, (int, int)>{};
    final reasons = <String, int>{};
    for (final r in f) {
      final k = '${r['reaction']}';
      final (d, sup) = counts[k] ?? (0, 0);
      counts[k] = r['delivered'] == true ? (d + 1, sup) : (d, sup + 1);
      if (r['delivered'] != true) reasons['${r['reason']}'] = (reasons['${r['reason']}'] ?? 0) + 1;
    }
    final delivered = counts.values.fold<int>(0, (a, c) => a + c.$1);
    final suppressed = counts.values.fold<int>(0, (a, c) => a + c.$2);
    final known = _reactionGroups.values.expand((l) => l).toSet();
    final groups = {..._reactionGroups, 'Other': [for (final k in counts.keys) if (!known.contains(k)) k]};
    final education = _reactionGroups['Education']!.toSet();
    final latest = f
        .where((r) => switch (_filter) {
              'Delivered' => r['delivered'] == true,
              'Suppressed' => r['delivered'] != true,
              'Education' => education.contains(r['reaction']),
              _ => true,
            })
        .take(300)
        .toList();

    return ListView(padding: const EdgeInsets.only(bottom: AppSpacing.xxl), children: [
      _tileGrid([
        _tile('Delivered 7d', '$delivered', tone: 'bull'),
        _tile('Suppressed 7d', '$suppressed', tone: suppressed > 0 ? 'gold' : null),
        _tile('Held back', '${(suppressed * 100 / math.max(1, delivered + suppressed)).round()}%'),
      ], cols: 3),
      _label('By reaction type'),
      for (final g in groups.entries)
        if (g.value.any(counts.containsKey))
          _card(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(g.key, style: AppText.bodyBold),
                if (g.key == 'Education') ...[const SizedBox(width: 6), _chip('NEW · no upsell', bg: AppColors.violetLight, fg: AppColors.violet, mono: false)],
              ]),
              const SizedBox(height: 8),
              for (final k in g.value)
                if (counts[k] != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(child: Text(k, style: AppFonts.mono(size: 12, color: AppColors.ink))),
                        Text('D ${counts[k]!.$1} · S ${counts[k]!.$2}', style: AppFonts.mono(size: 11, color: AppColors.ink4)),
                      ]),
                      const SizedBox(height: 3),
                      _bar(counts[k]!.$1 / math.max(1, counts[k]!.$1 + counts[k]!.$2), AppColors.blue, rest: counts[k]!.$2 > 0 ? AppColors.titanGold : AppColors.cream),
                    ]),
                  ),
            ]),
          ),
      if (reasons.isNotEmpty) ...[
        _label('Why suppressed'),
        _grid(['REASON', 'COUNT'], [for (final e in reasons.entries) [e.key.replaceAll('_', ' '), '${e.value}']]),
      ],
      _label('Latest firings'),
      _chips(const ['All', 'Delivered', 'Suppressed', 'Education'], _filter, (v) => setState(() => _filter = v)),
      for (final r in latest) _firingRow(r, who: s.nameOf(r['user_id'] as String?)),
    ]);
  }
}

// ── Discounts ───────────────────────────────────────────────────────────────

class _DiscountsTab extends StatelessWidget {
  const _DiscountsTab({required this.store});
  final _Store store;

  @override
  Widget build(BuildContext context) {
    final s = store;
    final o = s.offers;
    final grants = s.grants.values.toList();
    final now = DateTime.now();
    DateTime? at(Map<String, dynamic> g, String k) => DateTime.tryParse('${g[k] ?? ''}')?.toLocal();
    bool redeemedInS1(Map<String, dynamic> g) => at(g, 'redeemed_at') != null && at(g, 'redeemed_at')!.isBefore(at(g, 'stage2_at') ?? now);
    final active = grants.where((g) => _grantPct(g) > 0).toList()..sort((a, b) => '${a['expires_at']}'.compareTo('${b['expires_at']}'));
    final s1Redeemed = grants.where(redeemedInS1).length;
    final reachedS2 = grants.where((g) => (at(g, 'stage2_at')?.isBefore(now) ?? false) && !redeemedInS1(g)).length;
    final s2Redeemed = grants.where((g) => at(g, 'redeemed_at') != null && !redeemedInS1(g)).length;
    final suppressed = ((o?['suppressed_30d'] as Map?) ?? const {}).entries.toList();

    Widget stage(String label, int redeemed, int of) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(label, style: AppFonts.sans(size: 13, weight: FontWeight.w600, color: AppColors.ink)),
              const Spacer(),
              Text('$redeemed / $of · ${of == 0 ? '–' : '${(redeemed * 100 / of).round()}%'}', style: _cellStyle),
            ]),
            const SizedBox(height: 4),
            _bar(of == 0 ? 0 : redeemed / of, AppColors.bull, rest: AppColors.sand),
          ]),
        );

    return ListView(padding: const EdgeInsets.only(bottom: AppSpacing.xxl), children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, 0),
        child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 6, runSpacing: 6, children: [
          _chip('Step-down, no buy', mono: false),
          Icon(Icons.arrow_forward, size: 14, color: AppColors.ink4),
          _chip('Stage 1 · 50% · 48h', bg: AppColors.blueLight, fg: AppColors.blue, mono: false),
          Icon(Icons.arrow_forward, size: 14, color: AppColors.ink4),
          _chip('Stage 2 · 75% · 48h', bg: AppColors.violetLight, fg: AppColors.violet, mono: false),
          Icon(Icons.arrow_forward, size: 14, color: AppColors.ink4),
          _chip('Expires', mono: false),
        ]),
      ),
      _tileGrid([
        _tile('Active now', '${active.length}', tone: active.isNotEmpty ? 'bull' : null),
        _tile('Issued 30d', '${o?['issued_30d'] ?? grants.length}'),
        _tile('Redeemed 30d', '${o?['redeemed_30d'] ?? '–'}', tone: _num(o?['redeemed_30d']) > 0 ? 'bull' : null),
        _tile('Expired 30d', '${o?['expired_30d'] ?? '–'}'),
        _tile('Suppressed 30d', _fmt(suppressed.fold<num>(0, (a, e) => a + _num(e.value)))),
        _tile('Revenue 30d', o == null ? '–' : _inr(_num(o['revenue_paise_30d'])), tone: _num(o?['revenue_paise_30d']) > 0 ? 'bull' : null),
      ], cols: 3),
      _label('Conversion by stage'),
      _card(
        child: Column(children: [
          stage('Stage 1 · 50% off', s1Redeemed, grants.length),
          stage('Stage 2 · 75% off', s2Redeemed, reachedS2),
        ]),
      ),
      _label('Active grants · soonest expiry first'),
      if (active.isEmpty)
        _emptyCard(Icons.sell_outlined, 'No active offers', 'An offer starts when a first-time buyer steps down from a bigger pack to a cheaper one.')
      else
        _card(
          padding: EdgeInsets.zero,
          child: Column(children: [
            for (final g in active) _grantRow(s, g, at(g, 'expires_at') ?? now, now),
          ]),
        ),
      _label('Suppressed grants · 30d'),
      suppressed.isEmpty
          ? _emptyCard(Icons.block, 'None held back', 'Offers are held back for guests, existing customers, a re-entry within 120s of a loss, or under ₹1,000 left.')
          : _grid(['REASON', 'COUNT'], [for (final e in suppressed) ['${e.key}'.replaceAll('_', ' '), '${e.value}']]),
    ]);
  }

  Widget _grantRow(_Store s, Map<String, dynamic> g, DateTime exp, DateTime now) {
    final pct = _grantPct(g);
    final plan = s.plans['${g['sku']}'];
    final list = _num(plan?['price_paise']);
    final soon = exp.difference(now).inHours < 12;
    return Container(
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.cream))),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s.nameOf(g['user_id'] as String?), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppFonts.sans(size: 13, weight: FontWeight.w600, color: AppColors.ink)),
            const SizedBox(height: 3),
            Row(children: [
              pct == 75 ? _chip('S2 · 75%', bg: AppColors.violetLight, fg: AppColors.violet) : _chip('S1 · 50%', bg: AppColors.blueLight, fg: AppColors.blue),
              const SizedBox(width: 6),
              Flexible(child: Text('${plan?['title'] ?? g['sku']} ', overflow: TextOverflow.ellipsis, style: AppFonts.sans(size: 12, color: AppColors.ink3))),
              if (list > 0) ...[
                Text(_inr(list), style: AppFonts.mono(size: 11, color: AppColors.ink4).copyWith(decoration: TextDecoration.lineThrough)),
                const SizedBox(width: 4),
                Text(_inr((list * (100 - pct) / 100).round()), style: AppFonts.mono(size: 12, weight: FontWeight.w700, color: AppColors.ink)),
              ],
            ]),
          ]),
        ),
        Text(_left(exp), style: AppFonts.mono(size: 12, weight: FontWeight.w600, color: soon ? AppColors.bear : AppColors.ink3)),
      ]),
    );
  }
}

// ── Screens / Buttons / Symbols ─────────────────────────────────────────────

enum _Kind { screens, buttons, symbols }

class _Col {
  final String label;
  final num Function(String id) value;
  final String Function(num v) format;
  final bool Function(num v)? problem;
  final Color Function(num v)? tone;
  const _Col(this.label, this.value, {this.format = _fmt, this.problem, this.tone});
}

class _EntityTable extends StatefulWidget {
  const _EntityTable({super.key, required this.store, required this.kind, required this.wide});
  final _Store store;
  final _Kind kind;
  final bool wide;

  @override
  State<_EntityTable> createState() => _EntityTableState();
}

class _EntityTableState extends State<_EntityTable> {
  String _q = '';
  int _sortCol = 1;
  bool _desc = true;
  late bool _problemsOnTop = widget.kind == _Kind.buttons;
  String? _selected;
  final _hScroll = ScrollController();

  @override
  void dispose() {
    _hScroll.dispose();
    super.dispose();
  }

  String get _prefix => switch (widget.kind) { _Kind.screens => 'scr_', _Kind.buttons => 'btn_', _Kind.symbols => 'sym_' };
  String get _noun => switch (widget.kind) { _Kind.screens => 'screens', _Kind.buttons => 'buttons', _Kind.symbols => 'symbols' };

  List<_Col> _cols(_Store s) {
    final p = _prefix;
    num m(String id, String k) => s.sum('$p${id}_$k');
    switch (widget.kind) {
      case _Kind.screens:
        final live = s.liveCount('screen_view', 'screen');
        return [
          _Col('24H LIVE', (x) => live[x] ?? 0),
          _Col('OPENS 7D', (x) => m(x, 'opens_7d')),
          _Col('AVG DWELL', (x) => s.avgOfUsers('$p${x}_avg_dwell_sec_per_visit'), format: (v) => '${v.toStringAsFixed(1)}s'),
          _Col('ERRORS', (x) => m(x, 'error_state_views'), problem: (v) => v > 0),
          _Col('DEAD TAPS', (x) => m(x, 'dead_tap_non_clickable'), problem: (v) => v >= 3),
          _Col('RAGE', (x) => m(x, 'rage_tap_bursts'), problem: (v) => v > 0),
          _Col('EXITS', (x) => m(x, 'session_exit_drop_off')),
        ];
      case _Kind.buttons:
        final live = s.liveCount('tap', 'button');
        return [
          _Col('24H LIVE', (b) => live[b] ?? 0),
          _Col('TAPS 7D', (b) => m(b, 'clicks_7d')),
          _Col('CTR 7D', (b) => s.states.isEmpty ? 0 : m(b, 'ctr_pct_7d') / s.states.length, format: (v) => '${v.toStringAsFixed(1)}%'),
          _Col('DEAD FOR', (b) => s.usersWith('$p${b}_zero_click_dead_button_flag'), problem: (v) => v > 0),
          _Col('RAGE', (b) => m(b, 'rage_double_taps'), problem: (v) => v > 0),
          _Col('ERR', (b) => m(b, 'error_after_click'), problem: (v) => v > 0),
          _Col('POWER', (b) => s.states.keys.where((u) => (s.metricsOf(u)['$p${b}_clicks_7d'] ?? 0) >= 5).length,
              tone: (v) => v > 0 ? AppColors.bull : AppColors.ink),
        ];
      case _Kind.symbols:
        num trades(String x) => m(x, 'trades_won_7d') + m(x, 'trades_lost_7d');
        return [
          _Col('VIEWS 7D', (x) => m(x, 'chart_views_7d')),
          _Col('WIN %', (x) => trades(x) == 0 ? -1 : m(x, 'trades_won_7d') / trades(x) * 100, format: (v) => v < 0 ? '–' : '${v.round()}%'),
          _Col('TRADES 7D', trades),
          _Col('P&L 30D', (x) => m(x, 'net_realized_pnl_inr'),
              format: (v) => '${v >= 0 ? '+' : '−'}₹${_fmt(v.abs())}', tone: (v) => v > 0 ? AppColors.bull : v < 0 ? AppColors.bear : AppColors.ink),
          _Col('SHORT', (x) => m(x, 'margin_shortfall_rejections'), problem: (v) => v >= 3),
          _Col('RE-ENTRY <2M', (x) => m(x, 'revenge_trade_under_120s'), problem: (v) => v >= 2),
          _Col('HOLD', (x) => s.avgOfUsers('$p${x}_avg_hold_time_minutes'), format: (v) => v == 0 ? '–' : '${v.round()}m'),
        ];
    }
  }

  List<String> _ids(_Store s) => switch (widget.kind) {
        _Kind.screens => {...s.entities('scr_', '_opens_7d'), ...s.liveCount('screen_view', 'screen').keys}.toList(),
        _Kind.buttons => {..._buttonsIn(s), ...s.liveCount('tap', 'button').keys}.toList(),
        _Kind.symbols => {
            for (final suf in ['_chart_views_7d', '_trades_won_7d', '_trades_lost_7d', '_net_realized_pnl_inr', '_margin_shortfall_rejections'])
              ...s.entities('sym_', suf),
          }.toList(),
      };

  bool _isProblem(_Store s, String id) => switch (widget.kind) {
        _Kind.screens => _screenProblem(s, id),
        _Kind.buttons => _buttonProblem(s, id),
        _Kind.symbols => _symbolProblem(s, id),
      };

  String _tagOf(_Store s, String id) {
    if (widget.kind != _Kind.buttons) return '';
    if (s.sum('btn_${id}_rage_double_taps') > 0) return 'RAGE';
    if (s.usersWith('btn_${id}_zero_click_dead_button_flag') > 0) return 'DEAD';
    if (s.sum('btn_${id}_error_after_click') > 0) return 'ERROR';
    return '';
  }

  void _open(String id) {
    if (widget.wide) {
      setState(() => _selected = id);
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Scaffold(
        backgroundColor: AppColors.parchment,
        appBar: AppBar(backgroundColor: AppColors.pureWhite, foregroundColor: AppColors.ink, elevation: 0, title: Text(id, style: AppFonts.mono(size: 15, weight: FontWeight.w600))),
        body: _EntityDetail(store: widget.store, id: id, prefix: '$_prefix${id}_', kind: widget.kind),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.store;
    final cols = _cols(s);
    final sortIdx = (_sortCol - 1).clamp(0, cols.length - 1);
    final ids = _ids(s).where((id) => _q.isEmpty || id.contains(_q)).toList();
    final values = {for (final id in ids) id: [for (final c in cols) c.value(id)]};
    ids.sort((a, b) => _desc ? values[b]![sortIdx].compareTo(values[a]![sortIdx]) : values[a]![sortIdx].compareTo(values[b]![sortIdx]));
    final problems = ids.where((id) => _isProblem(s, id)).toList();
    final healthy = ids.where((id) => !_isProblem(s, id)).toList();
    final ordered = _problemsOnTop ? [...problems, ...healthy] : ids;
    const firstW = 150.0, colW = 92.0, rowH = 44.0;

    Widget headerCell(String t, int i) => InkWell(
          onTap: () => setState(() {
            if (_sortCol == i) {
              _desc = !_desc;
            } else {
              _sortCol = i;
              _desc = true;
            }
          }),
          child: Container(
            width: colW,
            height: 34,
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text('$t${_sortCol == i ? (_desc ? ' ▾' : ' ▴') : ''}', style: _headStyle.copyWith(color: _sortCol == i ? AppColors.blue : AppColors.ink3)),
          ),
        );

    final firstList = <Widget>[], rowsList = <Widget>[];
    for (var i = 0; i < ordered.length; i++) {
      final id = ordered[i];
      if (_problemsOnTop && problems.isNotEmpty && i == problems.length) {
        firstList.add(Container(
            height: 26, width: firstW, alignment: Alignment.centerLeft, padding: const EdgeInsets.only(left: 10), color: AppColors.cream, child: Text('HEALTHY · ${healthy.length}', style: _headStyle)));
        rowsList.add(Container(height: 26, width: colW * cols.length, color: AppColors.cream));
      }
      final problem = _isProblem(s, id);
      final tag = _tagOf(s, id);
      final selected = _selected == id;
      firstList.add(InkWell(
        onTap: () => _open(id),
        child: Container(
          height: rowH,
          width: firstW,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: selected ? AppColors.blueLight : (problem ? AppColors.bearLight : AppColors.pureWhite),
            border: Border(bottom: BorderSide(color: AppColors.cream)),
          ),
          child: Row(children: [
            if (problem) Container(width: 6, height: 6, margin: const EdgeInsets.only(right: 6), decoration: BoxDecoration(color: AppColors.bear, shape: BoxShape.circle)),
            Expanded(child: Text(id, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppFonts.mono(size: 11, color: AppColors.ink))),
            if (tag.isNotEmpty) _problemChip(tag),
          ]),
        ),
      ));
      rowsList.add(InkWell(
        onTap: () => _open(id),
        child: Container(
          height: rowH,
          decoration: BoxDecoration(color: selected ? AppColors.blueLight : AppColors.pureWhite, border: Border(bottom: BorderSide(color: AppColors.cream))),
          child: Row(children: [
            for (var c = 0; c < cols.length; c++)
              Container(
                width: colW,
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: (cols[c].problem?.call(values[id]![c]) ?? false)
                    ? _problemChip(cols[c].format(values[id]![c]))
                    : Text(cols[c].format(values[id]![c]), style: AppFonts.mono(size: 13, color: cols[c].tone?.call(values[id]![c]) ?? AppColors.ink)),
              ),
          ]),
        ),
      ));
    }

    final table = ordered.isEmpty
        ? ListView(children: [
            _emptyCard(Icons.table_rows_outlined, _q.isEmpty ? 'No $_noun data yet' : 'No $_noun match "$_q"',
                _q.isEmpty ? 'Rows appear as users on the new build use the app.' : 'Clear the search to see every row.'),
          ])
        : SingleChildScrollView(
            child: Container(
              margin: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.xxl),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(AppRadius.lg), border: Border.all(color: AppColors.birch)),
              clipBehavior: Clip.antiAlias,
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Column(children: [
                  Container(
                      width: firstW, height: 34, color: AppColors.cream, alignment: Alignment.centerLeft, padding: const EdgeInsets.only(left: 10), child: Text(_noun.toUpperCase(), style: _headStyle)),
                  ...firstList,
                ]),
                Expanded(
                  child: Scrollbar(
                    controller: _hScroll,
                    child: SingleChildScrollView(
                      controller: _hScroll,
                      scrollDirection: Axis.horizontal,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Container(color: AppColors.cream, child: Row(children: [for (var c = 0; c < cols.length; c++) headerCell(cols[c].label, c + 1)])),
                        ...rowsList,
                      ]),
                    ),
                  ),
                ),
              ]),
            ),
          );

    final list = Column(children: [
      _search('Search $_noun', (v) => setState(() => _q = v)),
      SizedBox(
        height: 40,
        child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg), children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: FilterChip(
              label: Text('Problems ${problems.length}',
                  style: AppFonts.sans(size: 12, weight: FontWeight.w600, color: problems.isEmpty ? AppColors.ink3 : AppColors.bear)),
              selected: _problemsOnTop,
              onSelected: (v) => setState(() => _problemsOnTop = v),
              visualDensity: VisualDensity.compact,
            ),
          ),
          if (!widget.wide)
            Padding(
              padding: const EdgeInsets.only(left: 8, top: 12),
              child: Text('← swipe for more columns · tap a header to sort', style: AppFonts.sans(size: 11, color: AppColors.ink4)),
            ),
        ]),
      ),
      if (widget.kind == _Kind.buttons && problems.isNotEmpty)
        Container(
          margin: const EdgeInsets.fromLTRB(AppSpacing.lg, 4, AppSpacing.lg, 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: AppColors.bearLight, borderRadius: BorderRadius.circular(AppRadius.lg)),
          child: Row(children: [
            Icon(Icons.warning_amber_rounded, color: AppColors.bear, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text('${problems.length} problem buttons of ${ids.length}: rage-tapped, dead or erroring',
                  style: AppFonts.sans(size: 13, weight: FontWeight.w600, color: AppColors.bear)),
            ),
          ]),
        ),
      Expanded(child: table),
    ]);

    if (!widget.wide) return list;
    final sel = _selected;
    return Row(children: [
      Expanded(child: list),
      VerticalDivider(width: 1, color: AppColors.birch),
      SizedBox(
        width: 380,
        child: sel == null
            ? Center(child: Text('Select a row to see every metric', style: AppText.bodySmall))
            : _EntityDetail(store: s, id: sel, prefix: '$_prefix${sel}_', kind: widget.kind, showTitle: true),
      ),
    ]);
  }
}

/// Every metric for one screen, button or symbol, across all scored users.
class _EntityDetail extends StatelessWidget {
  const _EntityDetail({required this.store, required this.id, required this.prefix, required this.kind, this.showTitle = false});
  final _Store store;
  final String id;
  final String prefix;
  final _Kind kind;
  final bool showTitle;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (_, _) {
        final keys = <String>{
          for (final u in store.states.keys)
            for (final k in store.metricsOf(u).keys)
              if (k.startsWith(prefix)) k,
        }.toList()
          ..sort();
        final noun = switch (kind) { _Kind.screens => 'Screen', _Kind.buttons => 'Button', _Kind.symbols => 'Symbol' };
        final keyTiles = switch (kind) {
          _Kind.screens => [('Opens 7d', 'opens_7d'), ('Errors', 'error_state_views'), ('Exits', 'session_exit_drop_off')],
          _Kind.buttons => [('Taps 7d', 'clicks_7d'), ('Rage', 'rage_double_taps'), ('→ Trade 5m', 'led_to_revenue_or_trade_5m')],
          _Kind.symbols => [('Won 7d', 'trades_won_7d'), ('Lost 7d', 'trades_lost_7d'), ('P&L 30d ₹', 'net_realized_pnl_inr')],
        };
        return ListView(padding: const EdgeInsets.only(bottom: AppSpacing.xxl), children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (showTitle) Text(id, style: AppFonts.mono(size: 15, weight: FontWeight.w600, color: AppColors.ink)),
              Text('$noun · ${keys.length} metrics · ${store.states.length} users scored', style: AppFonts.sans(size: 12, color: AppColors.ink4)),
            ]),
          ),
          _tileGrid([
            for (final (label, suffix) in keyTiles)
              _tile(label, _fmt(store.sum('$prefix$suffix')), tone: _isProblemMetric(suffix, store.sum('$prefix$suffix')) ? 'bear' : null),
          ], cols: 3),
          const SizedBox(height: AppSpacing.md),
          if (keys.isEmpty)
            _emptyCard(Icons.insights_outlined, 'No users have a value here yet', 'Values appear after users on the new build touch this ${noun.toLowerCase()}.')
          else
            _card(
              padding: EdgeInsets.zero,
              child: Column(children: [
                Container(
                  color: AppColors.cream,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(children: [
                    Expanded(flex: 3, child: Text('METRIC', style: _headStyle)),
                    for (final h in ['TOTAL', 'USERS', 'AVG']) Expanded(child: Text(h, textAlign: TextAlign.right, style: _headStyle)),
                  ]),
                ),
                for (final k in keys) _metricRow(k),
              ]),
            ),
        ]);
      },
    );
  }

  Widget _metricRow(String k) {
    final total = store.sum(k), users = store.usersWith(k);
    final short = k.substring(prefix.length);
    return Container(
      decoration: BoxDecoration(border: Border(top: BorderSide(color: AppColors.cream))),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(children: [
        Expanded(flex: 3, child: Text(short, style: AppFonts.mono(size: 11, color: AppColors.ink3))),
        Expanded(
          child: Align(
            alignment: Alignment.centerRight,
            child: _isProblemMetric(short, total) ? _problemChip(_fmt(total)) : Text(_fmt(total), style: _cellStyle),
          ),
        ),
        Expanded(child: Text('$users', textAlign: TextAlign.right, style: _cellStyle)),
        Expanded(child: Text(users == 0 ? '–' : _fmt(total / users), textAlign: TextAlign.right, style: _cellStyle)),
      ]),
    );
  }
}
