import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'diagnostics_service.dart';

class FirebaseService {
  FirebaseService._internal();
  static final FirebaseService instance = FirebaseService._internal();

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  /// HTTP statuses meaning "the server, or a hop in front of it, was busy or
  /// slow" rather than "the request was wrong". Retrying later is the correct
  /// response, so these must not be reported as crashes.
  ///
  /// 500 is deliberately absent: PostgREST returns it for genuine server-side
  /// faults (a malformed filter, a broken function) and excusing it would hide
  /// real bugs. Statement timeouts that surface as a 500 are caught by the
  /// 'statement timeout' text check instead.
  static const Set<int> _transientHttpStatus = {
    408, // Request Timeout
    425, // Too Early
    429, // Too Many Requests
    502, // Bad Gateway
    503, // Service Unavailable
    504, // Gateway Timeout
    522, // Cloudflare: connection timed out
    524, // Cloudflare: a timeout occurred
  };

  /// Parses a status carried as either an `int` or a `String` (Postgrest, GoTrue
  /// and Storage all report it as a nullable String; Functions uses an int).
  static bool _isTransientStatus(Object? raw) {
    if (raw == null) return false;
    final code = raw is int ? raw : int.tryParse(raw.toString().trim());
    return code != null && _transientHttpStatus.contains(code);
  }

  /// Returns true for transient connectivity errors (no internet, DNS lookup
  /// failure, dropped sockets, token refresh while offline) and for server-side
  /// hiccups (gateway timeouts, rate limits). These are not real crashes and
  /// should not be reported as fatal to Crashlytics.
  static bool isTransientNetworkError(Object error) {
    if (error is SocketException) return true;
    if (error is HttpException) return true;
    if (error is HandshakeException) return true;
    if (error is TimeoutException) return true;

    // Server-side transients. These are COMPLETED round trips carrying an error
    // status, not socket failures, so every check below missed them and a
    // Supabase gateway timeout was filed as a fatal crash.
    if (error is PostgrestException && _isTransientStatus(error.code)) return true;
    if (error is FunctionException && _isTransientStatus(error.status)) return true;
    if (error is AuthException && _isTransientStatus(error.statusCode)) return true;
    if (error is StorageException && _isTransientStatus(error.statusCode)) return true;

    final text = error.toString().toLowerCase();
    // A cancelled Postgres statement arrives as a 500, which the status set
    // deliberately excludes, so it needs naming explicitly. Kept narrow on
    // purpose: matching 'gateway timeout' anywhere in the text also excused a
    // 400 whose details merely mentioned it, and every real gateway failure
    // already carries a 502/503/504 status handled above.
    if (text.contains('statement timeout')) return true;

    return text.contains('socketexception') ||
        text.contains('failed host lookup') ||
        text.contains('clientexception') ||
        text.contains('connection closed') ||
        text.contains('connection reset') ||
        text.contains('connection refused') ||
        text.contains('network is unreachable') ||
        text.contains('software caused connection abort') ||
        text.contains('authretryablefetchexception') ||
        text.contains('errno = 7') ||
        text.contains('errno = 8');
  }

  /// Attaches the last database call as a Crashlytics custom key. Best-effort
  /// and never throws, so it can't turn a reported error into a second one.
  static Future<void> _attachDbContext() async {
    try {
      await FirebaseCrashlytics.instance
          .setCustomKey('last_db_call', DiagnosticsService.dbContext());
    } catch (_) {}
  }

  Future<void> initialize() async {
    try {
      await Firebase.initializeApp();
      _isInitialized = true;

      if (!kIsWeb) {
        FlutterError.onError = (FlutterErrorDetails details) {
          // Name the query before reporting. recordFlutterError takes no
          // `reason`, so this goes through a custom key; it is best-effort,
          // which is why the onError path below uses `reason` instead.
          unawaited(_attachDbContext());
          if (isTransientNetworkError(details.exception)) {
            // Log as non-fatal so it doesn't surface as a crash.
            FirebaseCrashlytics.instance.recordFlutterError(details, fatal: false);
          } else {
            FirebaseCrashlytics.instance.recordFlutterFatalError(details);
          }
        };
        PlatformDispatcher.instance.onError = (error, stack) {
          final transient = isTransientNetworkError(error);
          FirebaseCrashlytics.instance.recordError(
            error,
            stack,
            // Set synchronously as part of this call, so it cannot lose a race
            // with the report being written.
            reason: DiagnosticsService.dbContext(),
            fatal: !transient,
          );
          return true;
        };
      }
      debugPrint('Firebase successfully initialized.');
    } catch (e) {
      debugPrint('Firebase failed to initialize. Running in Supabase-only mode. Error: $e');
    }
  }
}
