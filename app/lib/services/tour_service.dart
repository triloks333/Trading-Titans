import 'package:flutter/foundation.dart';

/// Lightweight coordinator for replaying the interactive app tour from screens
/// other than the dashboard (where the tour actually lives).
///
/// Flow: a caller (e.g. Profile) sets the `pending_tour_replay` flag in
/// SharedPreferences and calls [requestReplay]. MainNavigation listens to
/// [goHomeTick] and switches to the Home tab, which recreates the dashboard;
/// the dashboard then reads the flag on load and starts the tour.
class TourService {
  TourService._();

  /// Incremented whenever a tour replay is requested. MainNavigation listens
  /// to this to bring the user back to the Home tab.
  static final ValueNotifier<int> goHomeTick = ValueNotifier<int>(0);

  static void requestReplay() => goHomeTick.value++;
}
