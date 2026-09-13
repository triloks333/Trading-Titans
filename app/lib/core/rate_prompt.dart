import 'package:shared_preferences/shared_preferences.dart';
import 'app_constants.dart';

/// Decides when to ask the user to rate the app on the Play Store.
///
/// State is device-local (SharedPreferences), mirroring the soft-update snooze
/// in `AuthService.dismissSoftUpdate()`. Two facts are persisted: whether the
/// user has already been sent to the store, and when they last chose
/// "Remind me later".
///
/// ponytail: "rated" means "tapped Rate now" — Play gives no callback telling
/// us a review was actually left, so tapping through to the store is treated as
/// done. Being device-local also means a reinstall asks again. Upgrade path for
/// both: the Play In-App Review API (`in_app_review`), which reports back that
/// its flow completed and lets Google suppress repeats server-side — but it
/// renders Google's own sheet, so it replaces this two-button dialog rather
/// than dropping into it, and Google quota-limits how often it appears.
class RatePrompt {
  RatePrompt._();

  /// Set once the user taps "Rate now". Suppresses the prompt permanently.
  static const String ratedKey = 'rate_prompt_rated';

  /// Epoch ms of the last "Remind me later". Overwritten on every dismissal.
  static const String snoozedKey = 'rate_prompt_snoozed_time';

  /// Pure gate: no I/O, no clock, deterministic from its arguments.
  ///
  /// Never asks once [rated]. Otherwise waits for the login streak to reach
  /// [AppConstants.ratePromptMinStreak], and for any previous "Remind me later"
  /// to be at least [AppConstants.ratePromptSnooze] old. Because each dismissal
  /// overwrites [snoozedAtMs], repeated deferrals each buy another full
  /// interval rather than the prompt returning early.
  ///
  /// A [nowMs] earlier than [snoozedAtMs] (a device clock moved backwards)
  /// yields a negative elapsed time and so keeps the snooze — the safe
  /// direction, since the failure mode of the alternative is nagging.
  static bool shouldShow({
    required int loginStreak,
    required bool rated,
    required int? snoozedAtMs,
    required int nowMs,
  }) {
    if (rated) return false;
    if (loginStreak < AppConstants.ratePromptMinStreak) return false;
    if (snoozedAtMs == null) return true;
    return nowMs - snoozedAtMs >= AppConstants.ratePromptSnooze.inMilliseconds;
  }

  /// [shouldShow] against the persisted state and the current time.
  ///
  /// Returns false when preferences cannot be read: without the suppression
  /// state we cannot tell an already-rated user from a new one, and asking a
  /// second time is the worse of the two mistakes.
  static Future<bool> shouldShowNow(int loginStreak) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return shouldShow(
        loginStreak: loginStreak,
        rated: prefs.getBool(ratedKey) ?? false,
        snoozedAtMs: prefs.getInt(snoozedKey),
        nowMs: DateTime.now().millisecondsSinceEpoch,
      );
    } catch (_) {
      return false;
    }
  }

  /// Records that the user went to the store, so they are never asked again.
  static Future<void> markRated() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(ratedKey, true);
    } catch (_) {}
  }

  /// Starts a fresh [AppConstants.ratePromptSnooze] window.
  static Future<void> snooze() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(snoozedKey, DateTime.now().millisecondsSinceEpoch);
    } catch (_) {}
  }
}
