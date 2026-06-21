import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'firebase_service.dart';

/// Captures DEVICE-LEVEL diagnostics for the auth/login flow so we can tell why
/// a login works on one phone but fails on another (the kind of failure the
/// server-side provisioning log can't see).
///
/// Crashlytics records each failure as a non-fatal with custom keys (step,
/// reason, identifier) and automatically attaches the device model, OS version
/// and app version. Analytics logs aggregate `login_step` / `login_failed`
/// events so you can spot patterns (e.g. "all failures are app_version 1.0.8 on
/// Android 13") in the Firebase console.
///
/// Every call is best-effort and never throws back into the caller, so it can
/// never itself break a login.
class DiagnosticsService {
  DiagnosticsService._();

  static String? _appVersion;

  static Future<String> _version() async {
    if (_appVersion != null) return _appVersion!;
    try {
      final info = await PackageInfo.fromPlatform();
      _appVersion = '${info.version}+${info.buildNumber}';
    } catch (_) {
      _appVersion = 'unknown';
    }
    return _appVersion!;
  }

  /// A breadcrumb marking where we are in the login flow. Helps order events
  /// when a later failure/crash is reported on the same device.
  static Future<void> logStep(String step, {String? identifier}) async {
    try {
      if (!FirebaseService.instance.isInitialized) return;
      final v = await _version();
      await FirebaseCrashlytics.instance.log('login_step:$step');
      final params = <String, Object>{
        'step': step,
        'app_version': v,
        'platform': defaultTargetPlatform.name,
      };
      if (identifier != null) params['id'] = identifier;
      await FirebaseAnalytics.instance.logEvent(
        name: 'login_step',
        parameters: params,
      );
    } catch (_) {}
  }

  /// Records a login/auth failure with full device context.
  ///
  /// [step] says where it broke, e.g. 'email_signin', 'profile_fetch',
  /// 'profile_missing', 'google_oauth', 'guest_signin', 'register'.
  /// [error]/[stack] are the raw cause (NOT the user-facing message).
  /// [identifier] (email/uid) is attached to Crashlytics only — never to the
  /// aggregate Analytics event — so we can correlate a specific user's device.
  static Future<void> logLoginFailure(
    String step,
    Object error, [
    StackTrace? stack,
    String? identifier,
  ]) async {
    try {
      if (!FirebaseService.instance.isInitialized) return;
      final v = await _version();
      final transient = FirebaseService.isTransientNetworkError(error);

      final c = FirebaseCrashlytics.instance;
      await c.setCustomKey('login_step', step);
      await c.setCustomKey('app_version', v);
      await c.setCustomKey('platform', defaultTargetPlatform.name);
      await c.setCustomKey('login_error_transient', transient);
      if (identifier != null) {
        await c.setCustomKey('login_identifier', identifier);
      }
      await c.recordError(
        error,
        stack,
        reason: 'login_failure:$step',
        fatal: false,
      );

      await FirebaseAnalytics.instance.logEvent(
        name: 'login_failed',
        parameters: {
          'step': step,
          'transient': transient.toString(),
          'app_version': v,
          'platform': defaultTargetPlatform.name,
        },
      );
    } catch (_) {}
  }
}
