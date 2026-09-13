# Trading Titans — session record, 13 Sep 2026 (session 2)

Continues the 19-item work list. This session closed **3 items** (12, 9-client, E)
and got partway into **item F**. Read the previous handoff for items already done
before this session; nothing listed there as done was touched.

## Environment

- Workspace: `c:\Users\manav\startups\Trading-Titans` (Windows, PowerShell)
- Branch: **`upto14sep`** — now **6 commits, working tree clean**
- Supabase project ref: **`bftvimnhpoiuoyryyiff`**

```
7936027  feat(auth): tell a banned user why, in a dialog rather than 13px of red text
8ad5c18  feat(notifications): make a system-tray push tap go somewhere
bda0894  feat(location,analytics): country and state pickers, platform recording, admin breakdown
ce7e5f7  feat(chart): rectangle, fibonacci and arc drawing tools, plus pivot points
48f935a  feat(chart): OHLC on tap, remembered timeframe and style, dead default period
657b7bb  fix(notifications,leaderboard): untappable rows, wrong CTA target, owners on the board
be40037  chore: snapshot all work through 14 Sep 2026   <-- origin/upto14sep IS STILL HERE
```

**Only `be40037` is pushed.** The three new commits are local. `git push origin
upto14sep` needs interactive browser auth the user must complete himself. Ask
before pushing.

Verification state at the end of this session: `flutter analyze` clean,
`flutter test` **480 passed** (was 468 at session start, +12 new).

```powershell
cd app;   $env:PATH="C:\flutter\bin;$env:PATH"; flutter test; flutter analyze
cd chart; npm run typecheck; npm test; npm run build:app
cd web;   npm run typecheck
```

Note: `chart` and `web` were **not** re-verified this session — nothing in either
was touched.

---

## Done this session

### Item 12 — location, platform, admin analytics. COMPLETE. (`bda0894`)

The server half (`20260913000200_country_state_and_platform.sql`) was already
applied to production before this session; it was **untracked** and is now
committed. Verified live: `save_user_preferences` has the six-arg signature,
`get_user_preferences`, `record_platform(p_platform text)` and
`admin_user_stats()` all exist.

Client work built:

- **`app/lib/core/countries.dart`** (new) — all 249 ISO 3166-1 alpha-2 codes plus
  India's 28 states and 8 union territories, as packed `CC=Name;…` strings parsed
  once on first use. Written in small appends as the previous handoff advised; the
  big-literal approach was not attempted.
- **`currency_service.dart`** — `countryCode` / `state` fields, persisted beside
  `_kLocation`, read in both `loadCached()` and `_refreshPreferences()`, cleared in
  `reset()`. New `setCountryAndState()`.
- **`supabase_service.dart`** — `countryCode` / `state` params on
  `saveUserPreferences()`, plus `recordPlatform()` and `getAdminUserStats()`.
- **`profile_screen.dart`** — the "Trading From" row now opens a searchable country
  picker, then a state picker for countries that ship a list. One reusable
  `_pickFromList()` sheet used twice. Onboarding's two-card step untouched.
- **`main.dart`** — `recordPlatform(platformTag())` in `_refreshSessionState()`.
- **`admin_analytics_screen.dart`** (new) — groups `admin_user_stats()` by its
  `dimension` column and never names one, so a dimension added server-side appears
  with no client release. Reachable from the existing `isAdmin` gate in
  `profile_screen.dart`.

**Two decisions worth not re-litigating:**

1. **`setLocation` was deleted.** It had exactly one caller, the coarse
   india/outside_india sheet that the country picker replaced. Keeping it would
   have been a back door around the server's derivation: `save_user_preferences`
   with only `p_location` set leaves `country_code` untouched, so a user could pick
   India and then flip residency, leaving the two contradicting each other — and
   residency is the sole input to the billing currency. Onboarding still records
   the coarse answer via `completeOnboarding`, which is safe because a brand new
   account has no country to contradict. **The migration's claim that "there is no
   path that sets one without the other" was not strictly true; deleting the client
   setter is what makes it true, with no further DB change.**
2. **`recordPlatform` is called from `_refreshSessionState`, not from push-token
   registration.** `_registerToken` only runs once FCM yields a token, so it would
   have missed every web user and everyone who declined notifications and counted
   them as having no platform — exactly the conflation the migration set out to
   fix. `platformTag()` sends `defaultTargetPlatform.name` (not
   `Platform.operatingSystem`, which does not exist on web) and lets the RPC
   lowercase and filter, so a desktop build reads as unknown rather than inflating
   Android.

**Checks left behind** in `app/test/preferences_test.dart`: the packed data is
asserted against the same shape the DB CHECK enforces (`^[A-Z]{2}$`), that all 249
parsed (a duplicate code would silently overwrite and show up only as a short
count), that subdivisions fit the 80-char column, and that
`TargetPlatform.{android,iOS}.name` still lowercase into what `record_platform`
accepts.

**Still outstanding for item 12 — the optional backfill.** Not applied; it is a
production data write and was never approved. 316 profiles currently have
`country_code`, `state` and `last_platform` all NULL.

```sql
update public.profiles set country_code = 'IN'
 where location = 'india' and country_code is null;   -- classifies 242 instantly
```
Honest because `location='india'` already means India. The 33 `outside_india` rows
cannot be guessed and stay NULL, which does not contradict their residency.
Until this runs, the analytics screen shows country/state/platform as 100%
"unknown" and only the residency breakdown carries data.

### Item 9 — push-tap deep linking. CLIENT COMPLETE, SERVER NOT APPLIED. (`8ad5c18`)

- Extracted the CTA switch out of `_NotificationsScreenState` into a top-level
  **`openNotificationCta(context, data, {fallbackToList})`** in
  `notifications_screen.dart`. `_openCta` delegates to it. One switch, one
  allow-list, so the in-app button and the tray tap cannot drift.
- `fallbackToList: true` makes an absent, unrecognised or `notifications` route
  open the notification list rather than swallow the tap. Most notifications carry
  no CTA at all, so without it the common case would still do nothing.
- All three tap paths wired in `notification_service.dart`:
  `onMessageOpenedApp` (background), `getInitialMessage()` (terminated — no stream
  event exists, the tap launched the process), and
  `onDidReceiveNotificationResponse` (foreground, where we post the local
  notification ourselves, so `showNotification` now takes an optional `payload`).
- `openPushTarget()` reuses **`parseActionData`** rather than a second JSON decoder
  — it already accepts a map or a string and is already covered by tests. Gives up
  silently when `AuthService.navigatorKey.currentContext` is null, because a
  launch-from-tap can arrive before the first frame and a dropped deep link beats a
  startup crash.
- `supabase/functions/push-notification/index.ts` forwards
  `action_data.{cta_route,cta_url,symbol,market}` into FCM `data` **under those
  exact key names**, so the client hands the map straight to the existing
  allow-list. `deno check` passes.

**The client half is safe as shipped.** Until the trigger forwards `action_data`, a
push carries no route and the tap opens the notification list, which is strictly
better than the current nothing.

**TWO PRODUCTION CHANGES STILL NEEDED AND NOT YET APPROVED** — see the section
below.

### Item E — ban wording. COMPLETE. (`7936027`)

- `mapAuthException` branches on `error.code == 'user_banned'` **first**, before the
  generic credentials message. Ordering is load-bearing: if the credentials branch
  won, a banned user would retype a correct password forever. Also matches the
  message text, because `code` is only populated for errors that arrived on an HTTP
  response.
- `kBannedAccountMessage` is a named constant in `auth_service.dart` so the login
  screen can distinguish a ban from an ordinary failure. Shown **both** in a dialog
  and inline, so the reason survives dismissal and stays on the form.
- The three duplicated catch bodies in `login_screen.dart` collapsed into one
  `_failWith()`, which is where the ban check lives. Net less code.
- `AppConstants.supportEmail` added; `legal.dart`'s existing default now points at
  it instead of a second literal.

**Wording note — needs a yes/no.** The requested text was
*"your account have been banned due to violating t&c and exploiting features if you
think this is incorrect kindly email us at support@thetradingtitans.com"*. It
shipped grammatically corrected, with every element preserved:

> Your account has been banned for violating our Terms & Conditions and for
> exploiting features.
>
> If you believe this is incorrect, email us at support@thetradingtitans.com and we
> will look into it.

If the original phrasing was deliberate, change `kBannedAccountMessage` in
`app/lib/services/auth_service.dart` — the test asserts on keywords, not the exact
sentence, so it will still pass.

Verified against production: 11 accounts carry `banned_until`, all
`2999-12-31 23:59:59+00` (finite, not `'infinity'` which GoTrue cannot scan).

**Check left behind:** `app/test/banned_account_test.dart` — 7 tests, including
that the raw Supabase string never reaches the user and that the ban outranks the
credentials branch.

---

## APPROVAL NEEDED before item 9 works end to end

Both are production changes. Neither was applied.

### 9a. Forward `action_data` through the notification trigger

`public.push_on_notification_insert()` currently posts only
`user_id, title, body, action_type`, so `action_data` never reaches FCM.

The function **embeds the service_role key** in its Authorization header and is
deliberately uncommitted (see `20260709010000_push_on_notification_insert.sql`).
So it must be edited **server-side without reading the key out**. Probed
read-only and confirmed: `def_len` 828, the anchor text `'action_type', NEW.action_type`
is present, `action_data` is not yet mentioned, and exactly 1 non-internal trigger
uses it.

```sql
do $$
declare def text;
begin
  select pg_get_functiondef(p.oid) into def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'push_on_notification_insert';

  if def is null then raise exception 'trigger function missing'; end if;
  if position('action_data' in def) > 0 then
    raise notice 'already forwards action_data; nothing to do'; return;
  end if;

  def := replace(def,
    '''action_type'', NEW.action_type',
    '''action_type'', NEW.action_type, ''action_data'', NEW.action_data');

  if position('action_data' in def) = 0 then
    raise exception 'anchor not found; live body differs from the documented shape';
  end if;

  execute def;
end $$;
```

- **Affected objects:** `public.push_on_notification_insert()` body only. The
  trigger `trg_push_on_notification` is not recreated and keeps pointing at the
  same oid.
- **Why a DO block:** the service_role key never leaves Postgres. Do **not**
  `select pg_get_functiondef(...)` into the transcript.
- **Rollback:** re-run with the two arguments to `replace()` swapped.
- **Client compat:** additive. Shipped 1.2.3 ignores unknown FCM `data` keys.
- **Blast radius if it fails:** DDL inside a DO block is transactional and
  `create or replace` leaves the old body on error, so a failure is a no-op. The
  risk is a *successful* change with a malformed body, which would stop all push
  notifications — mitigated by the anchor assertion.
- **After applying:** insert one test notification with a `cta_route` in
  `action_data` and confirm it arrives with a route.

### 9b. Deploy the `push-notification` edge function

Source is committed and `deno check` passes. Not deployed.

```powershell
npx --yes supabase@latest functions deploy push-notification --project-ref bftvimnhpoiuoyryyiff
```

**Do NOT use `mcp_supabase_deploy_edge_function`** — per the previous handoff it
took `market-history` down when given placeholder file content.

Order does not matter: the function tolerates an absent `action_data`, and the
trigger sending one to an old function is ignored.

---

## Item F — migration drift. IN PROGRESS, file not yet written.

Confirmed drift: `20260907151036_notification_read_at_and_7day_purge.sql` exists
locally; **`20260909073537_current_tier_honours_cancel_at_period_end` does not.**
Both versions are in production's `supabase_migrations.schema_migrations`.

The live body was captured (read-only, no secrets in it). Compared against the
original in `20260902000000_payments_foundation.sql`, the change is: `current_tier`
gained a second OR branch so a **cancelled but still paid-up** subscription keeps
its tier, requiring a non-null future `current_period_end`. `halted` and `expired`
stay excluded.

Live definition, verbatim, to write into the file:

```sql
CREATE OR REPLACE FUNCTION public.current_tier(p_user_id uuid DEFAULT auth.uid())
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select coalesce((select s.tier from public.subscriptions s
     where s.user_id = p_user_id
       and (
         -- Running normally. A null period end is tolerated only here, because an
         -- active subscription is by definition still being paid for.
         (s.status in ('active','pending')
            and (s.current_period_end is null or s.current_period_end > now()))
         -- Cancelled but paid up. Requires a real future end date, so a
         -- cancellation on a mandate that was never charged grants nothing.
         --
         -- `halted` and `expired` stay out on purpose: a failed or finished mandate
         -- must not grant a tier. And because this is compared against now(), the
         -- grant expires on its own with no cron to forget to run.
         or (s.status = 'cancelled'
            and s.current_period_end is not null
            and s.current_period_end > now())
       )
     order by case s.tier when 'titan' then 2 when 'pro' then 1 else 0 end desc
     limit 1), 'free');
$function$
```

**Resolved question — do not re-investigate.** The live ACL is
`{postgres=X, anon=X, authenticated=X, service_role=X}`, which looks like it
disagrees with `20260902000000`'s `revoke from public; grant to authenticated,
service_role`. It does not. Supabase's default privileges grant `anon` execute at
creation time, and `revoke ... from PUBLIC` does not remove a grant held by the
`anon` role. A fresh database replaying the original migration reproduces the same
ACL. **So the captured file needs the body only — no `revoke`/`grant` statements,
and no `comment on function` (the original's comment is still accurate).**

Name the file exactly `20260909073537_current_tier_honours_cancel_at_period_end.sql`
so `supabase db push` skips it. It is documentation of production, never applied.

---

## Not started

- **Item 11 — public chat room.** Largest item. Decisions already made, do not
  re-ask: text + images + voice notes; **links admin-only, enforced server-side**
  (reject or strip URLs from non-admin inserts, not just in the UI); report button
  + admin delete + per-user mute, all three confirmed; voice notes capped at 60s;
  images compressed on device; Supabase Realtime for transport, Supabase Storage
  for media. Needs `chat_messages` with RLS (insert own, select all, no client
  update or delete), `chat_reports`, a mute mechanism, a bucket with size limits,
  admin-only delete. Entry point on the home screen next to the notification bell,
  `app/lib/screens/main/dashboard_screen.dart` ~line 289. The realtime transport is
  the easy part; URL enforcement and moderation are the actual work, and an
  unmoderated public room in a financial app is a real liability.
- **Item 17 + item 18's blog button.** Admins write in `kashiv_vault/` and publish
  to `thetradingtitans.com/<slug>`. Vercel. Needs images, links, and
  **server-rendered** so Google indexes it. **First establish whether `web/` or
  `website/` is the deployed marketing site** — that was not determined this
  session. Then add a `blog` destination in three places that must stay in step:
  `kAdminCtaDestinations` (`admin_reward_screen.dart:17`), `kNotificationCtaRoutes`
  and the `openNotificationCta` switch (both `notifications_screen.dart`).
  `app/test/notification_cta_test.dart` asserts every admin destination is
  routable, in two tests now — the original one and a push-round-trip one — so a
  mismatch fails the suite twice.
- **Item G — release 1.2.4. Do LAST.** `app/pubspec.yaml` is still `1.2.3+47`;
  bump **both** parts. `flutter test` and `flutter analyze` clean, then
  `flutter build appbundle --release`, write a ≤500-char "What's new", and run
  `python scripts/set_update_prompt.py` **only after** the Play rollout is live.

## Suggested order tomorrow

1. Get 9a + 9b approved and applied, then verify one push end to end
2. Write the item F file (definition is above, no further queries needed)
3. Decide on the item 12 backfill
4. Item 11, the chat room
5. Item 17 + 18's blog button
6. Item G, cut and ship 1.2.4

## Traps — still all live, plus one new

Everything in the previous handoff still applies. Especially:

- **`CREATE OR REPLACE VIEW` does not preserve `reloptions`.** Omitting
  `WITH (security_invoker = false)` silently reverts the view to caller RLS and
  empties the League tab for everyone. Shipped as a bug three times. Keep the
  assertion block at the end of `20260913000100_leaderboard_excludes_owners.sql`.
- **Do not drop `wallet_balance` from the `leaderboard` view.** Shipped 1.2.3
  selects it by name in both `supabase_service.dart` and `web/src/pages/Leaderboard.tsx`.
- **Multi-statement CTEs share one snapshot.** Use separate statements or a `DO`
  block ending in `RAISE EXCEPTION`.
- **PowerShell + MSYS git mangles Unix-looking arguments.** Use
  `git commit -F <messagefile>`. Used throughout this session; it works.
- **Never `mcp_supabase_deploy_edge_function` with placeholder content.**
- **`banned_until = 'infinity'` breaks GoTrue.** Use a finite far-future timestamp.
- **The owner-exclusion email list is duplicated** in `award_weekly_podium()` and
  the `leaderboard` view. Grep `pawan.2u2@gmail.com` and fix both.

**New this session:** the local `deno` on this machine is 2.1.4 and cannot read the
repo's lockfile version 5. Use `deno check --no-lock <file>` for type-checking.
`deno lint` in this build does **not** accept `--no-lock`, so lint has to be left
to CI, where it is advisory anyway.

Secrets remain correctly ignored — re-verified this session with
`git check-ignore -v` on `secrets/`, `app/android/key.properties`, `.env` and
`app/.env.special` before every `git add`. All files were staged by name, never
`git add -A`.
