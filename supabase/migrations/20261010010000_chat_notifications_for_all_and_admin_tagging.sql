-- Migration: 20261010010000_chat_notifications_for_all_and_admin_tagging.sql
-- 1. Adds chat_muted_until to profiles.
-- 2. Adds action_route to chat_messages and exposes it in chat_feed.
-- 3. Adds mute_chat, unmute_chat, and get_taggable_users RPCs.
-- 4. Replaces notify_admins_on_chat_message with notify_on_chat_message to notify ALL users,
--    respecting chat_muted_until, except when an admin tags @everyone (which bypasses mute).

-- ── 1. Column on profiles ───────────────────────────────────────────────────
alter table public.profiles
    add column if not exists chat_muted_until timestamptz;

-- ── 2. Column on chat_messages ──────────────────────────────────────────────
alter table public.chat_messages
    add column if not exists action_route text;

-- ── 3. Update chat_feed view ────────────────────────────────────────────────
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
         coalesce(p.is_admin, false)     as author_is_admin,
         m.edited_at                     as edited_at,
         m.action_route                  as action_route
    from public.chat_messages m
    join public.profiles p on p.id = m.user_id
   where m.deleted_at is null;

revoke insert, update, delete on public.chat_feed from anon, authenticated;
revoke select on public.chat_feed from anon;
grant select on public.chat_feed to authenticated;

-- ── 4. RPCs for Chat Mute Management ────────────────────────────────────────
create or replace function public.mute_chat(p_duration_hours integer default 8)
returns void
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
declare
    v_uid uuid := auth.uid();
begin
    if v_uid is null then
        raise exception 'not authenticated' using errcode = 'check_violation';
    end if;

    update public.profiles
       set chat_muted_until = now() + (greatest(coalesce(p_duration_hours, 8), 1) || ' hours')::interval
     where id = v_uid;
end;
$$;

revoke all on function public.mute_chat(integer) from public;
grant execute on function public.mute_chat(integer) to authenticated;

create or replace function public.unmute_chat()
returns void
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
declare
    v_uid uuid := auth.uid();
begin
    if v_uid is null then
        raise exception 'not authenticated' using errcode = 'check_violation';
    end if;

    update public.profiles
       set chat_muted_until = null
     where id = v_uid;
end;
$$;

revoke all on function public.unmute_chat() from public;
grant execute on function public.unmute_chat() to authenticated;

-- ── 5. RPC: get_taggable_users (for Admin @autocomplete) ───────────────────
create or replace function public.get_taggable_users(p_query text default '')
returns table (
    id         uuid,
    name       text,
    is_admin   boolean
)
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
begin
    return query
    select p.id,
           coalesce(p.name, 'Titan') as name,
           coalesce(p.is_admin, false) as is_admin
      from public.profiles p
     where (
         p_query is null
         or btrim(p_query) = ''
         or p.name ilike '%' || btrim(p_query) || '%'
     )
     order by p.is_admin desc, p.name asc
     limit 20;
end;
$$;

revoke all on function public.get_taggable_users(text) from public;
grant execute on function public.get_taggable_users(text) to authenticated;

-- ── 6. Trigger Function: notify_on_chat_message ─────────────────────────────
create or replace function public.notify_on_chat_message()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
declare
    v_author_name   text;
    v_is_admin      boolean := false;
    v_preview       text;
    v_is_everyone   boolean := false;
    v_action_route  text := null;
    v_title         text;
begin
    if NEW.deleted_at is not null then
        return NEW;
    end if;

    select name, coalesce(is_admin, false)
      into v_author_name, v_is_admin
      from public.profiles
     where id = NEW.user_id;

    -- Only admins can trigger @everyone mass notification
    if v_is_admin and NEW.body is not null and NEW.body ~* '@everyone\b' then
        v_is_everyone := true;
    end if;

    -- Detect action route from explicit column or from message body if admin
    v_action_route := NEW.action_route;
    if v_action_route is null and v_is_admin and NEW.body is not null then
        if NEW.body ~* '/top-up|/topup' then
            v_action_route := '/top-up';
        elsif NEW.body ~* '/mentorship' then
            v_action_route := '/mentorship';
        elsif NEW.body ~* '/trade' then
            v_action_route := '/trade';
        elsif NEW.body ~* '/portfolio' then
            v_action_route := '/portfolio';
        elsif NEW.body ~* '/wallet' then
            v_action_route := '/wallet';
        elsif NEW.body ~* '/glossary' then
            v_action_route := '/glossary';
        elsif NEW.body ~* '/orders' then
            v_action_route := '/orders';
        elsif NEW.body ~* '/whatif' then
            v_action_route := '/whatif';
        elsif NEW.body ~* '/autopsy' then
            v_action_route := '/autopsy';
        elsif NEW.body ~* '/analytics' then
            v_action_route := '/analytics';
        elsif NEW.body ~* '/compete' then
            v_action_route := '/compete';
        end if;
    end if;

    if NEW.kind = 'image' then
        v_preview := '📷 Shared an image' || case when NEW.body is not null and btrim(NEW.body) <> '' then ': ' || NEW.body else '' end;
    elsif NEW.kind = 'voice' then
        v_preview := '🎤 Voice note';
    else
        v_preview := substring(coalesce(NEW.body, '') from 1 for 120);
    end if;

    if v_is_everyone then
        v_title := coalesce(v_author_name, 'Admin') || ' tagged @everyone';
    else
        v_title := coalesce(v_author_name, 'Titan') || ' in Titans Room';
    end if;

    -- If @everyone: notify all profiles (ignoring chat_muted_until).
    -- If regular: notify profiles where chat_muted_until is null or passed.
    insert into public.notifications (user_id, title, body, action_type, action_data)
    select p.id,
           v_title,
           v_preview,
           'chat',
           jsonb_build_object(
               'cta_route', coalesce(v_action_route, '/chat'),
               'action_route', v_action_route,
               'message_id', NEW.id,
               'author_name', v_author_name,
               'author_id', NEW.user_id,
               'is_everyone', v_is_everyone,
               'tag', case when v_is_everyone then '@everyone' else null end
           )
      from public.profiles p
     where p.id is distinct from NEW.user_id
       and (
           v_is_everyone = true
           or p.chat_muted_until is null
           or p.chat_muted_until < now()
       );

    return NEW;
exception
    when others then
        -- Chat posting must never fail because a notification couldn't be created
        return NEW;
end;
$$;

drop trigger if exists trg_chat_notify_admins on public.chat_messages;
drop trigger if exists trg_chat_notify_all on public.chat_messages;
create trigger trg_chat_notify_all
    after insert on public.chat_messages
    for each row execute function public.notify_on_chat_message();
