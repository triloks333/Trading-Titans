# Trading Titans 1.2.4 (versionCode 48)

Artifact: `app/build/app/outputs/bundle/release/app-release.aab` (47.5 MB)
Verified before build: `flutter test` 491 passed, `flutter analyze` clean.
Bundle carries `versionName=1.2.4`, `versionCode=48`.

## Play Store "What's new" (paste verbatim, 374 characters)

```
• Titans Room: a public chat for every trader — text and photos, with moderation.
• Tapping a notification now opens the right screen instead of doing nothing.
• New chart tools: rectangle, Fibonacci, arc and pivot points. Tap any candle for its OHLC.
• Your chart timeframe and style are remembered between sessions.
• Set your country and state in Settings.
```

## After the rollout reaches users

Per `.kiro/steering/release-process.md` section 3, the in-app update prompt is
driven by `app_config.latest_version`, not by the binary. Until it is raised the
soft window is empty and **nobody is prompted**.

```powershell
python scripts/set_update_prompt.py          # reads app/pubspec.yaml
python scripts/set_update_prompt.py --show   # verify
```

Run it **after** the Play rollout is live, never before. Leave
`min_supported_version` alone — that is the hard block, not the reminder.

## Not in this build, deliberately

- **Voice notes in the chat room.** The database, storage bucket and
  `ChatService.sendVoice()` all accept them, but no recorder ships: `legal.dart:302`
  promises users "no microphone or camera access beyond a photo you deliberately
  choose to upload". Adding a microphone makes that false, and because
  `termsVersion == lastUpdated`, updating the policy re-prompts every existing user
  for consent and must stay in step with `web/src/lib/legal.ts`. A voice message
  posted by a future build renders as a placeholder rather than a blank bubble.

## Server-side state this build depends on

All already applied and verified in production:

- `action_data` is forwarded by `push_on_notification_insert()` and by
  `push-notification` edge function v5, which is what makes the notification tap
  land somewhere.
- Chat tables, RLS, the insert gate trigger, `chat_feed` and the `chat-media`
  bucket.
- `blog_posts` plus the `blog-media` bucket.

## Still needs a deploy that requires credentials I do not have

- `git push origin upto14sep` — interactive browser auth.
- `website/` Vercel deploy, which is what turns on `/blog` and `/blog/<slug>`. The
  app's Blog CTA destination points at `thetradingtitans.com/blog` and will 404
  until that deploy happens.
