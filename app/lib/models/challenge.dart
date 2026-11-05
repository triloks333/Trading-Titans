/// A gamification challenge plus this user's progress against it, as returned
/// by the `get_my_challenges()` RPC (one round trip for catalogue + progress).
class Challenge {
  final String key;
  final String title;
  final String description;
  final String category; // performance | habit | breadth | learning | social
  final double rewardAmount;
  final int xp;

  /// How many times this challenge can ever pay out. `null` means unlimited
  /// (used by the weekly podium placings).
  final int? repeatLimit;
  final int sortOrder;
  final int timesEarned;
  final double totalEarned;
  final DateTime? lastEarnedAt;

  /// Running measure toward the next payout and its threshold, from
  /// get_my_challenges(); null for challenges with no single measure.
  final double? progress;
  final double? target;

  const Challenge({
    required this.key,
    required this.title,
    required this.description,
    required this.category,
    required this.rewardAmount,
    required this.xp,
    required this.repeatLimit,
    required this.sortOrder,
    required this.timesEarned,
    required this.totalEarned,
    this.lastEarnedAt,
    this.progress,
    this.target,
  });

  /// 0..1 toward [target]; 1 once complete; null when there is no measure.
  double? get fraction {
    if (isComplete) return 1;
    final t = target, p = progress;
    if (t == null || p == null || t <= 0) return null;
    return (p / t).clamp(0.0, 1.0);
  }

  /// Money milestones count rupees; everything else counts things.
  bool get isMoneyMeasure => key == 'titan_20' || key.startsWith('century_club');

  /// Earned at least once.
  bool get isEarned => timesEarned > 0;

  /// Nothing left to earn — a one-shot already claimed, or a repeatable one
  /// that has hit its limit.
  bool get isComplete => repeatLimit != null && timesEarned >= repeatLimit!;

  /// Remaining payouts, or `null` when unlimited.
  int? get remaining =>
      repeatLimit == null ? null : (repeatLimit! - timesEarned).clamp(0, repeatLimit!);

  static double _toDouble(dynamic v) =>
      v == null ? 0.0 : (v is num ? v.toDouble() : double.tryParse('$v') ?? 0.0);

  static int _toInt(dynamic v) =>
      v == null ? 0 : (v is num ? v.toInt() : int.tryParse('$v') ?? 0);

  factory Challenge.fromJson(Map<String, dynamic> json) => Challenge(
        key: json['key'] as String,
        title: json['title'] as String? ?? '',
        description: json['description'] as String? ?? '',
        category: json['category'] as String? ?? 'performance',
        rewardAmount: _toDouble(json['reward_amount']),
        xp: _toInt(json['xp']),
        repeatLimit: json['repeat_limit'] == null ? null : _toInt(json['repeat_limit']),
        sortOrder: _toInt(json['sort_order']),
        timesEarned: _toInt(json['times_earned']),
        totalEarned: _toDouble(json['total_earned']),
        lastEarnedAt: json['last_earned_at'] == null
            ? null
            : DateTime.tryParse('${json['last_earned_at']}'),
        progress: json['progress'] == null ? null : _toDouble(json['progress']),
        target: json['target'] == null ? null : _toDouble(json['target']),
      );
}

/// Display metadata for a challenge category. Keeps labels and ordering in one
/// place so the screen does not scatter switch statements.
class ChallengeCategory {
  final String key;
  final String label;

  const ChallengeCategory(this.key, this.label);

  static const List<ChallengeCategory> all = [
    ChallengeCategory('performance', 'Performance'),
    ChallengeCategory('habit', 'Consistency'),
    ChallengeCategory('breadth', 'Explore markets'),
    ChallengeCategory('learning', 'Learn the ropes'),
    ChallengeCategory('social', 'Community'),
  ];

  static String labelFor(String key) =>
      all.firstWhere((c) => c.key == key, orElse: () => const ChallengeCategory('', 'Other')).label;
}

/// Titan levels derived from total XP. Deliberately non-cash: it lets us reward
/// engagement without inflating wallet balances and wrecking the leaderboard.
class TitanLevel {
  final String name;
  final int minXp;

  const TitanLevel(this.name, this.minXp);

  static const List<TitanLevel> ladder = [
    TitanLevel('Novice', 0),
    TitanLevel('Apprentice', 250),
    TitanLevel('Trader', 750),
    TitanLevel('Strategist', 1750),
    TitanLevel('Veteran', 3500),
    TitanLevel('Titan', 6000),
  ];

  static TitanLevel forXp(int xp) {
    var current = ladder.first;
    for (final level in ladder) {
      if (xp >= level.minXp) current = level;
    }
    return current;
  }

  /// The next level up, or `null` at the top of the ladder.
  static TitanLevel? nextAfter(int xp) {
    for (final level in ladder) {
      if (level.minXp > xp) return level;
    }
    return null;
  }

  /// Progress 0..1 towards the next level. Returns 1.0 at max level.
  static double progressToNext(int xp) {
    final current = forXp(xp);
    final next = nextAfter(xp);
    if (next == null) return 1.0;
    final span = next.minXp - current.minXp;
    if (span <= 0) return 1.0;
    return ((xp - current.minXp) / span).clamp(0.0, 1.0);
  }
}
