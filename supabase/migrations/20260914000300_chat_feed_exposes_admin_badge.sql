-- Admins get a visible tag in the chat room.
--
-- Applied to production as version 20260914040250
-- (name `chat_feed_exposes_admin_badge`).
--
-- ── THIS REVERSES A DELIBERATE EARLIER DECISION ────────────────────────────
-- chat_feed was created explicitly WITHOUT is_admin (20260914000000, section 9),
-- reasoning that "a public room must not become a way to enumerate who the admins
-- are", with an assertion that failed the migration if the column appeared.
--
-- That was the right default and it is now overridden by an explicit product
-- decision: a moderator badge only works if it is public, and users being able to
-- tell who speaks for Trading Titans is the entire point. Recorded rather than
-- quietly deleted so the next person does not "fix" it back.
--
-- Driven by profiles.is_admin, which is already true for exactly the three intended
-- accounts (Pawan, Trilok, Manav). Deliberately NOT a fourth hardcoded copy of the
-- owner email list — award_weekly_podium() and the leaderboard view already carry
-- two, and the standing note is to stop adding more.
--
-- Note this is is_admin, not owner: manavagg2003@gmail.com is a secondary OWNER
-- account but is not an admin, so it gets no tag. That matches the request, which
-- named three people.
--
-- ── AFFECTED OBJECTS ───────────────────────────────────────────────────────
--   public.chat_feed   +author_is_admin
--
-- ── THE WITH CLAUSE IS STILL LOAD-BEARING ──────────────────────────────────
-- `create or replace view` does not preserve reloptions. Dropping
-- `with (security_invoker = false)` here would revert the view to caller RLS, and
-- because profiles is own-row-only that would blank every author name except your
-- own — the same failure this view exists to prevent. Asserted below.
--
-- ── CLIENT COMPATIBILITY ───────────────────────────────────────────────────
-- Additive column, so any build selecting named columns is unaffected.
--
-- ── ROLLBACK ───────────────────────────────────────────────────────────────
-- Recreate the view without author_is_admin, KEEPING the WITH clause.

create or replace view public.chat_feed
  with (security_invoker = false) as
  select m.id,
         m.user_id,
         m.kind,
         m.body,
         m.media_path,
         m.duration_ms,
         m.created_at,
         p.name                          as author_name,
         public.current_tier(m.user_id)  as author_tier,
         coalesce(p.is_admin, false)     as author_is_admin
    from public.chat_messages m
    join public.profiles p on p.id = m.user_id
   where m.deleted_at is null;

comment on view public.chat_feed is
  'Read path for the public chat room: messages joined to their author''s display '
  'name, paid tier and admin flag. MUST stay security_invoker = false — profiles is '
  'own-row-only, so with caller RLS every author name except your own goes blank. '
  'author_is_admin is exposed ON PURPOSE so the room can show a moderator tag; '
  'email and wallet_balance are still deliberately absent. Soft-deleted messages are '
  'filtered here because the underlying select policy is bypassed. READ ONLY: writes '
  'are revoked, and the linter''s security_definer_view finding is expected and must '
  'NOT be "fixed".';

revoke insert, update, delete on public.chat_feed from anon, authenticated;
revoke select on public.chat_feed from anon;
grant select on public.chat_feed to authenticated;

do $$
begin
  if (select reloptions::text from pg_class where relname = 'chat_feed')
       is distinct from '{security_invoker=false}' then
    raise exception 'chat_feed lost security_invoker=false; author names will go blank';
  end if;
  if has_table_privilege('authenticated', 'public.chat_feed', 'UPDATE')
     or has_table_privilege('anon', 'public.chat_feed', 'UPDATE') then
    raise exception 'chat_feed is writable through PostgREST';
  end if;
  if has_table_privilege('anon', 'public.chat_feed', 'SELECT') then
    raise exception 'chat_feed readable signed out';
  end if;
  -- The tag is now intended. These two are still not.
  if exists (select 1 from information_schema.columns
              where table_schema='public' and table_name='chat_feed'
                and column_name in ('email','wallet_balance')) then
    raise exception 'chat_feed is leaking a sensitive profiles column';
  end if;
  if not exists (select 1 from information_schema.columns
                  where table_schema='public' and table_name='chat_feed'
                    and column_name = 'author_is_admin') then
    raise exception 'author_is_admin is missing; the admin tag will never show';
  end if;
  -- A guard, not a constraint: if this fires, someone gained admin unintentionally
  -- and would be wearing a moderator tag in a public room.
  if (select count(*) from public.profiles where coalesce(is_admin,false)) <> 3 then
    raise warning 'admin count is no longer 3 - check who is wearing the chat tag';
  end if;
end
$$;
