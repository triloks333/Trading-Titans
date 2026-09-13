// Timing rules for the Play Store rating prompt.
//
// The failure modes here are both user-visible and both bad: asking someone who
// already rated, or asking again before the snooze is up. Neither shows in a
// build error, so the ordering is pinned here.

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/app_constants.dart';
import 'package:mobile/core/rate_prompt.dart';

void main() {
  final nowMs = DateTime.utc(2026, 8, 19, 10).millisecondsSinceEpoch;
  final snooze = AppConstants.ratePromptSnooze;
  int ago(Duration d) => nowMs - d.inMilliseconds;

  bool show({
    int loginStreak = AppConstants.ratePromptMinStreak,
    bool rated = false,
    int? snoozedAtMs,
  }) =>
      RatePrompt.shouldShow(
        loginStreak: loginStreak,
        rated: rated,
        snoozedAtMs: snoozedAtMs,
        nowMs: nowMs,
      );

  group('RatePrompt.shouldShow', () {
    test('stays quiet below the streak threshold', () {
      expect(show(loginStreak: 0), isFalse);
      expect(show(loginStreak: AppConstants.ratePromptMinStreak - 1), isFalse);
    });

    test('asks on the qualifying day when never asked before', () {
      expect(show(loginStreak: AppConstants.ratePromptMinStreak), isTrue);
      // A longer streak still qualifies — the threshold is a floor, not a match.
      expect(show(loginStreak: 30), isTrue);
    });

    test('never asks again once the user has gone to the store', () {
      // Outranks everything else, including an elapsed snooze.
      expect(show(rated: true), isFalse);
      expect(show(rated: true, loginStreak: 90), isFalse);
      expect(
        show(rated: true, snoozedAtMs: ago(snooze * 10)),
        isFalse,
      );
    });

    test('a dismissal suppresses the ask for the whole interval', () {
      expect(show(snoozedAtMs: nowMs), isFalse);
      expect(show(snoozedAtMs: ago(snooze - const Duration(minutes: 1))),
          isFalse);
    });

    test('the ask returns once the interval has elapsed', () {
      expect(show(snoozedAtMs: ago(snooze)), isTrue);
      expect(show(snoozedAtMs: ago(snooze + const Duration(days: 1))), isTrue);
    });

    test('each dismissal buys another full interval', () {
      // Re-snoozing at the moment the previous window expired must not leave
      // the prompt immediately eligible again.
      final firstWindowExpired = ago(snooze);
      expect(show(snoozedAtMs: firstWindowExpired), isTrue);
      // The dialog writes a fresh timestamp; 13 days later it is still quiet.
      final reSnoozedAt = nowMs;
      expect(
        RatePrompt.shouldShow(
          loginStreak: 5,
          rated: false,
          snoozedAtMs: reSnoozedAt,
          nowMs: reSnoozedAt + (snooze - const Duration(days: 1)).inMilliseconds,
        ),
        isFalse,
      );
      expect(
        RatePrompt.shouldShow(
          loginStreak: 5,
          rated: false,
          snoozedAtMs: reSnoozedAt,
          nowMs: reSnoozedAt + snooze.inMilliseconds,
        ),
        isTrue,
      );
    });

    test('a backwards device clock keeps the snooze instead of re-asking', () {
      // Negative elapsed time must not read as "interval satisfied".
      expect(show(snoozedAtMs: nowMs + snooze.inMilliseconds), isFalse);
    });

    test('the streak gate applies even after the snooze expires', () {
      expect(
        show(loginStreak: 1, snoozedAtMs: ago(snooze * 2)),
        isFalse,
      );
    });
  });
}
