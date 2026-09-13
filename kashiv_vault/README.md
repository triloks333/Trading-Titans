# KASHIVWEALTH MANAGEMENT VAULT

A separate Flutter Android application for company documents, personal records,
credentials, signatures, links, images, team roles, search, and audit activity.
It intentionally reuses the Trading Titans Supabase project while isolating all
vault data with `kv_` tables and `kv-*` private Storage buckets.

## Implemented MVP

- Supabase email authentication with owner/invite-only membership
- Four declared founders pre-provisioned as owners
- Owner, admin, member, and viewer permissions enforced by PostgreSQL RLS
- Company and personal document upload, download/preview, categories, tags,
  favorites, search, expiry dates, and protected Storage paths
- Password vault with company/personal scopes, generator, strength meter,
  show/hide, copy, edit, and delete
- Digital signatures by drawing, PNG upload, or camera capture
- Shared links and shared image albums
- Typo-tolerant global search across every module
- Dashboard, storage totals, expiry summary, activity log, team invitations,
  light/dark themes, and biometric prompt
- Material 3 premium UI and responsive layouts

## Deliberate access model

This is a **company-managed vault**, not a zero-knowledge consumer password
manager. The UI discloses that owners can inspect company and personal vault
records, matching the requested owner-oversight policy. Data is protected by
TLS, Supabase provider disk encryption, private buckets, authenticated sessions,
and row-level policies. Users must not store credentials unless they accept this
administrative-access model.

## Run

```powershell
cd kashiv_vault
C:\flutter\bin\flutter.bat pub get
C:\flutter\bin\flutter.bat run
```

The default configuration targets Supabase project `bftvimnhpoiuoyryyiff`.
Use `--dart-define=SUPABASE_URL=...` and
`--dart-define=SUPABASE_ANON_KEY=...` to override it.

## Backend migrations

Vault migrations are in the repository-level `supabase/migrations/` directory,
starting at `20260728000000_kashivwealth_vault_schema.sql`.

## Not yet production-complete

FCM requires registering Android package `com.kashivwealth.vault` in the shared
Firebase project; the current Firebase account returned HTTP 403 for app
management. OCR, PDF signature insertion, version restore, offline sync, AI
summaries/organization, approval workflows, QR sharing, bulk operations,
watermarks, 2FA/device revocation, and automated expiry jobs remain later phases.
Do not market this MVP as end-to-end encrypted or enterprise-certified.

## Google authentication callback

The application uses Supabase Google OAuth exclusively. Add this exact URL in
**Supabase Dashboard → Authentication → URL Configuration → Redirect URLs**:

`io.supabase.kashivvault://login-callback/`

Google is already used by Trading Titans in the same Supabase project. The
Google Cloud authorized web callback remains:

`https://bftvimnhpoiuoyryyiff.supabase.co/auth/v1/callback`
