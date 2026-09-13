import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Registers this device's FCM token against the signed-in member so the
/// `kv_notifications` trigger can push to the phone tray even when the app is
/// closed.
///
/// ponytail: no local-notification plugin. Android draws the tray notification
/// itself from the FCM `notification` payload while the app is backgrounded or
/// terminated, which is the case that matters. Ceiling: a message arriving while
/// the app is in the foreground updates the in-app list only; add
/// flutter_local_notifications if a heads-up banner is wanted there too.
class PushService {
  PushService(this.client);
  final SupabaseClient client;

  Future<void> register() async {
    final user = client.auth.currentUser;
    if (user == null) return;

    try {
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission();

      final token = await messaging.getToken();
      if (token != null) await _save(user.id, token);

      messaging.onTokenRefresh.listen((refreshed) {
        final current = client.auth.currentUser;
        if (current != null) _save(current.id, refreshed);
      });
    } catch (error) {
      // Push is an enhancement: never block sign-in on it.
      debugPrint('Push registration skipped: $error');
    }
  }

  Future<void> _save(String userId, String token) async {
    try {
      await client.from('kv_devices').upsert({
        'user_id': userId,
        'device_label': _label(),
        'platform': Platform.operatingSystem,
        'fcm_token': token,
        'last_seen_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'user_id,device_label');
    } catch (error) {
      debugPrint('Could not store push token: $error');
    }
  }

  String _label() {
    try {
      return '${Platform.operatingSystem} ${Platform.operatingSystemVersion}'
          .trim();
    } catch (_) {
      return 'device';
    }
  }
}
