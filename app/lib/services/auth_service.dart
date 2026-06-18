import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'supabase_service.dart';
import '../models/user.dart' as app_models;
import 'dart:async';
import 'notification_service.dart';
import 'firebase_service.dart';
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

  Future<void> dismissSoftUpdate() async {
    _needsSoftUpdate = false;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('soft_update_dismissed_time', DateTime.now().millisecondsSinceEpoch);
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
      return prefs.getInt('soft_update_dismissed_time');
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
    final dismissedTs = await _readDismissedTimestamp();
    final config = await _supabase
        .getAppVersionConfig()
        .timeout(const Duration(seconds: 10));
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
      if (event == AuthChangeEvent.signedIn && session != null) {
        refreshUser();
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
    try {
      await _supabase.signIn(email: email, password: password);
      _user = await _supabase.getUserProfile();
      if (isAuthenticated) {
        unawaited(NotificationService.instance.setup());
        if (FirebaseService.instance.isInitialized) {
          unawaited(FirebaseAnalytics.instance.setUserId(id: _supabase.client.auth.currentUser!.id));
          unawaited(FirebaseCrashlytics.instance.setCustomKey('user_id', _supabase.client.auth.currentUser!.id));
        }
      }
      notifyListeners();
    } catch (e) {
      throw Exception(mapAuthException(e));
    }
  }

  Future<void> register(String email, String password, String name, {String? referralCode}) async {
    try {
      await _supabase.signUp(email: email, password: password, name: name, referralCode: referralCode);
      for (int i = 0; i < 5; i++) {
        _user = await _supabase.getUserProfile();
        if (_user != null) break;
        await Future.delayed(const Duration(milliseconds: 500));
      }
      if (isAuthenticated) {
        unawaited(NotificationService.instance.setup());
        if (FirebaseService.instance.isInitialized) {
          unawaited(FirebaseAnalytics.instance.setUserId(id: _supabase.client.auth.currentUser!.id));
          unawaited(FirebaseCrashlytics.instance.setCustomKey('user_id', _supabase.client.auth.currentUser!.id));
        }
      }
      notifyListeners();
    } catch (e) {
      throw Exception(mapAuthException(e));
    }
  }

  Future<void> signInWithGoogle() async {
    try {
      await _supabase.client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: 'io.supabase.tradingtitans://login-callback/',
      );
    } catch (e) {
      throw Exception(mapAuthException(e));
    }
  }

  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _supabase.client.auth.resetPasswordForEmail(
        email,
        redirectTo: 'io.supabase.tradingtitans://login-callback/',
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

  Future<void> refreshUser() async {
    _user = await _supabase.getUserProfile();
    notifyListeners();
  }
}
