import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

/// One row of `churn_plan/indicators_encyclopedia_4272.md`.
class IntelIndicator {
  final String id, name, matrix, group, what, tells, returnImpact, payImpact;
  const IntelIndicator(this.id, this.name, this.matrix, this.group, this.what,
      this.tells, this.returnImpact, this.payImpact);

  factory IntelIndicator.fromJson(Map<String, dynamic> j) => IntelIndicator(
      j['id'], j['n'], j['m'], j['g'], j['what'] ?? '', j['tells'] ?? '', j['ret'] ?? '', j['pay'] ?? '');
}

/// One row of `churn_plan/action_reaction_encyclopedia_3370.md`.
class IntelRule {
  final String id, rulebookTitle, target, action, reaction, pursuit, goal;
  final int rulebook;
  final String? persona, sym;
  final List<String> refs;
  const IntelRule(this.id, this.rulebook, this.rulebookTitle, this.target, this.persona,
      this.sym, this.refs, this.action, this.reaction, this.pursuit, this.goal);

  factory IntelRule.fromJson(Map<String, dynamic> j) => IntelRule(
      j['id'], j['b'], j['bt'], j['target'], j['persona'], j['sym'],
      List<String>.from(j['refs'] ?? const []), j['action'] ?? '', j['reaction'] ?? '',
      j['pursuit'] ?? '', j['goal'] ?? '');
}

/// The full catalogue, generated from the churn_plan md files by
/// `scripts/gen_intel_catalog.py` into `assets/intel/catalog.json`.
class IntelCatalog {
  final List<IntelIndicator> indicators;
  final List<IntelRule> rules;
  late final Map<String, IntelIndicator> byName = {for (final i in indicators) i.name: i};
  late final Map<int, List<IntelRule>> byRulebook = () {
    final m = <int, List<IntelRule>>{};
    for (final r in rules) {
      (m[r.rulebook] ??= []).add(r);
    }
    return m;
  }();

  IntelCatalog(this.indicators, this.rules);

  static IntelCatalog? _cached;
  static Future<IntelCatalog>? _loading;

  /// Parsed off the UI isolate: the file is ~7 MB of JSON.
  static Future<IntelCatalog> load() {
    if (_cached != null) return Future.value(_cached);
    return _loading ??= () async {
      final raw = await rootBundle.loadString('assets/intel/catalog.json');
      final c = await compute(_parse, raw);
      return _cached = c;
    }();
  }

  static IntelCatalog _parse(String raw) {
    final j = jsonDecode(raw) as Map<String, dynamic>;
    return IntelCatalog(
      [for (final i in j['indicators'] as List) IntelIndicator.fromJson(i)],
      [for (final r in j['rules'] as List) IntelRule.fromJson(r)],
    );
  }

  /// Picks the catalogue rule for a rulebook whose target and persona best
  /// match the live context. [targetMatch] / [personaMatch] score a candidate
  /// string (0 = no match). Returns null if nothing in that rulebook matches.
  IntelRule? match(int rulebook, {String? sym, bool Function(String target)? target,
      int Function(String? persona)? persona}) {
    IntelRule? best;
    var bestScore = 0;
    for (final r in byRulebook[rulebook] ?? const <IntelRule>[]) {
      if (sym != null && r.sym != sym) continue;
      if (target != null && !target(r.target)) continue;
      final s = 1 + (persona?.call(r.persona) ?? 0);
      if (s > bestScore) {
        best = r;
        bestScore = s;
      }
    }
    return best;
  }
}
