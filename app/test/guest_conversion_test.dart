// Guest → permanent account upgrade.
//
// Two pure decisions are pinned here, both of which are wrong in a way that is
// invisible at a glance:
//
//   1. isGuestAccount() gates the whole upgrade CTA. If it answers "not a guest"
//      too early, the ₹6,000 offer disappears from a guest's Profile and the
//      feature silently stops existing for them.
//   2. mapConversionException() is the only thing standing between a user and a
//      dead end. Accounts are never merged, so when the email already belongs
//      to somebody the message has to tell them to sign in to that account —
//      the generic auth copy just says it "already exists" and leaves them
//      stuck mid-upgrade.
//
// The server side (the +₹6,000 being additive and payable once) is enforced by
// convert_guest_account() and verified against the live database, not here.

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/app_constants.dart';
import 'package:mobile/services/auth_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;

void main() {
  group('isGuestAccount', () {
    test('the JWT claim alone is enough', () {
      expect(
        isGuestAccount(
            supabaseIsAnonymous: true, profileEmail: 'someone@gmail.com'),
        isTrue,
      );
    });

    test('the placeholder email alone is enough', () {
      // The claim can already have flipped while convert_guest_account() has
      // not yet synced profiles.email. Keeping the CTA visible is what repairs
      // it, because tapping it re-runs the upgrade.
      expect(
        isGuestAccount(
          supabaseIsAnonymous: false,
          profileEmail: 'e5b1${AppConstants.guestEmailDomain}',
        ),
        isTrue,
      );
    });

    test('a real signed-in account is not a guest', () {
      expect(
        isGuestAccount(
            supabaseIsAnonymous: false, profileEmail: 'trader@gmail.com'),
        isFalse,
      );
    });

    test('an unknown session is not treated as a guest', () {
      // Nothing is known yet (no session, profile still loading). Offering an
      // upgrade to nobody is worse than offering it a moment later.
      expect(isGuestAccount(), isFalse);
      expect(isGuestAccount(supabaseIsAnonymous: null, profileEmail: null),
          isFalse);
    });

    test('a guest domain appearing mid-string does not count', () {
      expect(
        isGuestAccount(
          profileEmail: '${AppConstants.guestEmailDomain}.attacker@gmail.com',
        ),
        isFalse,
      );
    });
  });

  group('mapConversionException', () {
    test('an email that already has an account points at signing in', () {
      for (final raw in const [
        'A user with this email address has already been registered',
        'User already registered',
        'Email address already exists',
        'that address is already in use',
      ]) {
        final msg = mapConversionException(AuthException(raw));
        expect(msg, contains('already has a Trading Titans account'),
            reason: raw);
        expect(msg.toLowerCase(), contains('sign in'), reason: raw);
      }
    });

    test('an already-linked Google identity is named as such', () {
      final msg = mapConversionException(
          AuthException('Identity is already linked to another user'));
      expect(msg, contains('Google'));
      expect(msg.toLowerCase(), contains('sign out'));
    });

    test('manual linking being off does not blame the user', () {
      // Operator misconfiguration in the Supabase dashboard. Nothing the user
      // can do, so it must not read like their mistake.
      final msg =
          mapConversionException(AuthException('Manual linking is disabled'));
      expect(msg, contains('temporarily unavailable'));
      expect(msg.toLowerCase(), isNot(contains('email address')));
    });

    test('anything else falls through to the shared auth copy', () {
      expect(
        mapConversionException(AuthException('Password should be at least 6')),
        mapAuthException(AuthException('Password should be at least 6')),
      );
    });

    test('a plain thrown Exception is still readable', () {
      final msg = mapConversionException(
          Exception('Please enter a valid email address.'));
      expect(msg, contains('valid email address'));
      expect(msg, isNot(contains('Exception')));
    });
  });
}
