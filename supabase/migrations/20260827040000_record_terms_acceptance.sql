-- Record that a user accepted the Terms & Conditions and Privacy Policy.
--
-- The sign-in and sign-up screens now require a consent checkbox before an
-- account can be created. A checkbox whose result is not stored cannot be
-- evidenced later, which is most of the point of asking, so acceptance is
-- persisted with the version of the documents that was accepted.
--
-- Version is `LegalDocs.termsVersion`, which is the policy revision date
-- ('August 17, 2026'). Storing it rather than a bare boolean means a future
-- revision can be detected and re-consent asked for, instead of us knowing only
-- that someone once ticked a box against unknown text.
--
-- WHY AN RPC AND NOT A DIRECT UPDATE
-- Migration 20260827000000 revoked UPDATE on public.profiles from anon and
-- authenticated, after finding that clients could set their own is_admin and
-- wallet_balance. A direct client write here would now fail with "permission
-- denied for table profiles". SECURITY DEFINER is therefore required, not a
-- stylistic choice, and it matches how every other profile write already works
-- (save_user_preferences, credit_demo_cash, touch_login_streak, ...).
--
-- The function takes only the version and derives the user from auth.uid(), so a
-- caller cannot record consent on someone else's behalf.
alter table public.profiles
  add column if not exists terms_accepted_at timestamptz,
  add column if not exists terms_version text;

comment on column public.profiles.terms_accepted_at is
  'When the user accepted the Terms & Conditions and Privacy Policy. NULL for accounts created before the consent checkbox shipped (app 1.1.8).';
comment on column public.profiles.terms_version is
  'Revision of the documents accepted, matching LegalDocs.termsVersion in the app.';

create or replace function public.accept_terms(p_version text)
returns timestamptz
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
declare
  v_uid uuid := auth.uid();
  v_now timestamptz := now();
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;

  if p_version is null or length(trim(p_version)) = 0 then
    raise exception 'terms version is required';
  end if;

  -- First acceptance wins for a given version: re-running must not move the
  -- timestamp, because the app calls this after account creation and the Google
  -- path retries on the OAuth round-trip. Accepting a NEWER version does update,
  -- so a future re-consent is recorded properly.
  update public.profiles
  set terms_accepted_at = v_now,
      terms_version = p_version
  where id = v_uid
    and (terms_accepted_at is null or coalesce(terms_version, '') <> p_version);

  select terms_accepted_at into v_now
  from public.profiles where id = v_uid;

  return v_now;
end;
$$;

-- Callable by signed-in users only. anon has no account to record against, and
-- the security advisor flags DEFINER functions left executable by anon.
revoke all on function public.accept_terms(text) from public, anon;
grant execute on function public.accept_terms(text) to authenticated;
