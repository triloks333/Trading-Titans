import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import 'firebase_service.dart';

class RemoteConfigService {
  RemoteConfigService._internal();
  static final RemoteConfigService instance = RemoteConfigService._internal();

  final Map<String, dynamic> _defaults = {
    'enable_options_trading': true,
    'show_new_dashboard': false,
    'min_supported_version': '1.0.0',
  };

  Future<void> initialize() async {
    if (!FirebaseService.instance.isInitialized) {
      debugPrint('Skipping Remote Config init: Firebase not initialized.');
      return;
    }

    try {
      final remoteConfig = FirebaseRemoteConfig.instance;

      await remoteConfig.setDefaults(_defaults);

      await remoteConfig.setConfigSettings(RemoteConfigSettings(
        fetchTimeout: const Duration(seconds: 10),
        minimumFetchInterval: const Duration(hours: 12),
      ));

      // Fetch and activate configs
      await remoteConfig.fetchAndActivate();
      debugPrint('Firebase Remote Config successfully fetched and activated.');
    } catch (e) {
      debugPrint('Failed to fetch Remote Config. Using client defaults. Error: $e');
    }
  }

  bool get enableOptionsTrading {
    if (!FirebaseService.instance.isInitialized) return _defaults['enable_options_trading'] as bool;
    return FirebaseRemoteConfig.instance.getBool('enable_options_trading');
  }

  bool get showNewDashboard {
    if (!FirebaseService.instance.isInitialized) return _defaults['show_new_dashboard'] as bool;
    return FirebaseRemoteConfig.instance.getBool('show_new_dashboard');
  }

  String get minSupportedVersion {
    if (!FirebaseService.instance.isInitialized) return _defaults['min_supported_version'] as String;
    return FirebaseRemoteConfig.instance.getString('min_supported_version');
  }
}
