-- The chat room and the blog could not be written to at all. THE BUG: sending a
-- message in the Titans Room failed with "That message could not be sent."
--
-- Applied to production as version 20260914035624
-- (name `chat_and_blog_explicit_write_grants`).
--
-- ── ROOT CAUSE ─────────────────────────────────────────────────────────────
-- 20260903000000_leaderboard_read_only_view.sql ends with
--
--   alter default privileges in schema public
--     revoke insert, update, delete, truncate on tables from anon, authenticated;
--
-- so EVERY table created in `public` since then arrives SELECT-only for clients.
-- The chat and blog migrations both defined RLS insert policies and assumed
-- Supabase's usual defaults would supply the table-level grant. They did not.
--
-- A missing GRANT is checked BEFORE RLS, so the policy never even ran. The insert
-- failed with a bare permission error carrying no 'chat: ' marker, which is exactly
-- the case ChatService.readableFailure deliberately reports as generic copy rather
-- than leaking — correct behaviour, and also why the message said nothing useful.
--
-- That default-privilege revoke is not something to work around; it is the safety
-- net doing its job. It exists to force each new table to say out loud which writes
-- it accepts, which is what this migration does.
--
-- ── AFFECTED OBJECTS ───────────────────────────────────────────────────────
--   public.chat_messages  +INSERT to authenticated, -SELECT from anon
--   public.chat_reports   +INSERT to authenticated, -SELECT from anon
--   public.chat_mutes     -SELECT from anon        (writes stay RPC-only)
--   public.blog_posts     +INSERT/UPDATE/DELETE to authenticated
--
-- RLS is unchanged and still does the real work: chat inserts are constrained to
-- `user_id = auth.uid()` plus the whole chat_before_insert gate, and every blog
-- write is gated on is_admin(). The grant only decides whether the policy is
-- consulted at all.
--
-- ── VERIFIED ───────────────────────────────────────────────────────────────
-- By impersonating real accounts (set role authenticated + request.jwt.claims), so
-- the grant, the policy and the trigger were all exercised together:
--   admin      -> insert ok, message readable through chat_feed with an author
--                 name, a link ACCEPTED
--   admin      -> posting as another user REFUSED
--   non-admin  -> plain message ok, 't.me/pumpgroup' REFUSED
--
-- ── ROLLBACK ───────────────────────────────────────────────────────────────
--   revoke insert on public.chat_messages, public.chat_reports from authenticated;
--   revoke insert, update, delete on public.blog_posts from authenticated;
--   grant select on public.chat_messages, public.chat_reports, public.chat_mutes
--     to anon;   -- (not recommended; recorded for completeness)

grant insert on public.chat_messages to authenticated;
grant insert on public.chat_reports  to authenticated;

-- Admin authoring writes the table directly; RLS restricts all three to is_admin().
grant insert, update, delete on public.blog_posts to authenticated;

-- The chat tables are signed-in only. RLS already denies anon (every policy is
-- `to authenticated`), but the default grant handed anon SELECT, and leaving it
-- there would let a future policy be read as safe when it is not.
--
-- blog_posts deliberately KEEPS anon SELECT: crawlers must read published posts.
revoke select on public.chat_messages, public.chat_reports, public.chat_mutes
  from anon;

do $$
begin
  if not has_table_privilege('authenticated','public.chat_messages','INSERT') then
    raise exception 'chat_messages still cannot be written by authenticated';
  end if;
  if not has_table_privilege('authenticated','public.blog_posts','INSERT') then
    raise exception 'blog_posts still cannot be written by authenticated';
  end if;
  if has_table_privilege('anon','public.chat_messages','SELECT') then
    raise exception 'anon can still read chat_messages';
  end if;
  -- Must remain true or the blog stops being indexable.
  if not has_table_privilege('anon','public.blog_posts','SELECT') then
    raise exception 'anon lost blog_posts SELECT; crawlers will 404';
  end if;
  -- Writes here are RPC-only by design.
  if has_table_privilege('authenticated','public.chat_mutes','INSERT') then
    raise exception 'chat_mutes became client-writable';
  end if;
end $$;
