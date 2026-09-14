-- One public chat room, with the moderation needed to run it.
--
-- ── APPLIED TO PRODUCTION AS SEVEN VERSIONS ────────────────────────────────
-- This file is the consolidated final state. Production applied it incrementally,
-- because two holes and a missing read path were found by testing between steps:
--
--   20260914020314  public_chat_room                        tables
--   20260914020337  ..._link_detection_and_insert_gate      first cut
--   20260914020357  ..._rls_and_moderation                  policies + RPCs
--   20260914020415  ..._media_realtime_and_assertions       bucket, realtime
--   20260914020707  chat_link_detection_short_domains_and_no_guest_posting
--   20260914021437  chat_feed_view                          the read path
--   20260914022026  chat_insert_gate_null_safe_identity_check
--
-- Replaying THIS file on a fresh database lands on the same schema as production;
-- the superseded first cuts are described in place rather than reproduced. The
-- local filename keeps this directory's ordering, matching how the 13 Sep
-- migrations were already recorded. Production's schema_migrations is the authority
-- on what has run — the same documentation-only relationship as
-- 20260709010000_push_on_notification_insert.sql.
--
-- Write GRANTS are NOT here: see 20260914000200. Nothing in this file could be
-- written to by a client until that ran.
--
-- Requested: a single room for all users, carrying text, images and voice notes,
-- with links restricted to admins, a report button, admin delete and per-user
-- mute. Voice notes capped at 60 seconds, images compressed on device.
--
-- ── THE ACTUAL WORK IS MODERATION, NOT TRANSPORT ───────────────────────────
-- Realtime is one line at the bottom of this file. Everything above it exists
-- because an unmoderated public room attached to a financial app is a liability:
-- the predictable failure is a phishing link reaching every user at once, posted
-- by an account created a minute earlier.
--
-- So the link rule is enforced by a BEFORE INSERT TRIGGER rather than by an RPC.
-- An RPC only holds if every other write path is revoked, and the moment someone
-- adds a legitimate second insert path the rule silently stops applying. A trigger
-- holds no matter how the row arrives — PostgREST, another RPC, a cron, psql.
--
-- ── AFFECTED OBJECTS ───────────────────────────────────────────────────────
--   public.chat_messages            new
--   public.chat_reports             new
--   public.chat_mutes               new
--   public.chat_contains_link       new
--   public.chat_before_insert       new (trigger function)
--   public.report_chat_message      new
--   public.delete_chat_message      new (admin)
--   public.mute_chat_user           new (admin)
--   public.unmute_chat_user         new (admin)
--   storage bucket 'chat-media'     new, private, 5 MB cap
--   publication supabase_realtime   chat_messages added
--
-- ── CLIENT COMPATIBILITY ───────────────────────────────────────────────────
-- Entirely additive. Nothing shipped reads or writes any of this, so 1.2.3 is
-- unaffected and this can be applied before the client that uses it exists.
--
-- ── ROLLBACK ───────────────────────────────────────────────────────────────
--   alter publication supabase_realtime drop table public.chat_messages;
--   drop function if exists public.unmute_chat_user(uuid);
--   drop function if exists public.mute_chat_user(uuid, integer, text);
--   drop function if exists public.delete_chat_message(uuid);
--   drop function if exists public.report_chat_message(uuid, text);
--   drop trigger if exists trg_chat_before_insert on public.chat_messages;
--   drop function if exists public.chat_before_insert();
--   drop function if exists public.chat_contains_link(text);
--   drop table if exists public.chat_reports;
--   drop table if exists public.chat_mutes;
--   drop table if exists public.chat_messages;
--   delete from storage.buckets where id = 'chat-media';  -- objects first

-- ── 1. Tables ──────────────────────────────────────────────────────────────
create table if not exists public.chat_messages (
    id          uuid primary key default gen_random_uuid(),
    user_id     uuid not null references auth.users(id) on delete cascade,
    kind        text not null default 'text' check (kind in ('text','image','voice')),
    -- Text content, or the caption on an image. Null for a bare voice note.
    body        text,
    -- Storage object path inside the 'chat-media' bucket. Null for text.
    media_path  text,
    -- Voice only. Capped here as well as in the UI, because a client is not a
    -- trust boundary and a 30-minute "voice note" is a denial-of-service on
    -- everyone else's data plan.
    duration_ms integer check (duration_ms is null or (duration_ms > 0 and duration_ms <= 60000)),
    created_at  timestamptz not null default now(),
    -- Soft delete. Keeps a reported message readable to admins after removal,
    -- which a hard delete would destroy along with the evidence.
    deleted_at  timestamptz,
    deleted_by  uuid references auth.users(id),
    -- A message has to actually contain something. Enforced here rather than in
    -- the client so an empty row cannot be inserted by any path.
    constraint chat_messages_has_content check (
        case kind
            when 'text'  then body is not null and btrim(body) <> ''
            when 'image' then media_path is not null
            when 'voice' then media_path is not null and duration_ms is not null
        end
    )
);

comment on table public.chat_messages is
    'The single public chat room. Readable by every signed-in user, writable only '
    'as yourself, never updatable or deletable by a client. Admin removal goes '
    'through delete_chat_message(), which soft-deletes so reports stay auditable.';

-- The room is read newest-last in a paged window, so this is the only index the
-- read path needs. Partial on the soft-delete flag because a deleted message is
-- never in a normal result set.
create index if not exists chat_messages_recent_idx
    on public.chat_messages (created_at desc) where deleted_at is null;
-- For the rate limit and for "show me everything this spammer posted".
create index if not exists chat_messages_user_idx
    on public.chat_messages (user_id, created_at desc);

create table if not exists public.chat_mutes (
    user_id     uuid primary key references auth.users(id) on delete cascade,
    -- Finite, never 'infinity'. A mute that expires on its own needs no cron to
    -- forget to run, and the same rule already governs current_tier's grant. For a
    -- permanent mute an admin passes a large number of days.
    muted_until timestamptz not null,
    reason      text,
    muted_by    uuid not null references auth.users(id),
    created_at  timestamptz not null default now()
);

comment on table public.chat_mutes is
    'Admin-imposed posting bans for the public room. A row whose muted_until is in '
    'the past is inert, so unmuting is either deleting the row or letting it lapse. '
    'This is moderation, not a personal block list: it stops the user posting, it '
    'does not change what anyone sees.';

create table if not exists public.chat_reports (
    id          uuid primary key default gen_random_uuid(),
    message_id  uuid not null references public.chat_messages(id) on delete cascade,
    reporter_id uuid not null references auth.users(id) on delete cascade,
    reason      text,
    created_at  timestamptz not null default now(),
    -- One report per person per message. Without this a single user could inflate
    -- a report count and make the admin queue useless.
    unique (message_id, reporter_id)
);

comment on table public.chat_reports is
    'User reports against chat messages. Insert-only for users, readable by admins.';

-- ── 2. Link detection ──────────────────────────────────────────────────────
-- Its own function so the rule lives in exactly one place and can be tested
-- directly, rather than being buried in a trigger body where the only way to
-- exercise it is to insert a message.
--
-- ponytail: three signals, not a URL parser. A scheme, a www. prefix, or a dot
-- followed by a TLD from a curated list. The ceiling is a genuinely novel TLD or a
-- deliberate obfuscation ("example dot com", unicode homoglyphs, a link inside an
-- image) — none of which a regex was ever going to catch. The upgrade path is
-- moving to a moderation queue where a non-admin's first N messages are held for
-- review, which catches intent rather than syntax.
--
-- The TLD list rather than a bare `\.[a-z]{2,}` is what keeps false positives near
-- zero: a missing space after a full stop ("done.Next") would match the general
-- pattern and get an innocent message rejected, whereas 'next' is not a TLD. The
-- list leans towards the TLDs actually used for spam plus the common country
-- codes; add to it when something new shows up.
-- TWO HOLES FOUND BY TESTING THE FIRST CUT, both fixed below. Recorded because
-- both are the kind of thing that reads as fine and is not:
--
-- 1. 't.me/pumpgroup' slipped through. The bare-domain pattern demanded a 2+
--    character label and Telegram's is one character. Telegram invite links are
--    among the most common spam in trading communities, so this was the worst
--    available miss. Hence the second, path-anchored pattern.
-- 2. Guests could post (see chat_before_insert). Supabase anonymous sign-ins carry
--    an `authenticated` JWT, so `to authenticated` includes them.
create or replace function public.chat_contains_link(p_text text)
returns boolean
language sql
immutable
set search_path to 'pg_catalog', 'pg_temp'
as $$
    with tld as (select
        'com|net|org|io|co|in|me|app|dev|ai|xyz|info|biz|link|live|shop|' ||
        'site|online|club|top|tv|gg|ly|to|cc|ws|pw|icu|vip|fun|store|' ||
        'space|website|tech|cloud|digital|network|agency|solutions|' ||
        'uk|us|de|fr|es|it|nl|ru|cn|jp|kr|au|ca|br|mx|ar|za|ng|ke|eg|' ||
        'pk|bd|lk|np|ae|sa|qa|kw|sg|hk|tw|ph|id|my|th|vn|tr|ir|il|' ||
        'pl|se|no|fi|dk|cz|gr|pt|hu|ro|ua|by|kz|uz|ch|at|be|ie|nz' as list)
    select case
        when p_text is null or btrim(p_text) = '' then false
        -- Any scheme at all: http, https, ftp, tg, javascript, data...
        when p_text ~* '[a-z][a-z0-9+.-]*://' then true
        when p_text ~* '\mwww\.'               then true
        when p_text ~* 'mailto:'               then true
        -- Bare domain. Label 2+ characters so initials like 'e.g.' and decimals
        -- like 'Rs.50' do not match.
        when p_text ~* ('\m[a-z0-9][a-z0-9-]{1,61}\.(' || (select list from tld) || ')\M')
            then true
        -- With a path, one character is enough: t.me/x, x.co/y. A path makes it
        -- unambiguously a URL, so the label length no longer has to carry the
        -- false-positive protection on its own.
        when p_text ~* ('\m[a-z0-9][a-z0-9-]{0,61}\.(' || (select list from tld) || ')/')
            then true
        else false
    end;
$$;

comment on function public.chat_contains_link(text) is
    'True when the text looks like it contains a URL. Used to keep links out of the '
    'public room for everyone except admins. Syntactic and deliberately '
    'conservative about false positives — see the function body for the ceiling.';

-- ── 3. The insert gate ─────────────────────────────────────────────────────
-- Everything that decides whether a message is allowed, in one BEFORE INSERT
-- trigger so no write path can miss it.
create or replace function public.chat_before_insert()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
declare
    v_uid      uuid := auth.uid();
    v_is_admin boolean := public.is_admin();
    v_is_guest boolean := coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false);
    v_muted    timestamptz;
    v_recent   integer;
begin
    -- THIRD HOLE, found by probing the gate with no session: the first cut wrote
    -- `NEW.user_id <> auth.uid()`, which evaluates to NULL when auth.uid() is NULL,
    -- and plpgsql treats `if NULL then` as false — so the check did not fire and an
    -- insert with no session was ACCEPTED. Same three-valued logic trap the
    -- leaderboard migration documents for its WHERE clause.
    --
    -- RLS still denied anon (its `with check` also evaluates NULL and denies), so
    -- the exposure was limited to callers that bypass RLS: service_role and
    -- postgres. Those are trusted, but being the backstop for exactly that caller
    -- was this trigger's stated purpose.
    if v_uid is null then
        raise exception 'chat: not authenticated'
            using errcode = 'check_violation';
    end if;
    -- `is distinct from`, which is NULL safe, not `<>`.
    if NEW.user_id is null or NEW.user_id is distinct from v_uid then
        raise exception 'chat: you can only post as yourself'
            using errcode = 'check_violation';
    end if;

    -- Guests read the room but cannot post. An anonymous account is free to create
    -- and free to abandon, which is exactly what makes a public room worth abusing.
    -- Not expressible in the RLS policy: `to authenticated` already includes
    -- anonymous sign-ins, which is the trap.
    if v_is_guest then
        raise exception 'chat: create a free account to post in the room'
            using errcode = 'check_violation';
    end if;

    -- Muted users cannot post. Checked against now() so a lapsed mute needs no
    -- cleanup.
    select muted_until into v_muted
      from public.chat_mutes where user_id = v_uid;
    if v_muted is not null and v_muted > now() then
        raise exception 'chat: you are muted until %', v_muted
            using errcode = 'check_violation';
    end if;

    -- Links are admin only. THE REQUIREMENT. Rejected rather than stripped so the
    -- user learns why instead of watching their message silently lose half itself.
    -- Applies to the caption on an image too, which is the obvious way round a
    -- text-only check.
    if not v_is_admin and public.chat_contains_link(NEW.body) then
        raise exception 'chat: links can only be posted by admins'
            using errcode = 'check_violation';
    end if;

    -- ponytail: a flat rate limit, 10 messages per 30 seconds, non-admins only.
    -- Not a token bucket and not per-kind. The ceiling is a determined flooder
    -- pacing themselves just under it; the upgrade path is a slow-mode column on a
    -- room settings row, which is also what an admin would want during an incident.
    -- Without any limit at all a single loop can push the room past every client's
    -- ability to render it.
    if not v_is_admin then
        select count(*) into v_recent
          from public.chat_messages
         where user_id = v_uid
           and created_at > now() - interval '30 seconds';
        if v_recent >= 10 then
            raise exception 'chat: you are posting too quickly, wait a moment'
                using errcode = 'check_violation';
        end if;
    end if;

    -- A client must not be able to post something pre-deleted, or attribute the
    -- deletion to someone else.
    NEW.deleted_at := null;
    NEW.deleted_by := null;
    -- Nor backdate a message to the top of the room.
    NEW.created_at := now();

    return NEW;
end;
$$;

drop trigger if exists trg_chat_before_insert on public.chat_messages;
create trigger trg_chat_before_insert
    before insert on public.chat_messages
    for each row execute function public.chat_before_insert();

-- ── 4. RLS ─────────────────────────────────────────────────────────────────
alter table public.chat_messages enable row level security;
alter table public.chat_mutes    enable row level security;
alter table public.chat_reports  enable row level security;

-- Deliberately NO update or delete policy on any of the three. An absent policy is
-- a denial, so a client cannot edit or remove anything; the admin paths below are
-- SECURITY DEFINER functions instead. That is the whole reason those functions
-- exist rather than an `is_admin()` delete policy — one audited entry point.

drop policy if exists chat_messages_select on public.chat_messages;
create policy chat_messages_select on public.chat_messages
    for select to authenticated
    -- A removed message disappears for everyone but stays visible to admins, who
    -- need it to action the report that caused the removal.
    using (deleted_at is null or public.is_admin());

drop policy if exists chat_messages_insert on public.chat_messages;
create policy chat_messages_insert on public.chat_messages
    for insert to authenticated
    with check (user_id = auth.uid());

drop policy if exists chat_mutes_select on public.chat_mutes;
create policy chat_mutes_select on public.chat_mutes
    for select to authenticated
    -- Own row so the composer can say "you are muted until X" instead of letting
    -- the user type a message and then failing on insert.
    using (user_id = auth.uid() or public.is_admin());

drop policy if exists chat_reports_insert on public.chat_reports;
create policy chat_reports_insert on public.chat_reports
    for insert to authenticated
    with check (reporter_id = auth.uid());

drop policy if exists chat_reports_select on public.chat_reports;
create policy chat_reports_select on public.chat_reports
    for select to authenticated
    -- Reporters do not get to see the queue. Knowing who reported whom in a public
    -- room is itself a way to start a fight.
    using (public.is_admin());

-- ── 5. Moderation entry points ─────────────────────────────────────────────
create or replace function public.report_chat_message(p_message_id uuid, p_reason text default null)
returns void
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
declare v_uid uuid := auth.uid();
begin
    if v_uid is null then raise exception 'Not authenticated'; end if;
    insert into public.chat_reports (message_id, reporter_id, reason)
    values (p_message_id, v_uid, nullif(btrim(coalesce(p_reason,'')), ''))
    -- Reporting twice is not an error worth showing a user; they pressed the button
    -- again because nothing visibly happened the first time.
    on conflict (message_id, reporter_id) do nothing;
end;
$$;

revoke all on function public.report_chat_message(uuid, text) from public;
grant execute on function public.report_chat_message(uuid, text) to authenticated;

create or replace function public.delete_chat_message(p_message_id uuid)
returns void
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
begin
    if not public.is_admin() then
        raise exception 'delete_chat_message is admin only';
    end if;
    -- Soft delete, so the report queue still has something to point at.
    update public.chat_messages
       set deleted_at = now(), deleted_by = auth.uid()
     where id = p_message_id and deleted_at is null;
end;
$$;

revoke all on function public.delete_chat_message(uuid) from public;
grant execute on function public.delete_chat_message(uuid) to authenticated;

create or replace function public.mute_chat_user(
    p_user_id uuid,
    p_days    integer default 1,
    p_reason  text default null
)
returns timestamptz
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
declare v_until timestamptz;
begin
    if not public.is_admin() then
        raise exception 'mute_chat_user is admin only';
    end if;
    if p_days is null or p_days < 1 or p_days > 36500 then
        raise exception 'p_days must be between 1 and 36500';
    end if;
    v_until := now() + make_interval(days => p_days);
    insert into public.chat_mutes (user_id, muted_until, reason, muted_by)
    values (p_user_id, v_until, nullif(btrim(coalesce(p_reason,'')), ''), auth.uid())
    on conflict (user_id) do update
       set muted_until = excluded.muted_until,
           reason      = excluded.reason,
           muted_by    = excluded.muted_by,
           created_at  = now();
    return v_until;
end;
$$;

revoke all on function public.mute_chat_user(uuid, integer, text) from public;
grant execute on function public.mute_chat_user(uuid, integer, text) to authenticated;

create or replace function public.unmute_chat_user(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
begin
    if not public.is_admin() then
        raise exception 'unmute_chat_user is admin only';
    end if;
    delete from public.chat_mutes where user_id = p_user_id;
end;
$$;

revoke all on function public.unmute_chat_user(uuid) from public;
grant execute on function public.unmute_chat_user(uuid) to authenticated;

-- ── 6. Media ───────────────────────────────────────────────────────────────
-- Private bucket, not public. Chat media is readable by signed-in users through
-- the policy below rather than by anyone holding the URL, so a leaked link outside
-- the app is inert.
--
-- 5 MB covers a device-compressed photo and a 60-second voice note with headroom.
-- The mime allow-list is the real guard: without it the bucket is a way to host
-- arbitrary files, including HTML that would be served from our own origin.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('chat-media', 'chat-media', false, 5242880, array[
    'image/jpeg','image/png','image/webp',
    -- What the common Android and iOS recorders actually emit.
    'audio/aac','audio/mp4','audio/m4a','audio/mpeg','audio/ogg','audio/webm'
])
on conflict (id) do update
   set public             = false,
       file_size_limit    = excluded.file_size_limit,
       allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists chat_media_insert on storage.objects;
create policy chat_media_insert on storage.objects
    for insert to authenticated
    with check (
        bucket_id = 'chat-media'
        -- First path segment must be the uploader's own id, so one user cannot
        -- write into another's prefix or overwrite their media.
        and (storage.foldername(name))[1] = auth.uid()::text
    );

drop policy if exists chat_media_select on storage.objects;
create policy chat_media_select on storage.objects
    for select to authenticated
    using (bucket_id = 'chat-media');

-- No update or delete policy: media follows its message, and a message is only
-- ever soft-deleted. Purging the objects behind removed messages is a housekeeping
-- job for the service role, not something a client should reach.

-- ── 7. Realtime ────────────────────────────────────────────────────────────
-- The easy part, and the last line for a reason. RLS still applies to realtime, so
-- a subscriber receives only rows the select policy would have given them.
do $$
begin
    if not exists (
        select 1 from pg_publication_tables
         where pubname = 'supabase_realtime'
           and schemaname = 'public' and tablename = 'chat_messages'
    ) then
        alter publication supabase_realtime add table public.chat_messages;
    end if;
end $$;

-- ── 8. Assertions ──────────────────────────────────────────────────────────
-- The same belt-and-braces as 20260913000100: this migration's guarantees are all
-- absences (no update policy, no delete policy, a private bucket), and an absence
-- is exactly what a later edit removes without noticing.
do $$
declare v_problem text := '';
begin
    if exists (select 1 from pg_policies where schemaname='public'
                and tablename='chat_messages' and cmd in ('UPDATE','DELETE')) then
        v_problem := v_problem || 'chat_messages gained an update/delete policy; ';
    end if;
    if not exists (select 1 from pg_policies where schemaname='public'
                    and tablename='chat_messages' and cmd='SELECT') then
        v_problem := v_problem || 'chat_messages has no select policy; ';
    end if;
    if exists (select 1 from storage.buckets where id='chat-media' and public) then
        v_problem := v_problem || 'chat-media bucket is public; ';
    end if;
    if not exists (select 1 from storage.buckets
                    where id='chat-media' and allowed_mime_types is not null) then
        v_problem := v_problem || 'chat-media accepts any mime type; ';
    end if;
    if not exists (select 1 from pg_trigger
                    where tgname='trg_chat_before_insert' and not tgisinternal) then
        v_problem := v_problem || 'the insert gate trigger is missing; ';
    end if;
    -- The link rule itself, checked against a real string rather than trusting the
    -- regex compiled.
    if not public.chat_contains_link('check this https://evil.test/x') then
        v_problem := v_problem || 'link detection missed a scheme; ';
    end if;
    if not public.chat_contains_link('go to freemoney.xyz now') then
        v_problem := v_problem || 'link detection missed a bare domain; ';
    end if;
    if public.chat_contains_link('nifty closed up 1.2 percent today') then
        v_problem := v_problem || 'link detection false-positived on a decimal; ';
    end if;
    if public.chat_contains_link('e.g. buy the dip') then
        v_problem := v_problem || 'link detection false-positived on initials; ';
    end if;
    -- The Telegram case specifically, because it is the one the first cut missed.
    if not public.chat_contains_link('join t.me/pumpgroup') then
        v_problem := v_problem || 'link detection missed a short-label domain; ';
    end if;
    if public.chat_contains_link('P.S. good call') then
        v_problem := v_problem || 'link detection false-positived on an abbreviation; ';
    end if;
    if v_problem <> '' then
        raise exception 'chat room migration assertions failed: %', v_problem;
    end if;
end $$;

-- ── 9. The read path ───────────────────────────────────────────────────────
-- Added after the client was written, because two things made reading the room
-- directly impossible and neither was visible from the schema alone:
--
-- 1. chat_messages.user_id references auth.users, NOT public.profiles, so
--    PostgREST cannot embed the author — `profiles!inner(...)` finds no
--    relationship and the request fails outright.
-- 2. profiles is own-row-only under RLS (profiles_select_own_or_admin). Even with
--    a working join, every message except your own would come back with a blank
--    author. A room where only your own name renders is not a room.
--
-- So the same device the League tab already uses: a security_invoker = false view
-- that reads profiles as its owner and publishes ONLY safe columns. No email, no
-- wallet_balance, no is_admin — a public room must not become a way to enumerate
-- who the admins are or what anyone holds.
--
-- Soft-deleted messages are filtered HERE, and that is the only filter that
-- applies: with security_invoker = false the underlying select policy is bypassed.
-- Admins read removed messages from chat_messages directly, where their policy
-- branch still applies.
create or replace view public.chat_feed
  with (security_invoker = false) as
  select m.id,
         m.user_id,
         m.kind,
         m.body,
         m.media_path,
         m.duration_ms,
         m.created_at,
         p.name                         as author_name,
         public.current_tier(m.user_id) as author_tier
    from public.chat_messages m
    join public.profiles p on p.id = m.user_id
   where m.deleted_at is null;

comment on view public.chat_feed is
  'Read path for the public chat room: messages joined to their author''s display '
  'name and paid tier. MUST stay security_invoker = false — profiles is '
  'own-row-only, so with caller RLS every author name except your own goes blank. '
  'Publishes only safe columns; email, wallet_balance and is_admin are deliberately '
  'absent so the room cannot be used to enumerate admins or balances. Soft-deleted '
  'messages are filtered here because the underlying select policy is bypassed. '
  'READ ONLY: writes are revoked, and the Supabase linter''s security_definer_view '
  'finding is expected here and must NOT be "fixed".';

-- A joined view is not auto-updatable, so a write would fail anyway. Revoked
-- explicitly regardless, for the same reason the leaderboard does it: this view is
-- one edit away from being simple again, and at that point a write through it would
-- run as postgres.
revoke insert, update, delete on public.chat_feed from anon, authenticated;
revoke select on public.chat_feed from anon;
grant select on public.chat_feed to authenticated;

-- ── 10. Read-path assertions ───────────────────────────────────────────────
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
  if exists (select 1 from information_schema.columns
              where table_schema='public' and table_name='chat_feed'
                and column_name in ('email','wallet_balance','is_admin')) then
    raise exception 'chat_feed is leaking a sensitive profiles column';
  end if;

  -- The identity guard, which the first cut got wrong. This migration runs with no
  -- auth.uid(), so an insert here MUST be refused; if it succeeds, the NULL-safety
  -- fix has been undone.
  begin
    insert into public.chat_messages (user_id, kind, body)
    values ('00000000-0000-0000-0000-000000000000', 'text', 'assertion probe');
    raise exception 'the chat insert gate accepted a session-less insert';
  exception
    when check_violation then null;  -- expected
  end;
end
$$;
