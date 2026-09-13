# 1.2.0 (version code 44)

## Play Store "What's new" — paste this into the release

```
• New League tab — a proper leaderboard showing your rank, the top three and everyone else
• Signing out on the web no longer signs you out on your phone
• Plans and top-ups redesigned, with live pricing and GST included
• PRO and TITAN badges now show beside your name on your profile and the League
• Cleaner bottom navigation with labels on every tab
• Updated Terms and Privacy Policy to cover optional paid plans, renewals and refunds
```

439 characters, inside the 500 limit. "No ads on any plan" belongs in the store
listing body rather than here, where the space is better spent on what changed.

## Version

`1.2.0+44`. The version name is 1.2 as requested; the build number moved from 43
to 44 because Play rejects any upload whose version code is not strictly greater
than the last one published (42, shipped as 1.1.9). Code 43 was only ever
sideloaded for testing and never uploaded, so 44 is the first Play build of 1.2.

## What actually changed

**League tab.** `CompeteScreen` had been written but never wired to anything — no
import, no route — so the leaderboard was unreachable in every shipped build. It is
now a primary destination, and it was rebuilt to the app's design system on the way
in: no AppBar (matching Wallet and Profile, and a tab has nothing to go back to), a
"your position" card as the focal point, TOP THREE / EVERYONE ELSE sections, initial
avatars, `TrendArrow` on every P&L so gain and loss do not rely on colour alone, a
shimmer skeleton while loading, and the app's `EmptyState` with a "Place a trade"
CTA instead of a centred grey sentence. The 🥇🥈🥉 emoji medals are gone: they
rendered differently on every device and matched nothing else in the app.

Two real bugs were fixed in the same pass. The future was constructed inline in the
`FutureBuilder`, so the list refetched and flashed its skeleton on every rebuild,
including a theme change. And the avatar initial used `name[0]`, which throws on a
blank display name — reachable, because `profiles.name` defaults to `''` — and split
surrogate pairs, so an emoji name rendered a broken glyph.

Adding the tab moved Profile from index 4 to 5; every call site already went through
`NavTabService`'s named constants, and the deep-link clamp now derives from
`NavTabService.count` instead of a literal, so a future destination cannot be added
and silently left unreachable. Tests assert each named index points at the
destination it claims.

**The leaderboard was also returning one row.** Separate from the UI: the
`public.leaderboard` view was in production with `security_invoker = on`, so it ran
with the caller's privileges and obeyed `profiles`' own-row-only RLS. Every user saw
a board containing only themselves, on web as well as mobile. Restored to
`security_invoker = false`, which is what `20260621000200_profiles_pii_lockdown.sql`
defines; verified back to 196 rows with `profiles` itself still returning one row.
That fix is server-side and already live.

**Cross-device sign-out.** Both clients called `signOut()` bare, and both SDKs
default to `scope: global`, which revokes every refresh token on the account. So
signing out of the web app ended the session on the phone, and vice versa. Both now
pass `scope: local`. Global sign-out remains the right tool after a password change
or suspected compromise — a separate, deliberate action.

**Bottom navigation.** The old bar showed icons only and expanded the selected one
to reveal its label. At six destinations that wanted roughly 400dp on a 360dp phone,
so it was being scaled down to fit and came out cramped. Replaced with equal fixed
slots and a small permanent label on every tab: it cannot overflow at any width, and
no destination is a guessing game.

**Plans screen.** Monthly plans only in the app, with annual on the website where
the monthly/annual toggle can show both side by side — the comparison is the whole
point of an annual price. Seven tall identical cards became two plan cards and three
one-line top-up rows. Prices, cash grants and stipends all come from
`plan_catalogue`; the screen this replaced hardcoded ₹199/₹599/₹999 Play Console
products that had already drifted from both the database and the web app.

**Plan badges from a real source.** The profile, wallet and League pills read
`profiles.plan` and `profiles.subscription_active`. Nothing has ever written either,
so every account displayed the literal string `free_starter`, and brand-new free
accounts were labelled "ACTIVE". All now read the tier derived from `subscriptions`
via `current_tier()`.

**Checkout URL.** The built-in fallback pointed at
`trading-titans-web.vercel.app/plans`, which began returning 404 when the web app
moved under `/app`. Now `thetradingtitans.com/app/plans`, verified
absent-and-replaced in the shipped binary.

**Terms and Privacy.** Rewritten for a product that sells something: what is sold,
GST-inclusive pricing, auto-renewal, how to cancel, and a real refund policy.
`TERMS_VERSION` moved to `September 2, 2026` in both clients.

## Release checklist

- [x] Version `1.2.0+44`
- [x] `flutter analyze` clean
- [x] `flutter test` — 443 passing
- [x] APK sideloaded and the League redesign reviewed
- [x] AAB built and release-signed
- [ ] Upload to Play Console, paste the "What's new" above, roll out
- [x] `app_config` read policy applied — the update prompt can now actually fire
- [ ] **After** the rollout reaches users, arm the prompt:
      `python scripts/set_update_prompt.py` then `--show` to verify
- [ ] Leave `min_supported_version` alone; it is the hard block, not the reminder

## The update prompt was dead — fixed

`app_config` had row level security enabled with **no policies**, so every client
read zero rows. Verified against production as `authenticated`:
`select count(*) from app_config` returned `0`.

That is the table `set_update_prompt.py` writes to, so the script would have
reported success while no user was ever prompted. The same gap silently disabled
`min_supported_version`, `maintenance_mode` and `update_url` — the whole remote
gating system had been inert.

Fixed by `20260902000300_app_config_readable_by_signed_in.sql`, applied:

```sql
create policy "Config is readable by everyone"
  on public.app_config for select using (true);
```

`using (true)` rather than `auth.uid() is not null`, which is what `app_flags` uses.
That distinction matters: `AuthService.initialize()` reads this table *before* it
loads the profile and before any auth check, so a signed-in-only policy would leave
the hard-update gate and the maintenance notice dead on the login screen — exactly
where they need to work. `app_flags` can be signed-in-only because every surface it
gates sits behind auth; this table cannot.

Verified after applying: 9 rows readable as `authenticated` and as `anon` (the
login-screen case), and writes still refused both ways — `insert` gives 42501,
`update` matches 0 rows. Confirmed over the real REST API too, which is the path the
app actually uses.

Regression probe after the change, all PASS: cannot forge a subscription (42501),
cannot call `apply_paid_topup` (42501), cannot rewrite a plan price (0 rows),
`profiles` still returns only your own row, cannot self-credit the wallet (42501),
and the leaderboard still returns 196 rows.

## Also outstanding

- **Rotate the Razorpay live secret.** It was pasted into chat and sits in
  `app/.env.special`; treat it as compromised, then update `RAZORPAY_KEY_SECRET` in
  Supabase.
- **Add `https://thetradingtitans.com/app` to Supabase → Authentication → URL
  Configuration → Redirect URLs**, or Google sign-in, email confirmation and
  password reset break on the web. Unverified: Supabase validates `redirect_to` at
  the callback stage, so it cannot be checked without completing a real login.
- **`anon` and `authenticated` hold TRUNCATE on 67 tables**, including `profiles`.
  Fix written to `20260902000200_revoke_truncate_from_clients.sql`, not applied.
- **The leaderboard is readable without signing in.** Pre-existing, not introduced
  by the view fix. One-line tightening noted at the bottom of
  `20260902000400_restore_leaderboard_visibility.sql`.
- **Have a lawyer read the refund and renewal terms** before charging anyone.
- `monetization_enabled` is currently `true`, so the paid surfaces in this build are
  live. Everything above should be settled before real money moves.
