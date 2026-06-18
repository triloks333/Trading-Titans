import 'dart:async';
import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'firebase_service.dart';

/// Classifies a notification so it can be mapped to a dedicated Android
/// channel and an iOS sound file. Exactly six values; [broadcast] is the
/// designated default category (R1.1, R1.3).
enum NotificationCategory {
  orderExecuted,
  orderPending,
  orderFailed,
  priceAlert,
  broadcast, // default
  reward,
}

/// Per-category configuration mapping a [NotificationCategory] to its Android
/// channel identity and the base name of its sound asset (R1.2, R5.1).
///
/// [soundName] is the base file name without extension; it resolves to an
/// Android raw resource and an iOS `<soundName>.caf` bundled file.
class _CategoryConfig {
  final String androidChannelId;
  final String androidChannelName;
  final String androidChannelDescription;
  final String soundName;

  const _CategoryConfig({
    required this.androidChannelId,
    required this.androidChannelName,
    required this.androidChannelDescription,
    required this.soundName,
  });
}

/// Outcome of a [NotificationService.showNotification] call. Communicates
/// success/failure to call sites without throwing (R2.5, R2.6).
class ShowNotificationResult {
  /// False only when the call was rejected due to invalid input.
  final bool posted;

  /// True when the requested category was unmapped and the default was used.
  final bool usedFallbackCategory;

  /// Human-readable reason naming the offending parameter/category, if any.
  final String? error;

  const ShowNotificationResult({
    required this.posted,
    this.usedFallbackCategory = false,
    this.error,
  });
}

class NotificationService {
  NotificationService._internal();
  static final NotificationService instance = NotificationService._internal();
  factory NotificationService() => instance;

  StreamSubscription<String>? _tokenRefreshSubscription;
  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();
  bool _isLocalInitialized = false;

  /// Guards against re-creating channels more than once per process (R4.3).
  bool _channelsEnsured = false;

  /// The default category applied when a caller does not specify one (R1.3).
  static const NotificationCategory _defaultCategory = NotificationCategory.broadcast;

  /// Total mapping from every [NotificationCategory] to its channel/sound
  /// configuration. Channel ids are versioned (`*_channel_v1`) because an
  /// Android channel's sound is immutable after creation (R1.2, R4.4, R5.1).
  static const Map<NotificationCategory, _CategoryConfig> _categoryConfig = {
    NotificationCategory.orderExecuted: _CategoryConfig(
      androidChannelId: 'order_executed_channel_v1',
      androidChannelName: 'Order Executed',
      androidChannelDescription: 'Notifications for executed orders',
      soundName: 'order_executed',
    ),
    NotificationCategory.orderPending: _CategoryConfig(
      androidChannelId: 'order_pending_channel_v1',
      androidChannelName: 'Order Pending',
      androidChannelDescription: 'Notifications for pending orders',
      soundName: 'order_pending',
    ),
    NotificationCategory.orderFailed: _CategoryConfig(
      androidChannelId: 'order_failed_channel_v1',
      androidChannelName: 'Order Failed',
      androidChannelDescription: 'Notifications for failed orders',
      soundName: 'order_failed',
    ),
    NotificationCategory.priceAlert: _CategoryConfig(
      androidChannelId: 'price_alert_channel_v1',
      androidChannelName: 'Price Alerts',
      androidChannelDescription: 'Notifications for price alerts',
      soundName: 'price_alert',
    ),
    NotificationCategory.broadcast: _CategoryConfig(
      androidChannelId: 'broadcast_channel_v1',
      androidChannelName: 'Announcements',
      androidChannelDescription: 'General announcements and broadcasts',
      soundName: 'broadcast',
    ),
    NotificationCategory.reward: _CategoryConfig(
      androidChannelId: 'reward_channel_v1',
      androidChannelName: 'Rewards',
      androidChannelDescription: 'Notifications for rewards',
      soundName: 'reward',
    ),
  };

  Future<void> _initLocalNotifications() async {
    if (_isLocalInitialized) return;

    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings initializationSettingsDarwin =
        DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsDarwin,
    );

    await _notificationsPlugin.initialize(
      settings: initializationSettings,
    );

    _isLocalInitialized = true;

    // Create one Android channel per category once the plugin is ready (R4).
    await _ensureChannels();
  }

  /// Creates one Android [AndroidNotificationChannel] per [NotificationCategory]
  /// the first time it runs, then no-ops on subsequent calls (R4.1).
  ///
  /// Existing channels (matched by id) are reused without mutation, since an
  /// Android channel's sound is immutable after creation (R4.3, R4.4). Each
  /// channel creation is isolated in its own try/catch so a single failure does
  /// not abort the loop (R4.6); on a sound-resolution failure the channel is
  /// recreated with the platform default sound as a best-effort fallback
  /// (R5.2). On non-Android platforms this returns early.
  Future<void> _ensureChannels() async {
    if (_channelsEnsured) return;

    final AndroidFlutterLocalNotificationsPlugin? android = _notificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) {
      // Non-Android platform; nothing to create.
      _channelsEnsured = true;
      return;
    }

    // Collect the ids of channels that already exist so we can skip them
    // (reuse, do not recreate or mutate — R4.3).
    final Set<String> existingIds = <String>{};
    try {
      final existing = await android.getNotificationChannels();
      if (existing != null) {
        for (final channel in existing) {
          existingIds.add(channel.id);
        }
      }
    } catch (e) {
      debugPrint('Failed to query existing notification channels: $e');
    }

    for (final entry in _categoryConfig.entries) {
      final config = entry.value;

      // Skip channels that already exist (R4.3).
      if (existingIds.contains(config.androidChannelId)) {
        continue;
      }

      final AndroidNotificationChannel channel = AndroidNotificationChannel(
        config.androidChannelId,
        config.androidChannelName,
        description: config.androidChannelDescription,
        importance: Importance.max,
        sound: RawResourceAndroidNotificationSound(config.soundName),
      );

      // Each channel creation is isolated so one failure does not abort the
      // loop (R4.6).
      try {
        await android.createNotificationChannel(channel);
      } catch (e) {
        debugPrint(
            'Failed to create channel ${config.androidChannelId} with custom '
            'sound: $e');
        // Best-effort: retry without a custom sound so the category still has a
        // usable channel using the platform default sound (R5.2).
        try {
          final AndroidNotificationChannel fallbackChannel =
              AndroidNotificationChannel(
            config.androidChannelId,
            config.androidChannelName,
            description: config.androidChannelDescription,
            importance: Importance.max,
          );
          await android.createNotificationChannel(fallbackChannel);
        } catch (e2) {
          debugPrint(
              'Failed to create fallback channel '
              '${config.androidChannelId}: $e2');
        }
      }
    }

    _channelsEnsured = true;
  }

  Future<void> setup() async {
    assert(
      _categoryConfig.length == NotificationCategory.values.length,
      '_categoryConfig must have exactly one entry per NotificationCategory',
    );
    await _initLocalNotifications();

    if (!FirebaseService.instance.isInitialized) {
      debugPrint('Skipping Notification Service setup: Firebase not initialized.');
      return;
    }

    try {
      final messaging = FirebaseMessaging.instance;

      // 1. Request permissions (especially on iOS)
      final settings = await messaging.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        debugPrint('User granted push notification permissions.');
      } else {
        debugPrint('User declined or restricted push notification permissions.');
      }

      // 2. Fetch and register initial token
      final token = await messaging.getToken();
      if (token != null) {
        await _registerToken(token);
      }

      // 3. Configure token rotation listener
      _tokenRefreshSubscription?.cancel();
      _tokenRefreshSubscription = messaging.onTokenRefresh.listen((newToken) {
        _registerToken(newToken);
      });

    } catch (e) {
      debugPrint('Error setting up Notification Service: $e');
    }
  }

  Future<void> _registerToken(String token) async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;
    if (user == null) {
      debugPrint('User not signed in. Skipping token sync.');
      return;
    }

    final platformStr = Platform.isIOS ? 'ios' : 'android';

    try {
      await supabase.from('push_tokens').upsert({
        'user_id': user.id,
        'token': token,
        'platform': platformStr,
        'last_seen_at': DateTime.now().toUtc().toIso8601String(),
        'is_active': true,
      }, onConflict: 'token');
      debugPrint('Push token registered successfully.');
    } catch (e) {
      debugPrint('Failed to save push token to database: $e');
    }
  }

  /// Posts a local notification using the channel/sound mapped to [category].
  ///
  /// Validates required input: an empty/whitespace [title] or [body] is
  /// rejected and nothing is posted (R2.6). When [category] resolves to no
  /// configuration, the [_defaultCategory] mapping is used and the result
  /// flags the fallback (R1.5, R2.5). The [id], [title], and [body] are passed
  /// through unchanged (R2.4). Absent or wrong-format sound assets never
  /// surface an error to the caller; the platform default sound is used and the
  /// post still completes (R5.3, R5.4).
  Future<ShowNotificationResult> showNotification({
    required int id,
    required String title,
    required String body,
    NotificationCategory category = NotificationCategory.broadcast,
  }) async {
    // Validate required input (R2.6). Reject and post nothing.
    if (title.trim().isEmpty) {
      return const ShowNotificationResult(posted: false, error: 'missing title');
    }
    if (body.trim().isEmpty) {
      return const ShowNotificationResult(posted: false, error: 'missing body');
    }

    await _initLocalNotifications();

    // Resolve config; fall back to the default category when unmapped (R1.4,
    // R1.5, R2.5).
    var usedFallbackCategory = false;
    String? error;
    var config = _categoryConfig[category];
    if (config == null) {
      usedFallbackCategory = true;
      error = 'unrecognized category: ${category.name}';
      config = _categoryConfig[_defaultCategory];
    }
    // _categoryConfig is total over the enum, so the default always resolves.
    final resolved = config!;

    final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      resolved.androidChannelId,
      resolved.androidChannelName,
      channelDescription: resolved.androidChannelDescription,
      importance: Importance.max,
      priority: Priority.high,
      sound: RawResourceAndroidNotificationSound(resolved.soundName),
      ticker: 'ticker',
    );

    final DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      sound: '${resolved.soundName}.caf',
    );

    final NotificationDetails platformDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notificationsPlugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: platformDetails,
    );

    return ShowNotificationResult(
      posted: true,
      usedFallbackCategory: usedFallbackCategory,
      error: error,
    );
  }

  void dispose() {
    _tokenRefreshSubscription?.cancel();
  }
}
