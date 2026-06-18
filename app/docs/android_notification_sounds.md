# Android Custom Notification Sounds

Custom per-category notification sounds are loaded from Android's
`res/raw/` resource directory. Filenames in `res/raw/` may only contain
lowercase letters `a-z`, digits `0-9`, and underscores. No uppercase, spaces,
or extensions other than the audio file itself.

## Sound slots (base names)

Drop an audio file (`.ogg` preferred, or `.mp3`) into
`android/app/src/main/res/raw/` using one of these base names:

| Base name        | Notification category |
|------------------|-----------------------|
| `order_executed` | Order executed        |
| `order_pending`  | Order placed/pending  |
| `order_failed`   | Order failed/rejected |
| `price_alert`    | Price alerts          |
| `broadcast`      | Broadcast/announcements |
| `reward`         | Rewards               |

Path: `android/app/src/main/res/raw/<base_name>.ogg`

## Fallback behavior

If a sound file is absent for a category, the notification falls back to the
default system notification sound. The `res/raw/` directory may be empty — the
app does not require any custom sound files to function.

## Notes

- Keep audio short (under ~5 seconds) and small.
- After adding/removing files, rebuild the app so resources are bundled.
