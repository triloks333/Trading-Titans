import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

class FirebaseService {
  FirebaseService._internal();
  static final FirebaseService instance = FirebaseService._internal();

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  /// Returns true for transient connectivity errors (no internet, DNS lookup
  /// failure, dropped sockets, token refresh while offline). These are not
  /// real crashes and should not be reported as fatal to Crashlytics.
  static bool isTransientNetworkError(Object error) {
    if (error is SocketException) return true;
    if (error is HttpException) return true;
    if (error is HandshakeException) return true;
    if (error is TimeoutException) return true;

    final text = error.toString().toLowerCase();
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

  Future<void> initialize() async {
    try {
      await Firebase.initializeApp();
      _isInitialized = true;

      if (!kIsWeb) {
        FlutterError.onError = (FlutterErrorDetails details) {
          if (isTransientNetworkError(details.exception)) {
            // Log as non-fatal so it doesn't surface as a crash.
            FirebaseCrashlytics.instance.recordFlutterError(details, fatal: false);
          } else {
            FirebaseCrashlytics.instance.recordFlutterFatalError(details);
          }
        };
        PlatformDispatcher.instance.onError = (error, stack) {
          final transient = isTransientNetworkError(error);
          FirebaseCrashlytics.instance.recordError(error, stack, fatal: !transient);
          return true;
        };
      }
      debugPrint('Firebase successfully initialized.');
    } catch (e) {
      debugPrint('Firebase failed to initialize. Running in Supabase-only mode. Error: $e');
    }
  }
}
