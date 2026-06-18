# iOS Notification Sound Assets (Runner bundle)

This document describes the **user-supplied** custom notification sounds for the
iOS build of Trading Titans. On iOS, a notification's sound is selected
per-notification by file name, and the file must be bundled in the **Runner**
app target.

> These audio files are **not** committed to the repository and are **not**
> fabricated by the build. The app is fully build-safe and functional without
> them: when a sound file is absent (or in an unsupported format), iOS falls
> back to the **default alert sound** and the notification is still delivered.
> Nothing crashes.

## How iOS resolves the sound

`NotificationService` posts each notification with an iOS sound reference of
`<base name>.caf` for its category. iOS looks for a sound file with that exact
name in the app bundle (the Runner target). If the file is missing or cannot be
played, iOS uses the default notification sound.

## Supported formats

iOS custom notification sounds support:

- `.caf` (Core Audio Format — recommended; the names below use `.caf`)
- `.aiff`
- `.wav`

Constraints:

- Maximum duration **30 seconds**. Longer clips fall back to the default sound.
- Place the files at the top level of the Runner target so they resolve by
  bare file name.

## Sound-asset slots

Add a file named `<base name>.caf` (or `.aiff` / `.wav`) to the Runner target
for each category you want a custom sound for. Slots not filled use the default
alert sound. The iOS sound reference column is what `NotificationService` passes
to the notification.

| Category       | Base name        | iOS sound reference | iOS file (add to Runner) |
|----------------|------------------|---------------------|--------------------------|
| Order Executed | `order_executed` | `order_executed.caf` | `order_executed.caf` (or `.aiff` / `.wav`) |
| Order Pending  | `order_pending`  | `order_pending.caf`  | `order_pending.caf` (or `.aiff` / `.wav`)  |
| Order Failed   | `order_failed`   | `order_failed.caf`   | `order_failed.caf` (or `.aiff` / `.wav`)   |
| Price Alert    | `price_alert`    | `price_alert.caf`    | `price_alert.caf` (or `.aiff` / `.wav`)    |
| Broadcast (default) | `broadcast` | `broadcast.caf`     | `broadcast.caf` (or `.aiff` / `.wav`)      |
| Reward         | `reward`         | `reward.caf`         | `reward.caf` (or `.aiff` / `.wav`)         |

## How to add a sound to the Runner target in Xcode

1. Open `app/ios/Runner.xcworkspace` in Xcode.
2. In the Project Navigator, select the **Runner** group (the folder that
   contains `Info.plist`, `AppDelegate.swift`, etc.).
3. Drag the audio file (e.g. `order_executed.caf`) into the Runner group, or
   use **File → Add Files to "Runner"…**.
4. In the add-file dialog, enable **Copy items if needed**, and under
   **Add to targets** make sure **Runner** is checked.
5. Confirm the file appears under **Target → Runner → Build Phases → Copy
   Bundle Resources**. If it is not listed there, add it manually so it ships in
   the app bundle.
6. Repeat for each category sound you want to customize.

> Tip: to convert an existing audio file to `.caf`, use Apple's `afconvert`,
> e.g. `afconvert input.wav order_executed.caf -d ima4 -f caff -v` (keep the
> clip under 30 seconds).

## Fallback behavior (summary)

- **File present, supported format, ≤ 30 s** → the custom sound plays.
- **File absent** → the default alert sound plays; no error is returned to the
  caller.
- **File present but unsupported format or too long** → the default alert sound
  plays; no error is returned to the caller.

The corresponding Android raw resource slots are documented in
`app/android/app/src/main/res/raw/README.md`.
