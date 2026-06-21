import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_service.dart';

/// Thin, crash-safe wrapper around Firebase Analytics used to record the
/// onboarding funnel (onboarding_open -> signup_method_selected ->
/// signup_completed -> first_trade) and other product events.
///
/// Every call is best-effort: if Firebase isn't initialized or logging throws,
/// it silently no-ops so analytics can never break a user flow.
class AnalyticsService {
  AnalyticsService._();

  static Future<void> log(String name, [Map<String, Object>? params]) async {
    try {
      if (!FirebaseService.instance.isInitialized) return;
      await FirebaseAnalytics.instance.logEvent(name: name, parameters: params);
    } catch (_) {}
  }

  /// Funnel step 1: the auth/login screen was shown.
  static Future<void> logOnboardingOpen() => log('onboarding_open');

  /// Funnel step 2: the user picked a way to get in (email / google / guest).
  static Future<void> logSignupMethodSelected(String method) =>
      log('signup_method_selected', {'method': method});

  /// Funnel step 3: an account (or guest session) was successfully created.
  static Future<void> logSignupCompleted(String method) =>
      log('signup_completed', {'method': method});

  /// Funnel step 4: the user placed their very first trade. Fires at most once
  /// per install (guarded by a SharedPreferences flag) so it maps cleanly onto
  /// a funnel's "reached this step" semantics.
  static Future<void> logFirstTradeOnce(String market) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool('first_trade_logged') == true) return;
      await prefs.setBool('first_trade_logged', true);
      await log('first_trade', {'market': market});
    } catch (_) {}
  }
}
