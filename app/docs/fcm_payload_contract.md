# FCM Payload Contract (Forward-Looking, Doc-Only)

> **Status: NOT WIRED TODAY.** This is a forward-looking contract. As of this
> writing there is **no FCM sender** in the system — no Supabase Edge Function,
> database trigger, or external service sends Firebase Cloud Messaging push
> notifications to the app (project `bftvimnhpoiuoyryyiff`). This document
> records what a **future** FCM sender **must** do so that server-delivered push
> notifications play the same per-category sounds as locally posted
> notifications. No client code is wired to this contract today; local
> (foreground/in-app) notification sounds work independently of it.

_Related requirements: 6.1, 6.2, 6.3, 6.4._

## Why this contract exists

The client (`app/lib/services/notification_service.dart`) maps each
`NotificationCategory` to a dedicated Android `NotificationChannel` id and an iOS
sound file via its internal `_categoryConfig` table. An Android channel's sound
is fixed at channel-creation time, so the **only** way a push notification can
play a category's sound is for the sender to target that category's existing
channel id. iOS sounds are chosen per-notification via the APNs `sound` field.

Therefore, when an FCM sender eventually exists, it **must** populate the push
payload from the same per-category mapping the client uses:

- **Android:** set the notification payload `channel_id` (the
  `AndroidNotification.channel_id` / `android.notification.channel_id` field) to
  the channel id mapped to the notification's category. The resulting
  `channel_id` must be **identical** to the channel the client uses for a locally
  posted notification of the same category (Requirement 6.1).
- **iOS (APNs):** set the APNs `sound` field to the iOS sound file mapped to the
  notification's category. The resulting sound value must be **identical** to the
  sound the client uses locally for the same category (Requirement 6.2).

If both client and sender draw from the table below, the audible experience is
consistent whether the app is open or closed.

## Per-category mapping

This table mirrors the client's `_categoryConfig` in
`app/lib/services/notification_service.dart`. The sender **must** keep these
values in sync with that table.

| Category        | Android `channel_id`        | iOS APNs `sound`       |
|-----------------|-----------------------------|------------------------|
| `orderExecuted` | `order_executed_channel_v1` | `order_executed.caf`   |
| `orderPending`  | `order_pending_channel_v1`  | `order_pending.caf`    |
| `orderFailed`   | `order_failed_channel_v1`   | `order_failed.caf`     |
| `priceAlert`    | `price_alert_channel_v1`    | `price_alert.caf`      |
| `broadcast`     | `broadcast_channel_v1`      | `broadcast.caf`        |
| `reward`        | `reward_channel_v1`         | `reward.caf`           |

## Default for unmapped / unrecognized categories

If a future FCM sender sends a notification whose category has **no** mapped
Android channel or **no** mapped iOS sound (an unrecognized or uncategorized
notification), it **must** fall back to the designated default values rather than
dropping the notification or sending an empty value (Requirement 6.4):

- Android `channel_id` = `broadcast_channel_v1`
- iOS APNs `sound` = `"default"`

This guarantees the notification is still delivered with an audible default. The
`broadcast` category is the client's designated default category, so this aligns
server-side defaults with the client's local default behavior.

## Notes

- This contract is **conditional** on a sender existing. Where no FCM sender
  exists, the app still applies per-category sounds for locally posted
  notifications (Requirement 6.3); nothing here is required for that to work.
- The Android `channel_id` values are versioned (`*_channel_v1`). Because an
  Android channel's sound is immutable after creation, re-sounding a category in
  the future means introducing a new channel id (e.g. `*_channel_v2`) on the
  client **and** updating this table so the sender targets the new id.
- iOS sound file names use the `.caf` extension here to match the client's
  bundled sound slots. Supported iOS formats are `.caf` / `.aiff` / `.wav`
  (≤ 30 s).
- When a sender is built, update this document to remove the "NOT WIRED" status
  and link to the sender implementation.
