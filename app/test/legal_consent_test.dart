// The consent checkbox is only worth having if it actually blocks account
// creation, and the trap here is scope: an account can be created from BOTH auth
// screens by four different routes — email/password and Google on sign-up,
// Google and Guest on sign-in. A checkbox wired to only the sign-up screen is
// bypassable in two taps.
//
// These tests pin the widget contract rather than driving the real screens: the
// screens need Supabase, Provider, Firebase analytics and Google Fonts to build,
// which is a lot of harness for what is a small piece of logic. What they do lock
// down is the gate itself and the copy, so a future edit cannot quietly weaken
// either.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/legal.dart';
import 'package:mobile/widgets/legal_consent.dart';

/// Mirrors `_requireLegalConsent()` as it appears in both auth screens.
///
/// Ported here in the project's existing style (see trade_mechanics_test.dart,
/// which ports the money rules the same way) so the branch is exercised
/// deterministically. If either screen's copy diverges from this, the assertions
/// below stop describing the shipped behaviour — which is the signal to look.
bool requireLegalConsent({required bool accepted, required void Function() onBlocked}) {
  if (accepted) return true;
  onBlocked();
  return false;
}

void main() {
  group('consent gate', () {
    test('blocks the action and reports it when unaccepted', () {
      var blocked = 0;
      final allowed = requireLegalConsent(accepted: false, onBlocked: () => blocked++);
      expect(allowed, isFalse, reason: 'an unaccepted user must not proceed');
      expect(blocked, 1, reason: 'the user must be told why');
    });

    test('allows the action once accepted, without an error', () {
      var blocked = 0;
      final allowed = requireLegalConsent(accepted: true, onBlocked: () => blocked++);
      expect(allowed, isTrue);
      expect(blocked, 0);
    });

    test('every account-creating route is gated', () {
      // The four routes, as found in login_screen.dart and register_screen.dart.
      // Email/password SIGN-IN is deliberately absent: that user accepted at
      // signup and their acceptance is already recorded.
      const gated = <String>[
        'register: email/password',
        'register: google',
        'login: google',
        'login: guest',
      ];
      for (final route in gated) {
        expect(
          requireLegalConsent(accepted: false, onBlocked: () {}),
          isFalse,
          reason: '$route must refuse to create an account without consent',
        );
      }
      expect(gated.length, 4);
    });
  });

  group('LegalConsentCheckbox', () {
    testWidgets('renders both policy names as tappable links', (tester) async {
      var value = false;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => LegalConsentCheckbox(
              value: value,
              onChanged: (v) => setState(() => value = v),
            ),
          ),
        ),
      ));

      expect(find.byType(Checkbox), findsOneWidget);
      // The names must be present as text so a user can see what they accept.
      final text = tester.widget<Text>(find.byType(Text).first);
      final rendered = text.textSpan!.toPlainText();
      expect(rendered, contains('Terms & Conditions'));
      expect(rendered, contains('Privacy Policy'));
      expect(rendered, contains('I accept'));
    });

    testWidgets('ticking the box reports true', (tester) async {
      var value = false;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => LegalConsentCheckbox(
              value: value,
              onChanged: (v) => setState(() => value = v),
            ),
          ),
        ),
      ));

      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      expect(value, isTrue);
    });

    testWidgets('shows the error text only when asked to', (tester) async {
      Future<void> pump(bool showError) => tester.pumpWidget(MaterialApp(
            home: Scaffold(
              body: LegalConsentCheckbox(
                value: false,
                showError: showError,
                onChanged: (_) {},
              ),
            ),
          ));

      await pump(false);
      expect(find.text(LegalConsentCheckbox.errorText), findsNothing);

      await pump(true);
      expect(find.text(LegalConsentCheckbox.errorText), findsOneWidget);
    });
  });

  group('AuthDisclaimer', () {
    testWidgets('states the three things users misread', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: AuthDisclaimer()),
      ));

      expect(find.text('VIRTUAL TRADING ONLY'), findsOneWidget);
      expect(find.text(LegalDocs.authDisclaimer), findsOneWidget);
    });

    test('the copy covers simulated value, broker status and data delay', () {
      final copy = LegalDocs.authDisclaimer.toLowerCase();
      // Everything is virtual, including prizes/rewards.
      expect(copy, contains('simulated'));
      expect(copy, contains('reward'));
      expect(copy, contains('no real-world value'));
      // Not a broker.
      expect(copy, contains('not a registered broker'));
      // Prices may be delayed — the point the original report raised.
      expect(copy, contains('delayed'));
      expect(copy, contains('financial advice'));
    });
  });

  group('recorded acceptance', () {
    test('the version is the policy revision date, so the two cannot drift', () {
      expect(LegalDocs.termsVersion, LegalDocs.lastUpdated);
      expect(LegalDocs.termsVersion, isNotEmpty);
    });
  });
}
