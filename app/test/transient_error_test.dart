// Classification of transient vs. real errors for Crashlytics.
//
// This decides whether an error is filed as a crash. A Supabase 504 Gateway
// Timeout used to fall through every check and be reported fatal, which is how
// a routine server hiccup showed up as 15 crashes. The failure is silent in
// both directions — misclassify one way and crash metrics are fiction,
// misclassify the other way and real bugs get buried as non-fatals.

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:mobile/services/firebase_service.dart';

void main() {
  bool transient(Object e) => FirebaseService.isTransientNetworkError(e);

  // `details` defaults to something neutral so each case tests the status alone;
  // the classifier must not be keying off incidental text.
  PostgrestException pg(String? code, {String details = 'Bad Request'}) =>
      PostgrestException(message: '', code: code, details: details);

  group('server-side transients are not crashes', () {
    test('the reported 504 from PostgREST is transient', () {
      // The exact shape from the Crashlytics report:
      // PostgrestException(message: , code: 504, details: Gateway Timeout)
      expect(transient(pg('504', details: 'Gateway Timeout')), isTrue);
    });

    test('other gateway and overload statuses are transient', () {
      for (final code in ['408', '425', '429', '502', '503', '504', '522', '524']) {
        expect(transient(pg(code)), isTrue, reason: code);
      }
    });

    test('edge function, auth and storage failures use the same rule', () {
      expect(transient(const FunctionException(status: 504)), isTrue);
      expect(transient(const AuthException('boom', statusCode: '503')), isTrue);
      expect(
        transient(const StorageException('boom', statusCode: '504')),
        isTrue,
      );
    });

    test('a statement timeout arriving as a 500 is still transient', () {
      // PostgREST reports a cancelled statement as 500, so the status set alone
      // would miss it.
      expect(
        transient(PostgrestException(
          message: 'canceling statement due to statement timeout',
          code: '500',
        )),
        isTrue,
      );
    });
  });

  group('real failures stay fatal', () {
    test('a plain 500 is not excused', () {
      // A broken filter or function must still surface as a bug, so 500 is
      // deliberately absent from the transient set.
      expect(transient(pg('500')), isFalse);
    });

    test('client-side request errors are not transient', () {
      for (final code in ['400', '401', '403', '404', '409', '422', '42501']) {
        expect(transient(pg(code)), isFalse, reason: code);
      }
    });

    test('a missing or unparseable status is not transient', () {
      expect(transient(pg(null)), isFalse);
      expect(transient(PostgrestException(message: 'x', code: 'PGRST116')), isFalse);
    });

    test('an ordinary programming error is not transient', () {
      expect(transient(StateError('bad state')), isFalse);
      expect(transient(ArgumentError('nope')), isFalse);
    });
  });

  group('existing connectivity behaviour is unchanged', () {
    test('socket and DNS failures remain transient', () {
      expect(transient(const SocketException('failed host lookup')), isTrue);
      expect(transient(TimeoutException('slow')), isTrue);
      expect(transient(const HttpException('bad')), isTrue);
      expect(transient(Exception('Failed host lookup: supabase.co')), isTrue);
      expect(transient(Exception('ClientException: Connection reset')), isTrue);
    });
  });
}
