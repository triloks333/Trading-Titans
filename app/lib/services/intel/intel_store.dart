import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// One raw telemetry event.
class IntelEvent {
  final String name;
  final Map<String, Object?> props;
  final DateTime ts;
  final String session;
  bool synced;
  IntelEvent(this.name, this.props, this.ts, this.session, {this.synced = false});

  Map<String, Object?> toJson() => {'n': name, 'p': props, 't': ts.millisecondsSinceEpoch, 's': session, 'y': synced};
  factory IntelEvent.fromJson(Map<String, dynamic> j) => IntelEvent(
      j['n'] as String, Map<String, Object?>.from(j['p'] as Map),
      DateTime.fromMillisecondsSinceEpoch(j['t'] as int), j['s'] as String, synced: j['y'] == true);
}

/// Local, bounded event log (30 days / 6,000 events) plus daily snapshots of
/// slow-moving values. Every indicator is computed from this, so the numbers
/// the dashboard shows are traceable to recorded events.
class IntelStore {
  static const _kEvents = 'intel_events_v1';
  static const _kSnapshots = 'intel_snapshots_v1';
  static const maxEvents = 6000;
  static const retention = Duration(days: 30);

  final List<IntelEvent> events = [];
  /// day (yyyy-mm-dd) -> name -> value
  final Map<String, Map<String, num>> snapshots = {};
  late final String sessionId =
      's${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(1 << 20)}';
  SharedPreferences? _prefs;

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    try {
      final raw = _prefs!.getString(_kEvents);
      if (raw != null) {
        events.addAll((jsonDecode(raw) as List).map((e) => IntelEvent.fromJson(e as Map<String, dynamic>)));
      }
      final snaps = _prefs!.getString(_kSnapshots);
      if (snaps != null) {
        (jsonDecode(snaps) as Map<String, dynamic>).forEach((day, m) =>
            snapshots[day] = Map<String, num>.from(m as Map));
      }
    } catch (_) {
      events.clear(); // a corrupt log is dropped, never fatal
    }
    _prune();
  }

  IntelEvent add(String name, [Map<String, Object?> props = const {}]) {
    final e = IntelEvent(name, props, DateTime.now(), sessionId);
    events.add(e);
    if (events.length > maxEvents) events.removeRange(0, events.length - maxEvents);
    return e;
  }

  void snapshot(String name, num value) {
    (snapshots[dayKey(DateTime.now())] ??= {})[name] = value;
  }

  static String dayKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  void _prune() {
    final cutoff = DateTime.now().subtract(retention);
    events.removeWhere((e) => e.ts.isBefore(cutoff));
    final cutKey = dayKey(cutoff);
    snapshots.removeWhere((day, _) => day.compareTo(cutKey) < 0);
  }

  Future<void> persist() async {
    _prune();
    try {
      await _prefs?.setString(_kEvents, jsonEncode([for (final e in events) e.toJson()]));
      await _prefs?.setString(_kSnapshots, jsonEncode(snapshots));
    } catch (_) {}
  }

  /// Sends up to [max] unsynced events (oldest first) through [send] and marks
  /// them synced only once it succeeds, so a failed batch is retried next time
  /// and each event goes up once. Returns how many were sent.
  Future<int> upload(Future<void> Function(List<IntelEvent> batch) send, {int max = 500}) async {
    final batch = events.where((e) => !e.synced).take(max).toList();
    if (batch.isEmpty) return 0;
    await send(batch);
    for (final e in batch) {
      e.synced = true;
    }
    await persist();
    return batch.length;
  }

  // ── query helpers ──────────────────────────────────────────────────────────
  Iterable<IntelEvent> since(Duration d, [String? name]) {
    final cut = DateTime.now().subtract(d);
    return events.where((e) => !e.ts.isBefore(cut) && (name == null || e.name == name));
  }

  Iterable<IntelEvent> today([String? name]) {
    final n = DateTime.now();
    final start = DateTime(n.year, n.month, n.day);
    return events.where((e) => !e.ts.isBefore(start) && (name == null || e.name == name));
  }

  Iterable<IntelEvent> thisSession([String? name]) =>
      events.where((e) => e.session == sessionId && (name == null || e.name == name));

  Iterable<IntelEvent> named(String name) => events.where((e) => e.name == name);
}
