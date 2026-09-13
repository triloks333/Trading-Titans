// What a banned user is told when they try to sign in.
//
// The 11 accounts in the referral farm are banned at the GoTrue level
// (auth.users.banned_until), so their sign-in fails with a 400 and error_code
// `user_banned`. mapAuthException's last line is `return error.message`, which
// meant Supabase's own bare "User is banned" reached the login form as 13px of red
// text with no reason and no way to appeal.
//
// Tested as a pure function rather than by driving LoginScreen, which is the
// convention in this repo for auth-screen logic (see legal_consent_test.dart): the
// screen needs Supabase, Provider, Firebase analytics and Google Fonts to build,
// which is a lot of harness for a string decision.

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/app_constants.dart';
import 'package:mobile/services/auth_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('mapAuthException on a banned account', () {
    test('the authoritative error code is recognised', () {
      expect(
        mapAuthException(
            AuthException('User is banned', statusCode: '400', code: 'user_banned')),
        kBannedAccountMessage,
      );
    });

    test('the bare message is recognised even with no code', () {
      // `code` is only populated for errors that came back on an HTTP response,
      // so the message match is the fallback rather than decoration.
      expect(mapAuthException(AuthException('User is banned')), kBannedAccountMessage);
    });

    test('the raw Supabase string never reaches the user', () {
      // THE REGRESSION. mapAuthException ends in `return error.message`, so
      // without a branch this is exactly what the login form displayed.
      final shown = mapAuthException(
          AuthException('User is banned', statusCode: '400', code: 'user_banned'));
      expect(shown, isNot('User is banned'));
      expect(shown.length, greaterThan('User is banned'.length));
    });

    test('the copy gives a reason and somewhere to appeal', () {
      final copy = kBannedAccountMessage.toLowerCase();
      expect(copy, contains('banned'));
      expect(copy, contains('terms'));
      expect(copy, contains('exploiting'));
      // A dead end with no address is the thing this replaced.
      expect(kBannedAccountMessage, contains(AppConstants.supportEmail));
    });

    test('the ban outranks the credentials message', () {
      // Ordering matters: if the generic "Incorrect email or password" branch won,
      // a banned user would retype a correct password forever. GoTrue has sent
      // credentials-shaped copy alongside this code before.
      expect(
        mapAuthException(AuthException('Invalid login credentials',
            statusCode: '400', code: 'user_banned')),
        kBannedAccountMessage,
      );
    });

    test('an ordinary wrong password is untouched', () {
      expect(
        mapAuthException(AuthException('Invalid login credentials')),
        'Incorrect email or password. Please try again.',
      );
    });

    test('an unrelated auth error is untouched', () {
      expect(
        mapAuthException(AuthException('Email not confirmed')),
        'Please verify your email address before signing in.',
      );
    });
  });
}
