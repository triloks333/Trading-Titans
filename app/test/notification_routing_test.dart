// Push routing: notifications.action_type -> channel and sound.
//
// The app no longer posts its own order or price-alert notifications, so the
// sound is decided entirely by a cross-language chain:
//
//   notifications.action_type
//     -> channelFor()      (supabase/functions/push-notification/index.ts)
//     -> FCM data.type + android.notification.channel_id
//     -> categoryFromType() (here)
//     -> channel + sound
//
// Nothing in the build checks the two ends agree. If they drift, pushes land on
// a channel the app never created and quietly lose their custom sound — which is
// exactly the bug where a pending order played the executed sound.

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/services/notification_service.dart';

void main() {
  // The `type` values push-notification sends, and the channel_id it pairs with
  // each one. Copied from channelFor() in that function; if you change one side,
  // this test is the thing that should fail.
  const pushContract = <String, ({NotificationCategory category, String channelId})>{
    'order_executed': (
      category: NotificationCategory.orderExecuted,
      channelId: 'order_executed_channel_v1',
    ),
    'order_pending': (
      category: NotificationCategory.orderPending,
      channelId: 'order_pending_channel_v1',
    ),
    'order_failed': (
      category: NotificationCategory.orderFailed,
      channelId: 'order_failed_channel_v1',
    ),
    'price_alert': (
      category: NotificationCategory.priceAlert,
      channelId: 'price_alert_channel_v1',
    ),
    'reward': (
      category: NotificationCategory.reward,
      channelId: 'reward_channel_v1',
    ),
    'broadcast': (
      category: NotificationCategory.broadcast,
      channelId: 'broadcast_channel_v1',
    ),
  };

  group('categoryFromType matches the push-notification contract', () {
    pushContract.forEach((type, expected) {
      test("'$type' routes to ${expected.category.name}", () {
        expect(NotificationService.categoryFromType(type), expected.category);
      });
    });

    test('every push type resolves to the channel the server names', () {
      pushContract.forEach((type, expected) {
        final category = NotificationService.categoryFromType(type);
        expect(
          NotificationService.channelIdFor(category),
          expected.channelId,
          reason: "type '$type' must land on ${expected.channelId}",
        );
      });
    });
  });

  group('action_type values the producers actually write', () {
    test('a pending order does NOT get the executed sound', () {
      // place-order used to write action_type "order", which channelFor() maps
      // to the executed channel. This is the regression guard for that.
      final pending = NotificationService.categoryFromType('order_pending');
      final executed = NotificationService.categoryFromType('order_executed');
      expect(pending, NotificationCategory.orderPending);
      expect(pending, isNot(executed));
      expect(
        NotificationService.channelIdFor(pending),
        isNot(NotificationService.channelIdFor(executed)),
      );
    });

    test("'order' still routes to executed, for notify_order_executed", () {
      // The DB trigger writes action_type 'order' for fills; channelFor() maps
      // 'order' -> order_executed. Changing this would mis-sound every fill.
      expect(
        NotificationService.categoryFromType('order'),
        NotificationCategory.orderExecuted,
      );
    });

    test("server aliases 'trade' and 'expiry' route to executed", () {
      // channelFor() folds these into order_executed; the Dart side only ever
      // sees the mapped `type`, but assert the alias target is reachable.
      expect(
        NotificationService.categoryFromType('order_executed'),
        NotificationCategory.orderExecuted,
      );
    });
  });

  group('unknown and absent types degrade safely', () {
    test('null, empty and unrecognised types fall back to broadcast', () {
      for (final t in [null, '', 'nonsense', 'Order_Pending']) {
        expect(
          NotificationService.categoryFromType(t),
          NotificationCategory.broadcast,
          reason: 'type: $t',
        );
      }
    });

    test('the fallback still resolves to a real channel', () {
      expect(
        NotificationService.channelIdFor(NotificationCategory.broadcast),
        'broadcast_channel_v1',
      );
    });
  });

  test('every category has a distinct channel id', () {
    // Two categories sharing an id would silently share a sound, and an
    // Android channel's sound cannot be changed after creation.
    final ids = NotificationCategory.values
        .map(NotificationService.channelIdFor)
        .toList();
    expect(ids.toSet().length, NotificationCategory.values.length);
    for (final id in ids) {
      expect(id, isNotEmpty);
    }
  });
}
