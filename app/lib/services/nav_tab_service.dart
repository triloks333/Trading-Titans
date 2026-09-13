import 'package:flutter/foundation.dart';

/// Lets any screen request the bottom navigation switch to a specific tab,
/// used by empty-state CTAs like "Place your first trade" → Trade tab.
///
/// MainNavigation listens to [tabRequest] and applies the index. Tab indices:
/// 0 Home, 1 Trade, 2 Portfolio, 3 Wallet, 4 League, 5 Profile.
///
/// Always reference these by name. League was inserted ahead of Profile, which
/// moved Profile from 4 to 5 — a literal `goToTab(4)` anywhere would silently
/// have started opening the wrong screen. The constants are what made that
/// insertion safe, and the clamp in `MainNavigation._onTabRequest` has to keep
/// pace with [count].
class NavTabService {
  NavTabService._();

  static const int home = 0;
  static const int trade = 1;
  static const int portfolio = 2;
  static const int wallet = 3;
  static const int league = 4;
  static const int profile = 5;

  /// Number of tabs. The clamp on incoming requests is derived from this rather
  /// than hardcoded, so adding a destination cannot leave it unreachable.
  static const int count = 6;

  static final ValueNotifier<int> tabRequest = ValueNotifier<int>(-1);

  static void goToTab(int index) {
    // Reset then set so repeated requests to the same tab still notify.
    tabRequest.value = -1;
    tabRequest.value = index;
  }
}
