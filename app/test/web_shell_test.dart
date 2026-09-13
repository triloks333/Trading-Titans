// Guards the mobile app against the web build's two shared entry points.
//
// Adding web support meant touching files Android compiles from. Both changes
// below are `kIsWeb` branches, and the failure mode if either branch is written
// the wrong way round is silent on web but severe on mobile: a phone-width
// letterbox inside a phone, or an OAuth redirect that no longer returns to the
// app.
//
// These tests run on the Dart VM, where kIsWeb is false, so they assert exactly
// the mobile behaviour.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/app_constants.dart';
import 'package:mobile/main.dart';
import 'package:mobile/screens/main/main_navigation.dart';
import 'package:mobile/services/nav_tab_service.dart';

void main() {
  group('webShell leaves mobile alone', () {
    test('returns the very same widget instance, not a wrapped copy', () {
      const child = SizedBox(key: Key('home'));
      // identical(), not equality: anything inserted above the Navigator on
      // mobile would change layout for every screen at once.
      expect(identical(webShell(child), child), isTrue);
    });

    test('a null child is still safe to build', () {
      // MaterialApp.builder is typed with a nullable child.
      expect(webShell(null), isA<Widget>());
    });

    testWidgets('does not constrain width on mobile', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => webShell(child),
          home: const Placeholder(),
        ),
      );

      // Full test-harness width, unconstrained by the web content cap.
      final size = tester.getSize(find.byType(Placeholder));
      expect(size.width, 800);
    });
  });

  group('navigation destinations', () {
    test('the shared list and the request clamp agree on the tab count', () {
      // The desktop sidebar and the mobile navbar both index into this list, and
      // MainNavigation clamps incoming deep links to 0..NavTabService.count-1.
      // A destination added here without that count moving would be unreachable
      // from a deep link, which is how League nearly shipped invisible.
      expect(kMainNavDests.length, NavTabService.count);
      expect(kMainNavDests.map((d) => d.label).toList(),
          ['Home', 'Trade', 'Portfolio', 'Wallet', 'League', 'Profile']);
    });

    test('the named indices point at the destination they claim to', () {
      // Inserting League ahead of Profile moved Profile from 4 to 5. Every call
      // site goes through these constants, so this is the assertion that would
      // have caught the insertion silently opening the wrong screen.
      expect(kMainNavDests[NavTabService.home].label, 'Home');
      expect(kMainNavDests[NavTabService.trade].label, 'Trade');
      expect(kMainNavDests[NavTabService.portfolio].label, 'Portfolio');
      expect(kMainNavDests[NavTabService.wallet].label, 'Wallet');
      expect(kMainNavDests[NavTabService.league].label, 'League');
      expect(kMainNavDests[NavTabService.profile].label, 'Profile');
    });
  });

  group('auth redirect', () {
    test('mobile keeps the custom scheme registered in AndroidManifest', () {
      // Swapping this for an https origin would break Google sign-in, the guest
      // upgrade and password reset on every installed phone.
      expect(AppConstants.authRedirectUrl,
          'io.supabase.tradingtitans://login-callback/');
    });
  });
}
