import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme.dart';

/// Admin → Intelligence tab. Reads `intel_events` (last 24h once, then live
/// realtime inserts) and the `intel_admin_overview()` RPC every 30s.
/// Every number on screen comes from those two sources; nothing is faked.
class AdminCustomerIntelligenceScreen extends StatefulWidget {
  final bool embedded;
  const AdminCustomerIntelligenceScreen({super.key, this.embedded = false});

  @override
  State<AdminCustomerIntelligenceScreen> createState() => _AdminCustomerIntelligenceScreenState();
}

/// Newest-first event store shared by the tabs and the per-user drill-down.
class _Feed extends ChangeNotifier {
  static const _cap = 10000;
  final List<Map<String, dynamic>> events = [];
  final Set<Object> _ids = {};
  final Map<String, String> names = {};

  void load(List<Map<String, dynamic>> rows) {
    for (final r in rows) {
      if (_ids.add(r['id'])) events.add(r);
    }
    events.sort((a, b) => _ts(b).compareTo(_ts(a)));
    notifyListeners();
  }

  bool add(Map<String, dynamic> row) {
    if (!_ids.add(row['id'])) return false;
    events.insert(0, row);
    if (events.length > _cap) _ids.remove(events.removeLast()['id']);
    notifyListeners();
    return true;
  }

  void setNames(Map<String, String> m) {
    names.addAll(m);
    notifyListeners();
  }

  String nameOf(String? uid) => uid == null ? 'anonymous' : (names[uid] ?? '${uid.substring(0, 8)}…');
}

DateTime _ts(Map<String, dynamic> e) => DateTime.tryParse('${e['created_at']}')?.toLocal() ?? DateTime.fromMillisecondsSinceEpoch(0);
Map<String, dynamic> _props(Map<String, dynamic> e) => e['props'] is Map ? Map<String, dynamic>.from(e['props'] as Map) : const {};
num _num(Object? v) => v is num ? v : num.tryParse('$v') ?? 0;

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
  final _feed = _Feed();
  RealtimeChannel? _channel;
  Timer? _overviewTimer;
  Timer? _clockTimer;
  Map<String, dynamic>? _overview;
  String? _error;
  bool _loading = true;
  String _live = 'connecting';

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    // Subscribe first so no insert falls between the snapshot and the stream; the feed dedupes by id.
    _channel = _db
        .channel('admin-intel-events')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'intel_events',
          callback: (payload) {
            final row = Map<String, dynamic>.from(payload.newRecord);
            if (_feed.add(row)) _resolveNames([row['user_id'] as String?]);
          },
        )
        .subscribe((status, err) {
      if (mounted) setState(() => _live = status == RealtimeSubscribeStatus.subscribed ? 'live' : status.name);
    });
    _overviewTimer = Timer.periodic(const Duration(seconds: 30), (_) => _loadOverview());
    // Keeps the "x ago" labels honest without refetching.
    _clockTimer = Timer.periodic(const Duration(seconds: 15), (_) => mounted ? setState(() {}) : null);
    await Future.wait([_loadEvents(), _loadOverview()]);
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
      _feed.load(List<Map<String, dynamic>>.from(rows));
      await _resolveNames(_feed.events.map((e) => e['user_id'] as String?));
      _error = null;
    } catch (e) {
      _error = 'Could not load events: $e';
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadOverview() async {
    try {
      final res = await _db.rpc('intel_admin_overview');
      if (mounted && res is Map) setState(() => _overview = Map<String, dynamic>.from(res));
    } catch (_) {
      // Tiles keep their last real value; the feed still updates.
    }
  }

  Future<void> _resolveNames(Iterable<String?> uids) async {
    final missing = uids.whereType<String>().where((u) => !_feed.names.containsKey(u)).toSet().toList();
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
      _feed.setNames(m);
    } catch (_) {
      // Falls back to the short uid.
    }
  }

  Future<void> _refresh() async {
    await Future.wait([_loadEvents(), _loadOverview()]);
  }

  @override
  void dispose() {
    _overviewTimer?.cancel();
    _clockTimer?.cancel();
    final ch = _channel;
    if (ch != null) _db.removeChannel(ch);
    _feed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final content = DefaultTabController(
      length: 5,
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
            tabs: const [Tab(text: 'Live feed'), Tab(text: 'Users'), Tab(text: 'Screens'), Tab(text: 'Buttons'), Tab(text: 'Symbols')],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : ListenableBuilder(
                  listenable: _feed,
                  builder: (context, _) => TabBarView(children: [
                    _wrap(_LiveFeed(feed: _feed)),
                    _wrap(_UsersTab(feed: _feed)),
                    _wrap(_ScreensTab(events: _feed.events)),
                    _wrap(_ButtonsTab(events: _feed.events)),
                    _wrap(_SymbolsTab(events: _feed.events)),
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
    final o = _overview;
    String v(String k) => o == null ? '–' : '${o[k] ?? 0}';
    final live = _live == 'live';
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.sm),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: live ? AppColors.bull : AppColors.ink4, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(live ? 'LIVE' : _live.toUpperCase(), style: AppText.badge.copyWith(color: live ? AppColors.bull : AppColors.ink4)),
          const SizedBox(width: 8),
          Expanded(child: Text('${_feed.events.length} events loaded (24h)', style: AppText.bodySmall, overflow: TextOverflow.ellipsis)),
        ]),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(_error!, style: AppText.bodySmall.copyWith(color: AppColors.bear))),
        const SizedBox(height: AppSpacing.sm),
        Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.sm, children: [
          _tile('Active 5m', v('users_active_5m')),
          _tile('Active 24h', v('users_active_24h')),
          _tile('Events 1h', v('events_1h')),
          _tile('Events 24h', v('events_24h')),
          _tile('Apologies 7d', v('apologies_7d')),
        ]),
      ]),
    );
  }

  Widget _tile(String label, String value) => Container(
        width: 104,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: AppColors.pureWhite, borderRadius: BorderRadius.circular(AppRadius.md), border: Border.all(color: AppColors.birch)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label.toUpperCase(), style: AppText.sectionLabel, maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          Text(value, style: AppText.valueMed),
        ]),
      );
}

// ── Shared bits ─────────────────────────────────────────────────────────────

Widget _empty() => ListView(children: [
      Padding(padding: const EdgeInsets.all(AppSpacing.xxl), child: Center(child: Text('No events yet', style: AppText.body))),
    ]);

Widget _eventTile(Map<String, dynamic> e, {String? who}) {
  final s = _summary(e);
  return ListTile(
    dense: true,
    title: Text(who == null ? '${e['name']}' : '$who · ${e['name']}', style: AppText.bodyBold, maxLines: 1, overflow: TextOverflow.ellipsis),
    subtitle: s.isEmpty ? null : Text(s, style: AppFonts.mono(size: 11, color: AppColors.ink3), maxLines: 2, overflow: TextOverflow.ellipsis),
    trailing: Text(_ago(_ts(e)), style: AppText.bodySmall),
  );
}

/// Simple table: header row + rows of cells; first column flexes.
Widget _table(List<String> head, List<List<String>> rows) {
  if (rows.isEmpty) return _empty();
  Widget row(List<String> cells, TextStyle style) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 8),
        child: Row(children: [
          Expanded(flex: 3, child: Text(cells.first, style: style, maxLines: 2, overflow: TextOverflow.ellipsis)),
          for (final c in cells.skip(1)) Expanded(child: Text(c, style: style, textAlign: TextAlign.right)),
        ]),
      );
  return ListView.separated(
    itemCount: rows.length + 1,
    separatorBuilder: (_, _) => Divider(height: 1, color: AppColors.birch),
    itemBuilder: (_, i) => i == 0 ? row(head, AppText.sectionLabel) : row(rows[i - 1], AppFonts.mono(size: 12, color: AppColors.ink)),
  );
}

// ── Tabs ────────────────────────────────────────────────────────────────────

class _LiveFeed extends StatelessWidget {
  const _LiveFeed({required this.feed});
  final _Feed feed;

  @override
  Widget build(BuildContext context) {
    final ev = feed.events;
    if (ev.isEmpty) return _empty();
    return ListView.separated(
      itemCount: ev.length.clamp(0, 500),
      separatorBuilder: (_, _) => Divider(height: 1, color: AppColors.birch),
      itemBuilder: (_, i) => _eventTile(ev[i], who: feed.nameOf(ev[i]['user_id'] as String?)),
    );
  }
}

class _UsersTab extends StatelessWidget {
  const _UsersTab({required this.feed});
  final _Feed feed;

  @override
  Widget build(BuildContext context) {
    // Events are newest-first, so the first event seen per user is their latest.
    final latest = <String, Map<String, dynamic>>{};
    final counts = <String, int>{};
    for (final e in feed.events) {
      final u = e['user_id'] as String?;
      if (u == null) continue;
      latest.putIfAbsent(u, () => e);
      counts[u] = (counts[u] ?? 0) + 1;
    }
    if (latest.isEmpty) return _empty();
    final users = latest.keys.toList();
    return ListView.separated(
      itemCount: users.length,
      separatorBuilder: (_, _) => Divider(height: 1, color: AppColors.birch),
      itemBuilder: (context, i) {
        final u = users[i];
        final last = latest[u]!;
        final recent = DateTime.now().difference(_ts(last)).inMinutes < 5;
        return ListTile(
          leading: Icon(Icons.circle, size: 10, color: recent ? AppColors.bull : AppColors.ink5),
          title: Text(feed.nameOf(u), style: AppText.bodyBold, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text('${counts[u]} events · last: ${last['name']}', style: AppText.bodySmall),
          trailing: Text(_ago(_ts(last)), style: AppText.bodySmall),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => _UserTimeline(feed: feed, userId: u))),
        );
      },
    );
  }
}

class _UserTimeline extends StatelessWidget {
  const _UserTimeline({required this.feed, required this.userId});
  final _Feed feed;
  final String userId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(feed.nameOf(userId)), backgroundColor: AppColors.pureWhite, foregroundColor: AppColors.ink, elevation: 0),
      body: ListenableBuilder(
        listenable: feed,
        builder: (_, _) {
          final ev = feed.events.where((e) => e['user_id'] == userId).toList();
          if (ev.isEmpty) return _empty();
          return ListView.separated(
            itemCount: ev.length,
            separatorBuilder: (_, _) => Divider(height: 1, color: AppColors.birch),
            itemBuilder: (_, i) => _eventTile(ev[i]),
          );
        },
      ),
    );
  }
}

class _ScreensTab extends StatelessWidget {
  const _ScreensTab({required this.events});
  final List<Map<String, dynamic>> events;

  @override
  Widget build(BuildContext context) {
    final views = <String, int>{}, exits = <String, int>{};
    final dwell = <String, num>{};
    for (final e in events) {
      final s = '${_props(e)['screen'] ?? '?'}';
      if (e['name'] == 'screen_view') views[s] = (views[s] ?? 0) + 1;
      if (e['name'] == 'screen_exit') {
        exits[s] = (exits[s] ?? 0) + 1;
        dwell[s] = (dwell[s] ?? 0) + _num(_props(e)['dwell_ms']);
      }
    }
    final screens = {...views.keys, ...exits.keys}.toList()..sort((a, b) => (views[b] ?? 0).compareTo(views[a] ?? 0));
    return _table(
      ['SCREEN', 'VIEWS', 'AVG DWELL', 'EXITS'],
      [
        for (final s in screens)
          [s, '${views[s] ?? 0}', (exits[s] ?? 0) == 0 ? '–' : '${(dwell[s]! / exits[s]! / 1000).toStringAsFixed(1)}s', '${exits[s] ?? 0}'],
      ],
    );
  }
}

class _ButtonsTab extends StatelessWidget {
  const _ButtonsTab({required this.events});
  final List<Map<String, dynamic>> events;

  @override
  Widget build(BuildContext context) {
    final taps = <String, int>{}, rage = <String, int>{};
    for (final e in events) {
      final p = _props(e);
      final k = '${p['screen'] ?? '?'} › ${p['button'] ?? '?'}';
      if (e['name'] == 'tap') taps[k] = (taps[k] ?? 0) + 1;
      if (e['name'] == 'rage_tap') rage[k] = (rage[k] ?? 0) + 1;
    }
    final keys = {...taps.keys, ...rage.keys}.toList()
      ..sort((a, b) => ((rage[b] ?? 0) * 1000 + (taps[b] ?? 0)).compareTo((rage[a] ?? 0) * 1000 + (taps[a] ?? 0)));
    return _table(['SCREEN › BUTTON', 'TAPS', 'RAGE'], [
      for (final k in keys) [k, '${taps[k] ?? 0}', '${rage[k] ?? 0}'],
    ]);
  }
}

class _SymbolsTab extends StatelessWidget {
  const _SymbolsTab({required this.events});
  final List<Map<String, dynamic>> events;

  @override
  Widget build(BuildContext context) {
    final placed = <String, int>{}, closed = <String, int>{}, wins = <String, int>{};
    final pnl = <String, num>{};
    for (final e in events) {
      final p = _props(e);
      final s = '${p['sym'] ?? '?'}';
      if (e['name'] == 'trade_placed') placed[s] = (placed[s] ?? 0) + 1;
      if (e['name'] == 'trade_closed') {
        final v = _num(p['pnl']);
        closed[s] = (closed[s] ?? 0) + 1;
        if (v > 0) wins[s] = (wins[s] ?? 0) + 1;
        pnl[s] = (pnl[s] ?? 0) + v;
      }
    }
    final syms = {...placed.keys, ...closed.keys}.toList()..sort((a, b) => (placed[b] ?? 0).compareTo(placed[a] ?? 0));
    return _table(['SYMBOL', 'PLACED', 'CLOSED', 'WIN %', 'P&L'], [
      for (final s in syms)
        [
          s,
          '${placed[s] ?? 0}',
          '${closed[s] ?? 0}',
          (closed[s] ?? 0) == 0 ? '–' : '${((wins[s] ?? 0) * 100 / closed[s]!).round()}%',
          (closed[s] ?? 0) == 0 ? '–' : AppFormat.formatINR(pnl[s]!),
        ],
    ]);
  }
}
