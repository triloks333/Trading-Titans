import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'supabase_service.dart';
import '../core/app_constants.dart';
import '../core/legal.dart';
import '../models/user.dart' as app_models;
import 'dart:async';
import 'notification_service.dart';
import 'firebase_service.dart';
import 'analytics_service.dart';
import 'diagnostics_service.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

String mapAuthException(dynamic error) {
  if (error is AuthException) {
    final message = error.message.toLowerCase();
    if (message.contains('invalid login credentials') || message.contains('invalid credentials')) {
      return 'Incorrect email or password. Please try again.';
    } else if (message.contains('email not confirmed')) {
      return 'Please verify your email address before signing in.';
    } else if (message.contains('user already registered') || message.contains('already exists')) {
      return 'An account with this email address already exists.';
    } else if (message.contains('weak password') || message.contains('should be at least')) {
      return 'The password is too weak. Please use a stronger password.';
    } else if (message.contains('network') || message.contains('connection')) {
      return 'Connection error. Please check your internet connection.';
    } else if (message.contains('invalid email') || message.contains('email address is invalid')) {
      return 'Please enter a valid email address.';
    }
    return error.message;
  }
  
  final errorStr = error.toString().toLowerCase();
  if (errorStr.contains('invalid referral code')) {
    return 'Invalid referral code. Please check the code and try again.';
  }
  if (errorStr.contains('exception: ')) {
    return error.toString().substring(error.toString().indexOf('exception: ') + 11);
  }
  return error.toString();
}

/// True when this is an anonymous ("guest") session.
///
/// Two signals because they clear at different moments. [supabaseIsAnonymous]
/// is the authoritative JWT claim and flips as soon as the session refreshes,
/// while [profileEmail] still carries the `@guest.tradingtitans` placeholder
/// until convert_guest_account() syncs it. Treating either as "still a guest"
/// keeps the upgrade option visible if the profile sync was missed — and
/// re-running the upgrade is what repairs it.
bool isGuestAccount({bool? supabaseIsAnonymous, String? profileEmail}) =>
    (supabaseIsAnonymous ?? false) ||
    (profileEmail != null && profileEmail.endsWith(AppConstants.guestEmailDomain));

/// Error text for the guest → permanent upgrade.
///
/// [mapAuthException]'s generic "An account with this email address already
/// exists." is a dead end mid-upgrade. Accounts are never merged (moving
/// orders, holdings and balances between two user ids is exactly the risk this
/// feature avoids), so the user is told to sign in to the account they already
/// have instead.
String mapConversionException(dynamic error) {
  final raw = error is AuthException ? error.message : error.toString();
  final msg = raw.toLowerCase();

  if (msg.contains('already been registered') ||
      msg.contains('already registered') ||
      msg.contains('already exists') ||
      msg.contains('already in use')) {
    return 'That email already has a Trading Titans account. Sign out and sign in '
        'to it instead, or upgrade with a different email.';
  }
  if (msg.contains('already linked') || msg.contains('identity is already')) {
    return 'That Google account is already linked to another Trading Titans '
        'account. Sign out and sign in with it instead, or pick a different one.';
  }
  // Operator misconfiguration (manual identity linking is off in the Supabase
  // dashboard), not something the user can act on.
  if (msg.contains('manual linking') || msg.contains('manual_linking')) {
    return 'Account upgrades are temporarily unavailable. Please try again later.';
  }
  return mapAuthException(error);
}

/// Immutable result of evaluating the remote `app_config` map against the
/// locally installed app version. Produced by the pure [evaluateConfig]
/// function so the update / maintenance gating decision is deterministic and
/// testable in isolation from any I/O.
class EvaluationResult {
  /// True when the local version is below `min_supported_version` (a blocking
  /// hard update is required).
  final bool needsHardUpdate;

  /// True when the local version is within the soft-update window
  /// (`min_supported <= local < latest`) and no active 24h snooze applies.
  final bool needsSoftUpdate;

  /// True only when `maintenance_mode` equals the literal string "true".
  final bool needsMaintenanceMode;

  /// Validated, non-empty store URL, or '' when absent/empty.
  final String updateUrl;

  /// Maintenance message from config, or '' (UI applies a default when empty).
  final String maintenanceMessage;

  /// Release notes for the latest version, or '' when absent.
  final String latestVersionNotes;

  /// False when `min_supported_version` is absent or invalid (the minimum
  /// version check could not be completed; gating fails open).
  final bool minCheckCompleted;

  /// Indicates the underlying config fetch failed/timed out. Always false for
  /// the pure evaluation; set by the fetch wrapper (task 6.2).
  final bool refreshFailed;

  const EvaluationResult({
    required this.needsHardUpdate,
    required this.needsSoftUpdate,
    required this.needsMaintenanceMode,
    required this.updateUrl,
    required this.maintenanceMessage,
    required this.latestVersionNotes,
    required this.minCheckCompleted,
    required this.refreshFailed,
  });
}

/// Matches a strict `MAJOR.MINOR.PATCH` semantic version where each segment is
/// 1–6 digits (0–999999).
final RegExp _semverPattern = RegExp(r'^(\d{1,6})\.(\d{1,6})\.(\d{1,6})$');

/// Validates [raw] against [_semverPattern] before delegating to
/// [Version.parse]. Returns null when the value is absent, malformed, or
/// otherwise unparseable so callers can treat the field as unavailable.
Version? _tryParseConfigVersion(String? raw) {
  if (raw == null) return null;
  final value = raw.trim();
  if (!_semverPattern.hasMatch(value)) return null;
  try {
    return Version.parse(value);
  } catch (_) {
    return null;
  }
}

/// Pure evaluation of the remote `app_config` map.
///
/// No I/O, no `notifyListeners`, deterministic from its arguments. All gating
/// decisions are derived per-field and fail open independently:
///
/// - `min_supported_version` / `latest_version` are validated against
///   `^(\d{1,6})\.(\d{1,6})\.(\d{1,6})$` before [Version.parse]; an
///   invalid/absent value makes that field unavailable so its derived state
///   stays false. `minCheckCompleted` is false when `min_supported_version`
///   is invalid/absent.
/// - `update_url` must be a non-empty string; otherwise the hard/soft update
///   states that depend on it stay false.
/// - `maintenance_mode` is true only when the value equals the literal "true".
/// - `needsHardUpdate` = `localVersion < minSupported`.
/// - `needsSoftUpdate` = `minSupported <= localVersion < latest` AND no active
///   24h snooze (`nowTs - dismissedTs <= 24h` means snoozed).
/// - `maintenanceMessage` is taken from config or '' (UI applies the default).
EvaluationResult evaluateConfig(
  Map<String, String> config,
  Version localVersion,
  int nowTs,
  int? dismissedTs,
) {
  // Maintenance mode is true only for the exact literal "true".
  final needsMaintenanceMode = config['maintenance_mode'] == 'true';
  final maintenanceMessage = config['maintenance_message'] ?? '';
  final latestVersionNotes = config['latest_version_notes'] ?? '';

  // update_url must be a non-empty string to drive hard/soft gating.
  final rawUpdateUrl = config['update_url'];
  final updateUrl =
      (rawUpdateUrl != null && rawUpdateUrl.trim().isNotEmpty) ? rawUpdateUrl : '';
  final hasUpdateUrl = updateUrl.isNotEmpty;

  // Per-field version validation (invalid/absent => field unavailable).
  final minSupportedVersion = _tryParseConfigVersion(config['min_supported_version']);
  final latestVersion = _tryParseConfigVersion(config['latest_version']);
  final minCheckCompleted = minSupportedVersion != null;

  // Hard update: local below the minimum supported version, with a usable URL.
  var needsHardUpdate = false;
  if (minSupportedVersion != null && hasUpdateUrl) {
    needsHardUpdate = localVersion < minSupportedVersion;
  }

  // Soft update window: minSupported <= local < latest, no active 24h snooze.
  var needsSoftUpdate = false;
  if (minSupportedVersion != null && latestVersion != null && hasUpdateUrl) {
    final inWindow =
        minSupportedVersion <= localVersion && localVersion < latestVersion;
    final snoozed = dismissedTs != null &&
        (nowTs - dismissedTs) <= const Duration(hours: 24).inMilliseconds;
    needsSoftUpdate = inWindow && !snoozed;
  }

  return EvaluationResult(
    needsHardUpdate: needsHardUpdate,
    needsSoftUpdate: needsSoftUpdate,
    needsMaintenanceMode: needsMaintenanceMode,
    updateUrl: updateUrl,
    maintenanceMessage: maintenanceMessage,
    latestVersionNotes: latestVersionNotes,
    minCheckCompleted: minCheckCompleted,
    refreshFailed: false,
  );
}

class AuthService extends ChangeNotifier {
  final SupabaseService _supabase = SupabaseService();
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  bool _isInitializing = true;
  bool get isInitializing => _isInitializing;

  bool _isRecoveringPassword = false;
  bool get isRecoveringPassword => _isRecoveringPassword;

  void clearRecoveringPassword() {
    _isRecoveringPassword = false;
    notifyListeners();
  }

  bool _needsMaintenanceMode = false;
  bool get needsMaintenanceMode => _needsMaintenanceMode;
  String _maintenanceMessage = '';
  String get maintenanceMessage => _maintenanceMessage;

  bool _needsHardUpdate = false;
  bool get needsHardUpdate => _needsHardUpdate;

  bool _needsSoftUpdate = false;
  bool get needsSoftUpdate => _needsSoftUpdate;

  String _updateUrl = '';
  String get updateUrl => _updateUrl;

  String _latestVersionNotes = '';
  String get latestVersionNotes => _latestVersionNotes;

  /// True when the most recent config fetch (during [initialize] or
  /// [reevaluate]) failed or timed out. On [initialize] the gating states are
  /// failed open to false; on [reevaluate] the last-known gating states are
  /// retained while this flag is surfaced.
  bool _refreshFailed = false;
  bool get refreshFailed => _refreshFailed;

  /// Default copy shown on the maintenance screen when `maintenance_message`
  /// is absent or empty. Preserves the previous in-service default behavior.
  static const String _defaultMaintenanceMessage =
      'We are currently performing system upgrades. We will be back online shortly!';

  app_models.User? _user;
  app_models.User? get user => _user;

  bool get isAuthenticated => _user != null;

  /// The `latest_version` the most recent successful config fetch reported.
  /// Empty until that first fetch; only used to scope the snooze key.
  String _latestVersion = '';

  /// Snooze key for the soft-update prompt, scoped to the version on offer.
  ///
  /// This used to be a single global key, which meant dismissing one release's
  /// prompt also silenced the *next* release's for 24h — exactly wrong for a
  /// hotfix. Keying by version means a newly published `latest_version` starts
  /// with no snooze and is always announced.
  String get _snoozeKey => 'soft_update_dismissed_time_$_latestVersion';

  Future<void> dismissSoftUpdate() async {
    _needsSoftUpdate = false;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_snoozeKey, DateTime.now().millisecondsSinceEpoch);
    } catch (_) {}
  }

  /// Re-runs the config fetch (10s timeout) + [evaluateConfig] and notifies
  /// listeners so the gating UI re-applies. Unlike [initialize], a failed or
  /// timed-out refresh RETAINS the last-known gating states
  /// (`_needsHardUpdate` / `_needsSoftUpdate` / `_needsMaintenanceMode`) rather
  /// than failing open to false; it only surfaces [refreshFailed] = true.
  Future<void> reevaluate() async {
    try {
      final result = await _fetchAndEvaluate();
      _applyEvaluation(result);
      _refreshFailed = false;
    } catch (e) {
      debugPrint('reevaluate(): refresh failed, retaining last-known states. Error: $e');
      _refreshFailed = true;
    }
    notifyListeners();
  }

  /// Reads the locally installed app version via [PackageInfo], falling back
  /// to `0.0.0` when it cannot be read or parsed (so any non-empty minimum
  /// would gate, matching a fresh/unknown install conservatively).
  Future<Version> _readLocalVersion() async {
    var localVersionStr = '1.0.0';
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      localVersionStr = packageInfo.version;
    } catch (_) {}
    try {
      return Version.parse(localVersionStr);
    } catch (_) {
      return Version.none;
    }
  }

  /// Reads the persisted soft-update dismissal timestamp (ms since epoch), or
  /// null when none is stored / it cannot be read.
  Future<int?> _readDismissedTimestamp() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getInt(_snoozeKey);
    } catch (_) {
      return null;
    }
  }

  /// Fetches `app_config` (with a 10s timeout) and runs the pure
  /// [evaluateConfig] against the local version, the current time, and the
  /// persisted snooze timestamp. Throws on fetch failure/timeout so callers
  /// can apply their own fail-open vs. retain-last-known policy.
  Future<EvaluationResult> _fetchAndEvaluate() async {
    final localVersion = await _readLocalVersion();
    final config = await _supabase
        .getAppVersionConfig()
        .timeout(const Duration(seconds: 10));
    // Must be set before the snooze is read: the key is scoped to this version.
    _latestVersion = config['latest_version'] ?? '';
    final dismissedTs = await _readDismissedTimestamp();
    return evaluateConfig(
      config,
      localVersion,
      DateTime.now().millisecondsSinceEpoch,
      dismissedTs,
    );
  }

  /// Copies an [EvaluationResult] onto the live gating state fields. Preserves
  /// the existing in-service behavior of substituting a default maintenance
  /// message when maintenance is active but no message is configured.
  void _applyEvaluation(EvaluationResult result) {
    _needsHardUpdate = result.needsHardUpdate;
    _needsSoftUpdate = result.needsSoftUpdate;
    _needsMaintenanceMode = result.needsMaintenanceMode;
    _updateUrl = result.updateUrl;
    _latestVersionNotes = result.latestVersionNotes;
    _maintenanceMessage =
        (result.needsMaintenanceMode && result.maintenanceMessage.isEmpty)
            ? _defaultMaintenanceMessage
            : result.maintenanceMessage;
  }

  Future<void> initialize() async {
    // Fetch remote config (10s timeout) & apply the pure evaluation.
    // Fail open: on any failure/timeout, all gating states are cleared and the
    // user is allowed to proceed.
    try {
      final result = await _fetchAndEvaluate();
      _applyEvaluation(result);
      _refreshFailed = false;
    } catch (e) {
      debugPrint('Fail-Open triggered: Failed to load remote config. Error: $e');
      _needsHardUpdate = false;
      _needsSoftUpdate = false;
      _needsMaintenanceMode = false;
      _refreshFailed = true;
    }

    _user = await _supabase.getUserProfile();
    _isInitializing = false;
    notifyListeners();

    if (isAuthenticated) {
      unawaited(NotificationService.instance.setup());
      if (FirebaseService.instance.isInitialized) {
        unawaited(FirebaseAnalytics.instance.setUserId(id: _supabase.client.auth.currentUser!.id));
        unawaited(FirebaseCrashlytics.instance.setCustomKey('user_id', _supabase.client.auth.currentUser!.id));
      }
    }

    _supabase.client.auth.onAuthStateChange.listen((data) {
      final AuthChangeEvent event = data.event;
      if (event == AuthChangeEvent.passwordRecovery) {
        _isRecoveringPassword = true;
        notifyListeners();
      }
      
      final session = data.session;
      if (event == AuthChangeEvent.userUpdated) {
        // Fired when a linked identity or a confirmed email lands on the
        // account — the moment a guest upgrade becomes finalisable.
        unawaited(_completePendingConversion());
      }

      if (event == AuthChangeEvent.signedIn && session != null) {
        refreshUser();
        unawaited(_applyPendingReferral());
        unawaited(_logPendingSignupAnalytics());
        unawaited(_applyPendingTermsAcceptance());
        unawaited(_completePendingConversion());
        unawaited(NotificationService.instance.setup());
        if (FirebaseService.instance.isInitialized) {
          unawaited(FirebaseAnalytics.instance.setUserId(id: session.user.id));
          unawaited(FirebaseCrashlytics.instance.setCustomKey('user_id', session.user.id));
        }
      } else if (event == AuthChangeEvent.signedOut) {
        _user = null;
        NotificationService.instance.dispose();
        if (FirebaseService.instance.isInitialized) {
          unawaited(FirebaseAnalytics.instance.setUserId(id: null));
        }
        notifyListeners();
      }
    });
  }

  Future<void> login(String email, String password) async {
    unawaited(DiagnosticsService.logStep('email_signin_attempt', identifier: email));
    try {
      await _supabase.signIn(email: email, password: password);
      _user = await _supabase.getUserProfile();
      if (isAuthenticated) {
        unawaited(NotificationService.instance.setup());
        if (FirebaseService.instance.isInitialized) {
          unawaited(FirebaseAnalytics.instance.setUserId(id: _supabase.client.auth.currentUser!.id));
          unawaited(FirebaseCrashlytics.instance.setCustomKey('user_id', _supabase.client.auth.currentUser!.id));
        }
      } else {
        // Auth succeeded but no profile loaded — this is exactly what strands a
        // user at login. Record it (with device context) so we can see it.
        unawaited(DiagnosticsService.logLoginFailure(
          'profile_missing_after_signin',
          StateError('signed in but profile is null'),
          StackTrace.current,
          email,
        ));
      }
      notifyListeners();
    } catch (e, st) {
      unawaited(DiagnosticsService.logLoginFailure('email_signin', e, st, email));
      throw Exception(mapAuthException(e));
    }
  }

  Future<void> register(String email, String password, String name, {String? referralCode}) async {
    unawaited(DiagnosticsService.logStep('register_attempt', identifier: email));
    try {
      await _supabase.signUp(email: email, password: password, name: name, referralCode: referralCode);
      for (int i = 0; i < 5; i++) {
        _user = await _supabase.getUserProfile();
        if (_user != null) break;
        await Future.delayed(const Duration(milliseconds: 500));
      }
      // Funnel step 3: account created via email.
      unawaited(AnalyticsService.logSignupCompleted('email'));
      unawaited(_recordTermsAcceptance());
      if (_user == null) {
        unawaited(DiagnosticsService.logLoginFailure(
          'profile_missing_after_register',
          StateError('registered but profile is null after retries'),
          StackTrace.current,
          email,
        ));
      }
      if (isAuthenticated) {
        unawaited(NotificationService.instance.setup());
        if (FirebaseService.instance.isInitialized) {
          unawaited(FirebaseAnalytics.instance.setUserId(id: _supabase.client.auth.currentUser!.id));
          unawaited(FirebaseCrashlytics.instance.setCustomKey('user_id', _supabase.client.auth.currentUser!.id));
        }
      }
      notifyListeners();
    } catch (e, st) {
      unawaited(DiagnosticsService.logLoginFailure('register', e, st, email));
      throw Exception(mapAuthException(e));
    }
  }

  /// Signs the user in anonymously ("guest" mode) so they can explore and
  /// trade immediately with the starting balance. The profile is created by
  /// the handle_new_user() trigger right after sign-in, so we poll briefly
  /// (mirroring [register]) before reporting success. Guests are blocked
  /// server-side from topping up / buying plans / referral payouts.
  Future<void> continueAsGuest() async {
    unawaited(DiagnosticsService.logStep('guest_signin_attempt'));
    try {
      await _supabase.client.auth.signInAnonymously();
      for (int i = 0; i < 5; i++) {
        _user = await _supabase.getUserProfile();
        if (_user != null) break;
        await Future.delayed(const Duration(milliseconds: 500));
      }
      // Funnel step 3: guest session created.
      unawaited(AnalyticsService.logSignupCompleted('guest'));
      unawaited(_recordTermsAcceptance());
      if (_user == null) {
        unawaited(DiagnosticsService.logLoginFailure(
          'profile_missing_after_guest',
          StateError('guest signed in but profile is null after retries'),
          StackTrace.current,
        ));
      }
      if (isAuthenticated) {
        unawaited(NotificationService.instance.setup());
        if (FirebaseService.instance.isInitialized) {
          unawaited(FirebaseAnalytics.instance.setUserId(id: _supabase.client.auth.currentUser!.id));
          unawaited(FirebaseCrashlytics.instance.setCustomKey('user_id', _supabase.client.auth.currentUser!.id));
        }
      }
      notifyListeners();
    } catch (e, st) {
      unawaited(DiagnosticsService.logLoginFailure('guest_signin', e, st));
      throw Exception(mapAuthException(e));
    }
  }

  Future<void> signInWithGoogle({String? referralCode}) async {
    try {
      // OAuth can't carry signup metadata the way email/password does, so we
      // stash the referral code locally and apply it via RPC once the user
      // returns signed-in. Persisted so it survives the browser round-trip.
      final code = referralCode?.trim();
      try {
        final prefs = await SharedPreferences.getInstance();
        if (code != null && code.isNotEmpty) {
          await prefs.setString('pending_referral_code', code);
        } else {
          await prefs.remove('pending_referral_code');
        }
        // Funnel: remember the method so we can log signup_completed when the
        // OAuth round-trip returns the user signed-in.
        await prefs.setString('pending_signup_method', 'google');
        // Consent was ticked on the auth screen a moment ago, but OAuth leaves
        // the app entirely, so it cannot be recorded until we are signed in and
        // back. Stashed for the same reason the referral code is, and applied by
        // _applyPendingTermsAcceptance() when the auth listener fires.
        await prefs.setString('pending_terms_version', LegalDocs.termsVersion);
      } catch (_) {}

      await _supabase.client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: AppConstants.authRedirectUrl,
      );
    } catch (e, st) {
      unawaited(DiagnosticsService.logLoginFailure('google_oauth', e, st));
      throw Exception(mapAuthException(e));
    }
  }

  /// True when the signed-in account is still a guest.
  bool get isGuest => isGuestAccount(
        supabaseIsAnonymous: _supabase.client.auth.currentUser?.isAnonymous,
        profileEmail: _user?.email,
      );

  /// Step 1 of the email upgrade: attach [email] to the guest account.
  ///
  /// Supabase emails a confirmation link and will not accept a password until
  /// it has been followed, so the upgrade cannot be a single call. Nothing is
  /// copied or migrated — the auth user keeps its id, so every order, holding,
  /// reward and ledger row stays attached.
  Future<void> startEmailConversion(String email) async {
    final trimmed = email.trim();
    if (trimmed.length < 3 ||
        !trimmed.contains('@') ||
        trimmed.endsWith(AppConstants.guestEmailDomain)) {
      throw Exception('Please enter a valid email address.');
    }
    unawaited(DiagnosticsService.logStep('convert_email_attempt', identifier: trimmed));
    try {
      await _setConversionPending(true);
      await _supabase.client.auth.updateUser(UserAttributes(email: trimmed));
    } catch (e, st) {
      await _setConversionPending(false);
      unawaited(DiagnosticsService.logLoginFailure('convert_email_link', e, st, trimmed));
      throw Exception(mapConversionException(e));
    }
  }

  /// Step 2 of the email upgrade, reachable only once the address is verified.
  /// Returns the demo cash credited, or null if the identity is not attached
  /// yet.
  Future<num?> setConversionPassword(String password) async {
    try {
      await _supabase.client.auth.updateUser(UserAttributes(password: password));
    } catch (e, st) {
      unawaited(DiagnosticsService.logLoginFailure('convert_set_password', e, st));
      throw Exception(mapConversionException(e));
    }
    return completeConversion();
  }

  /// Upgrades by linking a Google identity. Uses the same deep link as
  /// [signInWithGoogle], so the redirect is already wired; the upgrade is
  /// finalised when the app comes back and the auth listener fires.
  Future<void> convertWithGoogle() async {
    unawaited(DiagnosticsService.logStep('convert_google_attempt'));
    try {
      await _setConversionPending(true);
      await _supabase.client.auth.linkIdentity(
        OAuthProvider.google,
        redirectTo: AppConstants.authRedirectUrl,
      );
    } catch (e, st) {
      await _setConversionPending(false);
      unawaited(DiagnosticsService.logLoginFailure('convert_google_link', e, st));
      throw Exception(mapConversionException(e));
    }
  }

  /// Finalises an upgrade. The session is refreshed first: until it is, the JWT
  /// still carries `is_anonymous: true`, and credit_demo_cash /
  /// activate_subscription / apply_referral_code would go on rejecting the user
  /// for the remainder of the token's life.
  ///
  /// Returns the demo cash credited, or null when the identity is not fully
  /// attached yet (the confirmation link has not been followed).
  Future<num?> completeConversion() async {
    try {
      await _supabase.client.auth.refreshSession();
    } catch (e) {
      // A stale token only delays the guest restrictions lifting; the upgrade
      // itself is decided server-side from auth.users, so carry on.
      debugPrint('Session refresh before conversion failed: $e');
    }
    final result = await _supabase.convertGuestAccount();
    if (!result.converted) return null;
    await refreshUser();
    notifyListeners();
    return result.bonus;
  }

  /// Finalises an upgrade that was started before an app round-trip (the Google
  /// redirect, or reopening the app from the email confirmation link).
  /// Best-effort: the RPC is idempotent, so a retry on the next auth event is
  /// harmless.
  Future<void> _completePendingConversion() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool('pending_conversion') != true) return;
      final bonus = await completeConversion();
      if (bonus != null) {
        await prefs.remove('pending_conversion');
        unawaited(AnalyticsService.log('guest_conversion_completed', {'bonus': bonus}));
      }
    } catch (e) {
      debugPrint('Pending conversion completion skipped: $e');
    }
  }

  Future<void> _setConversionPending(bool pending) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (pending) {
        await prefs.setBool('pending_conversion', true);
      } else {
        await prefs.remove('pending_conversion');
      }
    } catch (_) {}
  }

  /// Applies any referral code stashed before a Google sign-in. Best-effort:
  /// failures never block login, and the underlying RPC is idempotent (it
  /// no-ops for already-referred users or outside the new-signup window).
  Future<void> _applyPendingReferral() async {
    String? code;
    try {
      final prefs = await SharedPreferences.getInstance();
      code = prefs.getString('pending_referral_code');
      if (code == null || code.trim().isEmpty) return;
      final applied = await _supabase.applyReferralCode(code);
      await prefs.remove('pending_referral_code');
      if (applied) {
        await refreshUser();
      }
    } catch (e) {
      debugPrint('Pending referral apply skipped: $e');
    }
  }

  /// Fires the signup_completed funnel event for an OAuth (Google) sign-in that
  /// originated from one of our auth buttons. Best-effort and one-shot (the
  /// pending marker is cleared immediately).
  /// Records acceptance of the Terms and Privacy Policy for the current user.
  ///
  /// Called straight after the email and guest account-creation paths, where the
  /// consent checkbox was ticked moments earlier in the same session.
  ///
  /// Best-effort: the checkbox has already gated the UI, so a network failure
  /// here must not fail an account that was just created successfully. An
  /// unrecorded acceptance is repaired on the next sign-in, because the RPC is
  /// idempotent per version.
  Future<void> _recordTermsAcceptance() async {
    await _supabase.acceptTerms(LegalDocs.termsVersion);
  }

  /// Applies the acceptance stashed before a Google redirect.
  ///
  /// The Google path cannot record consent inline: `signInWithGoogle` hands off to
  /// a browser and returns before the user is authenticated, and the RPC derives
  /// the user from auth.uid(). So the version is written to local storage before
  /// the redirect and consumed here, once the auth listener confirms a session.
  /// One-shot — the marker is cleared whether or not the write succeeds, and the
  /// RPC being idempotent means a lost marker costs nothing.
  Future<void> _applyPendingTermsAcceptance() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final version = prefs.getString('pending_terms_version');
      if (version == null) return;
      await prefs.remove('pending_terms_version');
      await _supabase.acceptTerms(version);
    } catch (_) {}
  }

  Future<void> _logPendingSignupAnalytics() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final method = prefs.getString('pending_signup_method');
      if (method == null) return;
      await prefs.remove('pending_signup_method');
      await AnalyticsService.logSignupCompleted(method);
    } catch (_) {}
  }

  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _supabase.client.auth.resetPasswordForEmail(
        email,
        redirectTo: AppConstants.authRedirectUrl,
      );
    } catch (e) {
      throw Exception(mapAuthException(e));
    }
  }

  Future<void> updatePassword(String newPassword) async {
    try {
      await _supabase.client.auth.updateUser(
        UserAttributes(password: newPassword),
      );
    } catch (e) {
      throw Exception(mapAuthException(e));
    }
  }

  Future<void> logout() async {
    await _supabase.signOut();
    _user = null;
    notifyListeners();
  }

  /// Re-reads the profile. Never throws: this is called un-awaited from the
  /// `onAuthStateChange` listener and from screen loads, so a server hiccup here
  /// became an unhandled async error reported as a fatal crash. On failure the
  /// last-known user is kept and listeners are not disturbed.
  Future<void> refreshUser() async {
    final app_models.User? fresh;
    try {
      fresh = await _supabase.getUserProfile();
    } catch (e) {
      debugPrint('refreshUser failed, keeping last-known profile: $e');
      return;
    }
    _user = fresh;
    notifyListeners();
  }
}
