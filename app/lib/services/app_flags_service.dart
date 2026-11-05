import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Database-backed feature flags, read from the `app_flags` table.
///
/// Flipping a row in the Supabase dashboard turns a surface on or off for
/// everyone on the next app launch or foreground — no release needed. Reads are
/// open to any signed-in user; writes are admin-only via RLS.
///
/// Defaults are deliberately the *safe* value, so a failed fetch keeps paid
/// surfaces hidden rather than exposing them.
class AppFlagsService extends ChangeNotifier {
  AppFlagsService._internal();
  static final AppFlagsService instance = AppFlagsService._internal();

  static const Map<String, bool> _defaults = {
    'monetization_enabled': false,
    'us_stocks_enabled': false,
  };

  Map<String, bool> _flags = Map.of(_defaults);
  bool _loaded = false;

  bool get isLoaded => _loaded;

  bool isEnabled(String key) => _flags[key] ?? _defaults[key] ?? false;

  /// True when wallet top-ups, the Subscribe screen and plan badges should be
  /// visible. The app is free while this is false.
  bool get monetizationEnabled => isEnabled('monetization_enabled');

  /// True when the US Stocks market tab should load real data instead of
  /// showing the "Coming soon" state.
  bool get usStocksEnabled => isEnabled('us_stocks_enabled');

  /// Sets one flag in memory only, for widget tests.
  @visibleForTesting
  void debugSetFlag(String key, bool value) {
    _flags = {..._flags, key: value};
    notifyListeners();
  }

  Future<void> refresh() async {
    try {
      final rows = await Supabase.instance.client
          .from('app_flags')
          .select('key, enabled');
      final next = Map.of(_defaults);
      for (final row in rows as List<dynamic>) {
        final map = Map<String, dynamic>.from(row as Map);
        final key = map['key'] as String?;
        if (key != null) next[key] = map['enabled'] == true;
      }
      _flags = next;
      _loaded = true;
      notifyListeners();
    } catch (e) {
      // Keep whatever we had (defaults on first run). Never fail open.
      debugPrint('AppFlagsService.refresh failed, keeping defaults: $e');
    }
  }
}
