import 'package:flutter/foundation.dart';

/// Lets any screen request the bottom navigation switch to a specific tab,
/// used by empty-state CTAs like "Place your first trade" → Trade tab.
///
/// MainNavigation listens to [tabRequest] and applies the index. Tab indices:
/// 0 Home, 1 Trade, 2 Portfolio, 3 Wallet, 4 Profile.
class NavTabService {
  NavTabService._();

  static const int home = 0;
  static const int trade = 1;
  static const int portfolio = 2;
  static const int wallet = 3;
  static const int profile = 4;

  static final ValueNotifier<int> tabRequest = ValueNotifier<int>(-1);

  static void goToTab(int index) {
    // Reset then set so repeated requests to the same tab still notify.
    tabRequest.value = -1;
    tabRequest.value = index;
  }
}
