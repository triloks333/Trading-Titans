import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../screens/main/notifications_screen.dart'
    show openNotificationCta, parseActionData;
import 'auth_service.dart' show AuthService;
import 'chat_service.dart';
import 'firebase_service.dart';

/// Classifies a notification so it can be mapped to a dedicated Android
/// channel and an iOS sound file. Exactly seven values; [broadcast] is the
/// designated default category (R1.1, R1.3).
enum NotificationCategory {
  orderExecuted,
  orderPending,
  orderFailed,
  priceAlert,
  broadcast, // default
  reward,
  chat,
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
    NotificationCategory.chat: _CategoryConfig(
      androidChannelId: 'chat_channel_v1',
      androidChannelName: 'Titans Room',
      androidChannelDescription: 'Notifications for Titans Room chat messages',
      soundName: 'broadcast',
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
      // Covers the foreground case only. A push that arrives while the app is
      // open is posted by us as a local notification (see the onMessage handler),
      // so the OS routes its tap here rather than through FirebaseMessaging.
      onDidReceiveNotificationResponse: (response) async {
        if (response.actionId == 'chat_reply') {
          final replyText = response.input;
          if (replyText != null && replyText.trim().isNotEmpty) {
            try {
              await ChatService.instance.sendText(replyText.trim());
            } catch (e) {
              debugPrint('Direct reply error: $e');
            }
          }
          return;
        }
        if (response.actionId == 'chat_mark_read') {
          final id = response.id;
          if (id != null) {
            await _notificationsPlugin.cancel(id: id);
          }
          return;
        }
        if (response.actionId == 'chat_mute_8h') {
          await ChatService.muteNotificationsFor(const Duration(hours: 8));
          final id = response.id;
          if (id != null) {
            await _notificationsPlugin.cancel(id: id);
          }
          return;
        }
        openPushTarget(response.payload);
      },
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

    // Web has no flutter_local_notifications implementation, and browser push
    // would additionally need a service worker plus a VAPID key. Everything
    // below this line is therefore mobile-only.
    //
    // Nothing is lost in-app: the notifications *list* is read from the
    // public.notifications table, so a web user still sees every alert. Only the
    // OS-level tray push is absent.
    //
    // The Firebase guard below would already stop the FCM half of this method on
    // web (Firebase.initializeApp() has no options for web, so it self-disables
    // and isInitialized stays false), but _initLocalNotifications() runs ahead
    // of it and would throw MissingPluginException.
    if (kIsWeb) {
      debugPrint('Skipping Notification Service setup: not supported on web.');
      return;
    }

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

      // 4. Foreground push handler: when a push arrives while the app is open,
      // Android/iOS do NOT show it in the tray automatically — they deliver it
      // here. Post it as a local notification so EVERY push appears in the
      // system tray regardless of app state. (Background/terminated pushes are
      // shown automatically by the OS.)
      FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
        final notif = message.notification;
        final data = message.data;
        final title = (notif?.title ?? data['title'] ?? '').trim();
        final body = (notif?.body ?? data['body'] ?? '').trim();
        if (title.isEmpty && body.isEmpty) return;

        final category = categoryFromType(data['type']);
        if (category == NotificationCategory.chat) {
          final isEveryone = data['is_everyone'] == 'true' ||
              data['is_everyone'] == true ||
              data['tag'] == '@everyone';
          if (ChatService.isChatRoomActive) {
            debugPrint('Suppressing chat notification: user is active in chatroom.');
            return;
          }
          if (!isEveryone && await ChatService.isChatMuted()) {
            debugPrint('Suppressing chat notification: chat is muted.');
            return;
          }
        }

        showNotification(
          id: (message.messageId ?? DateTime.now().microsecondsSinceEpoch.toString()).hashCode,
          title: title.isEmpty ? 'Trading Titans' : title,
          body: body,
          category: category,
          // Carried through so the tap can route. Without it, a push that landed
          // while the app was open would open nothing when tapped.
          payload: jsonEncode(data),
        );
      });

      // 5. Tap handling. Two separate paths, and both are needed:
      //   - onMessageOpenedApp fires when the app was in the BACKGROUND and the
      //     OS-drawn notification is tapped.
      //   - getInitialMessage covers a TERMINATED app: the tap is what launched
      //     the process, so there is no stream event to listen for, only this one
      //     message waiting to be collected.
      // The foreground case is the local-notification callback in
      // _initLocalNotifications.
      FirebaseMessaging.onMessageOpenedApp.listen((message) {
        openPushTarget(message.data);
      });
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) openPushTarget(initial.data);

    } catch (e) {
      debugPrint('Error setting up Notification Service: $e');
    }
  }

  /// Opens whatever a tapped notification pointed at.
  ///
  /// Takes either an FCM `data` map or a local-notification payload string —
  /// [parseActionData] already accepts both and returns null on anything
  /// unusable, which is exactly this job and is already covered by tests.
  ///
  /// The FCM `data` map deliberately reuses `action_data`'s key names
  /// (`cta_route`, `cta_url`, ...), so it can be handed straight to the same
  /// allow-list the in-app button uses instead of inventing a second routing
  /// contract. `fallbackToList: true` because a push tap has no notification list
  /// on screen, so an absent or unrecognised route should open the list rather
  /// than swallow the tap.
  ///
  /// Silently gives up when there is no navigator yet: a tap that launched the
  /// process can arrive before the first frame, and a dropped deep link is a much
  /// better outcome than a crash on startup.
  static void openPushTarget(Object? payloadOrData) {
    final context = AuthService.navigatorKey.currentContext;
    if (context == null) {
      debugPrint('openPushTarget: no navigator yet, ignoring tap');
      return;
    }
    openNotificationCta(context, parseActionData(payloadOrData),
        fallbackToList: true);
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
  /// [payload] is opaque to this method and handed back by the OS when the
  /// notification is tapped. Optional, so existing callers that post a purely
  /// informational notification are unchanged.
  Future<ShowNotificationResult> showNotification({
    required int id,
    required String title,
    required String body,
    NotificationCategory category = NotificationCategory.broadcast,
    String? payload,
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

    final List<AndroidNotificationAction>? chatActions = category == NotificationCategory.chat
        ? const [
            AndroidNotificationAction(
              'chat_reply',
              'Reply',
              inputs: [
                AndroidNotificationActionInput(
                  label: 'Type a reply...',
                ),
              ],
            ),
            AndroidNotificationAction(
              'chat_mark_read',
              'Mark as read',
              cancelNotification: true,
            ),
            AndroidNotificationAction(
              'chat_mute_8h',
              'Mute 8h',
              cancelNotification: true,
            ),
          ]
        : null;

    final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      resolved.androidChannelId,
      resolved.androidChannelName,
      channelDescription: resolved.androidChannelDescription,
      importance: Importance.max,
      priority: Priority.high,
      sound: RawResourceAndroidNotificationSound(resolved.soundName),
      ticker: 'ticker',
      actions: chatActions,
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

    // Post to the system tray. A missing/invalid custom sound resource makes
    // the plugin throw `invalid_sound`, which would otherwise prevent the
    // notification from ever appearing in the tray. So on any failure we retry
    // once WITHOUT a custom sound (the channel's default sound is used), which
    // guarantees the notification is delivered (R5.3, R5.4).
    try {
      await _notificationsPlugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: platformDetails,
        payload: payload,
      );
    } catch (e) {
      debugPrint('showNotification: custom-sound post failed ($e); retrying with default sound');
      final AndroidNotificationDetails fallbackAndroid = AndroidNotificationDetails(
        resolved.androidChannelId,
        resolved.androidChannelName,
        channelDescription: resolved.androidChannelDescription,
        importance: Importance.max,
        priority: Priority.high,
        ticker: 'ticker',
        actions: chatActions,
      );
      const DarwinNotificationDetails fallbackIos = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );
      try {
        await _notificationsPlugin.show(
          id: id,
          title: title,
          body: body,
          notificationDetails: NotificationDetails(android: fallbackAndroid, iOS: fallbackIos),
          payload: payload,
        );
      } catch (e2) {
        debugPrint('showNotification: fallback post also failed: $e2');
        return ShowNotificationResult(posted: false, usedFallbackCategory: usedFallbackCategory, error: 'post failed: $e2');
      }
    }

    return ShowNotificationResult(
      posted: true,
      usedFallbackCategory: usedFallbackCategory,
      error: error,
    );
  }

  /// The Android channel id mapped to [category].
  ///
  /// Must stay identical to the ids `channelFor()` in the `push-notification`
  /// edge function writes into `android.notification.channel_id`. If they drift,
  /// a background push lands on a channel the app never created and silently
  /// loses its custom sound.
  static String channelIdFor(NotificationCategory category) =>
      (_categoryConfig[category] ?? _categoryConfig[_defaultCategory]!)
          .androidChannelId;

  /// Maps a push `data.type` value to a notification category for channel/sound
  /// selection. Unknown/absent types fall back to the default (broadcast).
  ///
  /// Load-bearing: now that the app no longer posts its own order and price-alert
  /// notifications, the sound is decided entirely by the chain
  /// `notifications.action_type` -> `channelFor()` in the push-notification edge
  /// function -> `data.type` -> here.
  static NotificationCategory categoryFromType(String? type) {
    switch (type) {
      case 'price_alert':
        return NotificationCategory.priceAlert;
      case 'order':
      case 'order_executed':
        return NotificationCategory.orderExecuted;
      case 'order_pending':
        return NotificationCategory.orderPending;
      case 'order_failed':
        return NotificationCategory.orderFailed;
      case 'reward':
        return NotificationCategory.reward;
      case 'chat':
        return NotificationCategory.chat;
      default:
        return NotificationCategory.broadcast;
    }
  }

  void dispose() {
    _tokenRefreshSubscription?.cancel();
  }
}
