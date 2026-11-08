import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme.dart';

/// Admin → Intelligence tab. Live from three realtime streams:
/// `intel_events` (raw events, last 24h), `intel_user_state` (per-user computed
/// metrics) and `intel_reaction_firings` (every reaction, delivered or
/// suppressed), plus the `intel_admin_overview()` RPC every 30s.
/// Every number on screen comes from those sources; nothing is faked.
class AdminCustomerIntelligenceScreen extends StatefulWidget {
  final bool embedded;
  const AdminCustomerIntelligenceScreen({super.key, this.embedded = false});

  @override
  State<AdminCustomerIntelligenceScreen> createState() => _AdminCustomerIntelligenceScreenState();
}

/// Shared live store for every tab and the per-user drill-down.
class _Store extends ChangeNotifier {
  static const _cap = 10000;
  final List<Map<String, dynamic>> events = [];
  final Set<Object> _ids = {};
  final Map<String, String> names = {};
  /// user_id → {metrics, updated_at}
  final Map<String, Map<String, dynamic>> states = {};
  final List<Map<String, dynamic>> firings = [];
  final Set<Object> _firingIds = {};

  void loadEvents(List<Map<String, dynamic>> rows) {
    for (final r in rows) {
      if (_ids.add(r['id'])) events.add(r);
    }
    events.sort((a, b) => _ts(b).compareTo(_ts(a)));
    notifyListeners();
  }

  bool addEvent(Map<String, dynamic> row) {
    if (!_ids.add(row['id'])) return false;
    events.insert(0, row);
    if (events.length > _cap) _ids.remove(events.removeLast()['id']);
    notifyListeners();
    return true;
  }

  void putState(Map<String, dynamic> row) {
    states['${row['user_id']}'] = row;
    notifyListeners();
  }

  void addFirings(Iterable<Map<String, dynamic>> rows) {
    for (final r in rows) {
      if (_firingIds.add(r['id'])) firings.add(r);
    }
    firings.sort((a, b) => _ts(b).compareTo(_ts(a)));
    notifyListeners();
  }

  void setNames(Map<String, String> m) {
    names.addAll(m);
    notifyListeners();
  }

  String nameOf(String? uid) => uid == null ? 'anonymous' : (names[uid] ?? '${uid.substring(0, 8)}…');

  Map<String, num> metricsOf(String uid) {
    final m = states[uid]?['metrics'];
    return m is Map ? {for (final e in m.entries) '${e.key}': _num(e.value)} : const {};
  }

  /// Sum of [key] across every user's computed metrics.
  num sum(String key) => states.keys.fold<num>(0, (a, u) => a + (metricsOf(u)[key] ?? 0));
  int usersWith(String key) => states.keys.where((u) => (metricsOf(u)[key] ?? 0) > 0).length;
}

DateTime _ts(Map<String, dynamic> e) => DateTime.tryParse('${e['created_at'] ?? e['updated_at']}')?.toLocal() ?? DateTime.fromMillisecondsSinceEpoch(0);
Map<String, dynamic> _props(Map<String, dynamic> e) => e['props'] is Map ? Map<String, dynamic>.from(e['props'] as Map) : const {};
num _num(Object? v) => v is num ? v : num.tryParse('$v') ?? 0;
String _fmt(num v) => v == v.roundToDouble() ? '${v.round()}' : v.toStringAsFixed(2);

String _ago(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inSeconds < 60) return '${d.inSeconds.clamp(0, 59)}s ago';
  if (d.inMinutes < 60) return '${d.inMinutes}m ago';
  if (d.inHours < 24) return '${d.inHours}h ago';
  return '${d.inDays}d ago';
}

String _summary(Map<String, dynamic> e) => _props(e).entries.map((p) => '${p.key}=${p.value}').join(' · ');

class _AdminCustomerIntelligenceScreenState extends State<AdminCustomerIntelligenceScreen> {
  final _db = Supabase.instance.client;
  final _store = _Store();
  RealtimeChannel? _channel;
  Timer? _overviewTimer;
  Timer? _clockTimer;
  Map<String, dynamic>? _overview;
  String? _error;
  bool _loading = true;
  String _live = 'connecting';
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    // Subscribe first so no row falls between the snapshot and the stream; the store dedupes.
    _channel = _db
        .channel('admin-intel')
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
        .subscribe((status, err) {
      // removeChannel() in dispose fires this synchronously; ignore it then.
      if (mounted && !_closing) setState(() => _live = status == RealtimeSubscribeStatus.subscribed ? 'live' : status.name);
    });
    _overviewTimer = Timer.periodic(const Duration(seconds: 30), (_) => _loadOverview());
    // Keeps the "x ago" labels honest without refetching.
    _clockTimer = Timer.periodic(const Duration(seconds: 15), (_) => mounted ? setState(() {}) : null);
    await _refresh();
  }

  Future<void> _refresh() async {
    await Future.wait([_loadEvents(), _loadStates(), _loadFirings(), _loadOverview()]);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadEvents() async {
    try {
      final since = DateTime.now().toUtc().subtract(const Duration(hours: 24)).toIso8601String();
      final rows = await _db
          .from('intel_events')
          .select('id, user_id, session_id, name, props, client_ts, created_at')
          .gte('created_at', since)
          .order('created_at', ascending: false)
          .limit(5000);
      _store.loadEvents(List<Map<String, dynamic>>.from(rows));
      await _resolveNames(_store.events.map((e) => e['user_id'] as String?));
      _error = null;
    } catch (e) {
      _error = 'Could not load events: $e';
    }
  }

  Future<void> _loadStates() async {
    try {
      final rows = await _db.from('intel_user_state').select('user_id, metrics, updated_at').order('updated_at', ascending: false).limit(1000);
      for (final r in rows) {
        _store.putState(Map<String, dynamic>.from(r));
      }
      await _resolveNames(_store.states.keys);
    } catch (e) {
      _error = 'Could not load user metrics: $e';
    }
  }

  Future<void> _loadFirings() async {
    try {
      final since = DateTime.now().toUtc().subtract(const Duration(days: 7)).toIso8601String();
      final rows = await _db
          .from('intel_reaction_firings')
          .select('id, user_id, reaction, delivered, reason, props, created_at')
          .gte('created_at', since)
          .order('created_at', ascending: false)
          .limit(2000);
      _store.addFirings(List<Map<String, dynamic>>.from(rows));
      await _resolveNames(_store.firings.map((e) => e['user_id'] as String?));
    } catch (e) {
      _error = 'Could not load reactions: $e';
    }
  }

  Future<void> _loadOverview() async {
    try {
      final res = await _db.rpc('intel_admin_overview');
      if (mounted && res is Map) setState(() => _overview = Map<String, dynamic>.from(res));
    } catch (_) {
      // Tiles keep their last real value; the streams still update.
    }
  }

  Future<void> _resolveNames(Iterable<String?> uids) async {
    final missing = uids.whereType<String>().where((u) => !_store.names.containsKey(u)).toSet().toList();
    if (missing.isEmpty) return;
    try {
      final m = <String, String>{};
      for (var i = 0; i < missing.length; i += 100) {
        final rows = await _db.from('profiles').select('id, name, email').inFilter('id', missing.sublist(i, (i + 100).clamp(0, missing.length)));
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

  static const _tabs = ['Overview', 'Live feed', 'Users', 'Screens', 'Buttons', 'Symbols', 'Reactions'];

  @override
  Widget build(BuildContext context) {
    final content = DefaultTabController(
      length: _tabs.length,
      child: Column(children: [
        _header(),
        Container(
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.birch))),
          child: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: AppColors.ink,
            unselectedLabelColor: AppColors.ink3,
            indicatorColor: AppColors.titanGold,
            labelStyle: AppFonts.sans(size: 13, weight: FontWeight.w600),
            tabs: [for (final t in _tabs) Tab(text: t)],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : ListenableBuilder(
                  listenable: _store,
                  builder: (context, _) => TabBarView(children: [
                    _wrap(_OverviewTab(store: _store, overview: _overview)),
                    _wrap(_LiveFeed(store: _store)),
                    _wrap(_UsersTab(store: _store)),
                    _wrap(_ScreensTab(store: _store)),
                    _wrap(_ButtonsTab(store: _store)),
                    _wrap(_SymbolsTab(store: _store)),
                    _wrap(_ReactionsTab(store: _store)),
                  ]),
                ),
        ),
      ]),
    );

    if (widget.embedded) return content;
    return Scaffold(
      appBar: AppBar(title: const Text('Customer intelligence'), backgroundColor: AppColors.pureWhite, foregroundColor: AppColors.ink, elevation: 0),
      body: content,
    );
  }

  Widget _wrap(Widget child) => RefreshIndicator(onRefresh: _refresh, child: child);

  Widget _header() {
    final live = _live == 'live';
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.sm),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: live ? AppColors.bull : AppColors.ink4, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(live ? 'LIVE' : _live.toUpperCase(), style: AppText.badge.copyWith(color: live ? AppColors.bull : AppColors.ink4)),
          const SizedBox(width: 8),
          Expanded(
            child: Text('${_store.events.length} events (24h) · ${_store.states.length} users scored · ${_store.firings.length} reactions (7d)',
                style: AppText.bodySmall, overflow: TextOverflow.ellipsis),
          ),
        ]),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(_error!, style: AppText.bodySmall.copyWith(color: AppColors.bear))),
      ]),
    );
  }
}

// ── Shared bits ─────────────────────────────────────────────────────────────

Widget _empty([String text = 'No data yet']) => ListView(children: [
      Padding(padding: const EdgeInsets.all(AppSpacing.xxl), child: Center(child: Text(text, style: AppText.body))),
    ]);

Widget _tile(String label, String value) => Container(
      width: 108,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: AppColors.pureWhite, borderRadius: BorderRadius.circular(AppRadius.md), border: Border.all(color: AppColors.birch)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label.toUpperCase(), style: AppText.sectionLabel, maxLines: 2, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 4),
        Text(value, style: AppText.valueMed),
      ]),
    );

Widget _section(String title) => Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.sm),
      child: Text(title.toUpperCase(), style: AppText.sectionLabel),
    );

Widget _eventTile(Map<String, dynamic> e, {String? who}) {
  final s = _summary(e);
  return ListTile(
    dense: true,
    title: Text(who == null ? '${e['name']}' : '$who · ${e['name']}', style: AppText.bodyBold, maxLines: 1, overflow: TextOverflow.ellipsis),
    subtitle: s.isEmpty ? null : Text(s, style: AppFonts.mono(size: 11, color: AppColors.ink3), maxLines: 2, overflow: TextOverflow.ellipsis),
    trailing: Text(_ago(_ts(e)), style: AppText.bodySmall),
  );
}

Widget _row(List<String> cells, TextStyle style) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 8),
      child: Row(children: [
        Expanded(flex: 3, child: Text(cells.first, style: style, maxLines: 2, overflow: TextOverflow.ellipsis)),
        for (final c in cells.skip(1)) Expanded(child: Text(c, style: style, textAlign: TextAlign.right)),
      ]),
    );

/// Header row + rows of cells; first column flexes.
Widget _table(List<String> head, List<List<String>> rows, {String empty = 'No data yet'}) {
  if (rows.isEmpty) return _empty(empty);
  return ListView.separated(
    itemCount: rows.length + 1,
    separatorBuilder: (_, _) => Divider(height: 1, color: AppColors.birch),
    itemBuilder: (_, i) => i == 0 ? _row(head, AppText.sectionLabel) : _row(rows[i - 1], AppFonts.mono(size: 12, color: AppColors.ink)),
  );
}

/// Distinct entity ids found in metric keys, e.g. `btn_<id>_clicks_7d` → id.
Set<String> _entities(_Store s, String prefix, String suffix) => {
      for (final u in s.states.keys)
        for (final k in s.metricsOf(u).keys)
          if (k.startsWith(prefix) && k.endsWith(suffix)) k.substring(prefix.length, k.length - suffix.length),
    };

// ── Tabs ────────────────────────────────────────────────────────────────────

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({required this.store, required this.overview});
  final _Store store;
  final Map<String, dynamic>? overview;

  @override
  Widget build(BuildContext context) {
    String v(String k) => overview == null ? '–' : '${overview![k] ?? 0}';
    final s = store;
    final perMin = (overview?['events_per_minute_60m'] as List?) ?? const [];
    final maxN = perMin.fold<num>(1, (a, e) => _num((e as List)[1]) > a ? _num(e[1]) : a);
    final byName = ((overview?['events_by_name_24h'] as Map?) ?? const {}).entries.toList()
      ..sort((a, b) => _num(b.value).compareTo(_num(a.value)));
    final pv = s.sum('x_paywall_pack_view_30d'), cs = s.sum('x_paywall_checkout_start_30d');
    final ps = s.sum('x_paywall_purchase_success_30d'), pf = s.sum('x_paywall_purchase_failed_30d');
    return ListView(children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        child: Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.sm, children: [
          _tile('Active 5m', v('users_active_5m')),
          _tile('Active 24h', v('users_active_24h')),
          _tile('Users scored', '${s.states.length}'),
          _tile('Events 1h', v('events_1h')),
          _tile('Events 24h', v('events_24h')),
          _tile('Reactions sent 24h', v('reactions_delivered_24h')),
          _tile('Suppressed 24h', v('reactions_suppressed_24h')),
          _tile('Crash credits 7d', v('apologies_7d')),
          _tile('Crashed since open', '${s.usersWith('hw_crashed_since_last_open_current')}'),
          _tile('Slow cold start', '${s.usersWith('hw_cold_start_slow_over_4000ms_current')}'),
        ]),
      ),
      _section('Events per minute (60m)'),
      SizedBox(
        height: 60,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: perMin.isEmpty
              ? Text('No events in the last hour', style: AppText.bodySmall)
              : Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  for (final e in perMin)
                    Expanded(
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 1),
                        height: 60 * _num((e as List)[1]) / maxN,
                        color: AppColors.titanGold,
                      ),
                    ),
                ]),
        ),
      ),
      _section('Paywall funnel (30d, all users)'),
      _row(['STEP', 'COUNT', '% OF VIEWS'], AppText.sectionLabel),
      for (final (label, n) in [('Pack viewed', pv), ('Checkout started', cs), ('Purchase succeeded', ps), ('Purchase failed', pf)])
        _row([label, _fmt(n), pv == 0 ? '–' : '${(n / pv * 100).round()}%'], AppFonts.mono(size: 12, color: AppColors.ink)),
      _section('Events by name (24h)'),
      for (final e in byName.take(20)) _row([e.key, '${e.value}'], AppFonts.mono(size: 12, color: AppColors.ink)),
      const SizedBox(height: AppSpacing.xxl),
    ]);
  }
}

class _LiveFeed extends StatelessWidget {
  const _LiveFeed({required this.store});
  final _Store store;

  @override
  Widget build(BuildContext context) {
    final ev = store.events;
    if (ev.isEmpty) return _empty('No events yet');
    return ListView.separated(
      itemCount: ev.length.clamp(0, 500),
      separatorBuilder: (_, _) => Divider(height: 1, color: AppColors.birch),
      itemBuilder: (_, i) => _eventTile(ev[i], who: store.nameOf(ev[i]['user_id'] as String?)),
    );
  }
}

class _UsersTab extends StatelessWidget {
  const _UsersTab({required this.store});
  final _Store store;

  @override
  Widget build(BuildContext context) {
    final latest = <String, DateTime>{};
    final counts = <String, int>{};
    for (final e in store.events) {
      final u = e['user_id'] as String?;
      if (u == null) continue;
      latest.putIfAbsent(u, () => _ts(e));
      counts[u] = (counts[u] ?? 0) + 1;
    }
    for (final u in store.states.keys) {
      final t = _ts(store.states[u]!);
      if (t.isAfter(latest[u] ?? DateTime(0))) latest[u] = t;
    }
    if (latest.isEmpty) return _empty('No users yet');
    final users = latest.keys.toList()..sort((a, b) => latest[b]!.compareTo(latest[a]!));
    return ListView.separated(
      itemCount: users.length,
      separatorBuilder: (_, _) => Divider(height: 1, color: AppColors.birch),
      itemBuilder: (context, i) {
        final u = users[i];
        final m = store.metricsOf(u);
        final recent = DateTime.now().difference(latest[u]!).inMinutes < 5;
        return ListTile(
          leading: Icon(Icons.circle, size: 10, color: recent ? AppColors.bull : AppColors.ink5),
          title: Text(store.nameOf(u), style: AppText.bodyBold, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
              '${counts[u] ?? 0} events 24h · ${m.length} metrics · streak ${_fmt(m['hw_login_streak_current_days_current'] ?? 0)}d',
              style: AppText.bodySmall),
          trailing: Text(_ago(latest[u]!), style: AppText.bodySmall),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => _UserDetail(store: store, userId: u))),
        );
      },
    );
  }
}

/// Every computed metric for one user, grouped by section and searchable,
/// plus their raw event timeline and reactions.
class _UserDetail extends StatefulWidget {
  const _UserDetail({required this.store, required this.userId});
  final _Store store;
  final String userId;

  @override
  State<_UserDetail> createState() => _UserDetailState();
}

class _UserDetailState extends State<_UserDetail> {
  String _q = '';

  static const _sections = {
    'launch_': 'Launches', 'hw_': 'App health', 'scr_': 'Screens', 'btn_': 'Buttons', 'sym_': 'Symbols', 'x_': 'Other',
  };

  @override
  Widget build(BuildContext context) {
    final s = widget.store;
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(s.nameOf(widget.userId)),
          backgroundColor: AppColors.pureWhite,
          foregroundColor: AppColors.ink,
          elevation: 0,
          bottom: TabBar(
            labelColor: AppColors.ink,
            unselectedLabelColor: AppColors.ink3,
            indicatorColor: AppColors.titanGold,
            tabs: const [Tab(text: 'Metrics'), Tab(text: 'Events'), Tab(text: 'Reactions')],
          ),
        ),
        body: ListenableBuilder(
          listenable: s,
          builder: (_, _) => TabBarView(children: [_metrics(), _events(), _reactions()]),
        ),
      ),
    );
  }

  Widget _metrics() {
    final s = widget.store;
    final m = s.metricsOf(widget.userId);
    final updated = s.states[widget.userId];
    final keys = m.keys.where((k) => _q.isEmpty || k.contains(_q)).toList()..sort();
    final grouped = <String, List<String>>{};
    for (final k in keys) {
      final sec = _sections.entries.firstWhere((e) => k.startsWith(e.key), orElse: () => const MapEntry('', 'Other')).value;
      (grouped[sec] ??= []).add(k);
    }
    return ListView(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, 0),
        child: TextField(
          decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Filter metrics (e.g. reliance, rage, order_entry)', isDense: true),
          onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, 0),
        child: Text(
            updated == null
                ? 'No computed metrics uploaded yet (the app uploads every 5 min and on pause).'
                : '${m.length} non-zero metrics · updated ${_ago(_ts(updated))}',
            style: AppText.bodySmall),
      ),
      for (final sec in _sections.values.toSet())
        if (grouped[sec] != null) ...[
          _section('$sec (${grouped[sec]!.length})'),
          for (final k in grouped[sec]!) _row([k, _fmt(m[k]!)], AppFonts.mono(size: 11, color: AppColors.ink)),
        ],
      const SizedBox(height: AppSpacing.xxl),
    ]);
  }

  Widget _events() {
    final ev = widget.store.events.where((e) => e['user_id'] == widget.userId).toList();
    if (ev.isEmpty) return _empty('No events in the last 24h');
    return ListView.separated(
      itemCount: ev.length,
      separatorBuilder: (_, _) => Divider(height: 1, color: AppColors.birch),
      itemBuilder: (_, i) => _eventTile(ev[i]),
    );
  }

  Widget _reactions() {
    final f = widget.store.firings.where((e) => e['user_id'] == widget.userId).toList();
    if (f.isEmpty) return _empty('No reactions in the last 7 days');
    return ListView.separated(
      itemCount: f.length,
      separatorBuilder: (_, _) => Divider(height: 1, color: AppColors.birch),
      itemBuilder: (_, i) => _firingTile(f[i]),
    );
  }
}

class _ScreensTab extends StatelessWidget {
  const _ScreensTab({required this.store});
  final _Store store;

  @override
  Widget build(BuildContext context) {
    final s = store;
    final live = <String, int>{};
    for (final e in s.events.where((e) => e['name'] == 'screen_view')) {
      final k = '${_props(e)['screen']}';
      live[k] = (live[k] ?? 0) + 1;
    }
    final screens = {..._entities(s, 'scr_', '_opens_7d'), ...live.keys}.toList();
    num avgOf(String k) {
      final us = s.states.keys.where((u) => (s.metricsOf(u)[k] ?? 0) > 0).toList();
      return us.isEmpty ? 0 : us.fold<num>(0, (a, u) => a + s.metricsOf(u)[k]!) / us.length;
    }

    screens.sort((a, b) => s.sum('scr_${b}_opens_7d').compareTo(s.sum('scr_${a}_opens_7d')));
    return _table(['SCREEN', '24H LIVE', 'OPENS 7D', 'AVG DWELL', 'BOUNCE', 'SCROLL', 'RAGE', 'EXITS'], [
      for (final x in screens)
        [
          x,
          '${live[x] ?? 0}',
          _fmt(s.sum('scr_${x}_opens_7d')),
          '${avgOf('scr_${x}_avg_dwell_sec_per_visit').toStringAsFixed(1)}s',
          _fmt(s.sum('scr_${x}_pogo_bounce_under_1500ms')),
          '${avgOf('scr_${x}_max_scroll_depth_pct').round()}%',
          _fmt(s.sum('scr_${x}_rage_tap_bursts')),
          _fmt(s.sum('scr_${x}_session_exit_drop_off')),
        ],
    ]);
  }
}

class _ButtonsTab extends StatelessWidget {
  const _ButtonsTab({required this.store});
  final _Store store;

  @override
  Widget build(BuildContext context) {
    final s = store;
    final live = <String, int>{};
    for (final e in s.events.where((e) => e['name'] == 'tap')) {
      final k = '${_props(e)['button']}';
      live[k] = (live[k] ?? 0) + 1;
    }
    final btns = {..._entities(s, 'btn_', '_clicks_30d'), ..._entities(s, 'btn_', '_zero_click_dead_button_flag'), ...live.keys}.toList();
    num score(String b) => s.sum('btn_${b}_rage_double_taps') * 1000 + s.usersWith('btn_${b}_zero_click_dead_button_flag') * 100 + s.sum('btn_${b}_clicks_7d');
    btns.sort((a, b) => score(b).compareTo(score(a)));
    // Flags first: rage-tapped or dead buttons are what admins act on.
    return _table(['BUTTON', '24H LIVE', '7D', 'CTR 7D', 'DEAD FOR', 'RAGE', '→TRADE'], [
      for (final b in btns)
        [
          b,
          '${live[b] ?? 0}',
          _fmt(s.sum('btn_${b}_clicks_7d')),
          s.states.isEmpty ? '–' : '${(s.sum('btn_${b}_ctr_pct_7d') / s.states.length).toStringAsFixed(1)}%',
          '${s.usersWith('btn_${b}_zero_click_dead_button_flag')}',
          _fmt(s.sum('btn_${b}_rage_double_taps')),
          _fmt(s.sum('btn_${b}_led_to_revenue_or_trade_5m')),
        ],
    ]);
  }
}

class _SymbolsTab extends StatelessWidget {
  const _SymbolsTab({required this.store});
  final _Store store;

  @override
  Widget build(BuildContext context) {
    final s = store;
    final syms = {
      for (final suf in ['_chart_views_7d', '_trades_won_7d', '_trades_lost_7d', '_net_realized_pnl_inr', '_margin_shortfall_rejections']) ..._entities(s, 'sym_', suf),
    }.toList();
    num trades(String x) => s.sum('sym_${x}_trades_won_7d') + s.sum('sym_${x}_trades_lost_7d');
    syms.sort((a, b) => (trades(b) * 10 + s.sum('sym_${b}_chart_views_7d')).compareTo(trades(a) * 10 + s.sum('sym_${a}_chart_views_7d')));
    return _table(['SYMBOL', 'VIEWS 7D', 'W/L 7D', 'WIN %', 'P&L 30D', 'SHORT', 'REVENGE', 'HOLD'], [
      for (final x in syms)
        [
          x,
          _fmt(s.sum('sym_${x}_chart_views_7d')),
          '${_fmt(s.sum('sym_${x}_trades_won_7d'))}/${_fmt(s.sum('sym_${x}_trades_lost_7d'))}',
          trades(x) == 0 ? '–' : '${(s.sum('sym_${x}_trades_won_7d') / trades(x) * 100).round()}%',
          AppFormat.formatINR(s.sum('sym_${x}_net_realized_pnl_inr')),
          _fmt(s.sum('sym_${x}_margin_shortfall_rejections')),
          _fmt(s.sum('sym_${x}_revenge_trade_under_120s')),
          s.usersWith('sym_${x}_avg_hold_time_minutes') == 0
              ? '–'
              : '${(s.sum('sym_${x}_avg_hold_time_minutes') / s.usersWith('sym_${x}_avg_hold_time_minutes')).round()}m',
        ],
    ], empty: 'No symbol activity yet');
  }
}

Widget _firingTile(Map<String, dynamic> f, {String? who}) {
  final delivered = f['delivered'] == true;
  final p = _summary(f);
  return ListTile(
    dense: true,
    leading: Icon(delivered ? Icons.check_circle : Icons.block, size: 18, color: delivered ? AppColors.bull : AppColors.bear),
    title: Text('${who == null ? '' : '$who · '}${f['reaction']}', style: AppText.bodyBold, maxLines: 1, overflow: TextOverflow.ellipsis),
    subtitle: Text('${delivered ? 'delivered' : 'suppressed'} · ${f['reason']}${p.isEmpty ? '' : ' · $p'}',
        style: AppFonts.mono(size: 11, color: AppColors.ink3), maxLines: 2, overflow: TextOverflow.ellipsis),
    trailing: Text(_ago(_ts(f)), style: AppText.bodySmall),
  );
}

class _ReactionsTab extends StatelessWidget {
  const _ReactionsTab({required this.store});
  final _Store store;

  @override
  Widget build(BuildContext context) {
    final f = store.firings;
    if (f.isEmpty) return _empty('No reactions in the last 7 days');
    final byKey = <String, (int, int)>{};
    final reasons = <String, int>{};
    for (final r in f) {
      final k = '${r['reaction']}';
      final (d, sup) = byKey[k] ?? (0, 0);
      byKey[k] = r['delivered'] == true ? (d + 1, sup) : (d, sup + 1);
      if (r['delivered'] != true) reasons['${r['reason']}'] = (reasons['${r['reason']}'] ?? 0) + 1;
    }
    return ListView(children: [
      _section('By reaction (7d)'),
      _row(['REACTION', 'DELIVERED', 'SUPPRESSED'], AppText.sectionLabel),
      for (final e in byKey.entries) _row([e.key, '${e.value.$1}', '${e.value.$2}'], AppFonts.mono(size: 12, color: AppColors.ink)),
      if (reasons.isNotEmpty) ...[
        _section('Suppression reasons'),
        for (final e in reasons.entries) _row([e.key, '${e.value}'], AppFonts.mono(size: 12, color: AppColors.ink)),
      ],
      _section('Latest'),
      for (final r in f.take(300)) _firingTile(r, who: store.nameOf(r['user_id'] as String?)),
    ]);
  }
}
