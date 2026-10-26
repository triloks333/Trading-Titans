-- Migration: 20261010000000_chat_edit_and_admin_notifications.sql
-- 1. Adds edited_at to chat_messages and exposes it in chat_feed.
-- 2. Creates edit_chat_message() RPC for authors to update their own text messages.
-- 3. Adds trigger to notify admins when new chat messages are posted in the Titans Room.

-- ── 1. Column on chat_messages ──────────────────────────────────────────────
alter table public.chat_messages
    add column if not exists edited_at timestamptz;

-- ── 2. Update chat_feed view ───────────────────────────────────────────────
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
         m.edited_at                     as edited_at
    from public.chat_messages m
    join public.profiles p on p.id = m.user_id
   where m.deleted_at is null;

revoke insert, update, delete on public.chat_feed from anon, authenticated;
revoke select on public.chat_feed from anon;
grant select on public.chat_feed to authenticated;

-- ── 3. RPC: edit_chat_message ──────────────────────────────────────────────
create or replace function public.edit_chat_message(
    p_message_id uuid,
    p_new_body   text
)
returns void
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
declare
    v_uid      uuid := auth.uid();
    v_is_admin boolean := public.is_admin();
    v_alnum    text;
    v_newlines integer;
    v_owner    uuid;
    v_kind     text;
begin
    if v_uid is null then
        raise exception 'chat: not authenticated'
            using errcode = 'check_violation';
    end if;

    select user_id, kind
      into v_owner, v_kind
      from public.chat_messages
     where id = p_message_id and deleted_at is null;

    if v_owner is null then
        raise exception 'chat: message not found'
            using errcode = 'check_violation';
    end if;

    if v_owner is distinct from v_uid then
        raise exception 'chat: you can only edit your own messages'
            using errcode = 'check_violation';
    end if;

    if v_kind is distinct from 'text' then
        raise exception 'chat: only text messages can be edited'
            using errcode = 'check_violation';
    end if;

    if p_new_body is null or btrim(p_new_body) = '' then
        raise exception 'chat: message cannot be empty'
            using errcode = 'check_violation';
    end if;

    -- Links restricted to admins
    if not v_is_admin and public.chat_contains_link(p_new_body) then
        raise exception 'chat: links can only be posted by admins'
            using errcode = 'check_violation';
    end if;

    -- Text moderation & anti-spam (non-admins)
    if not v_is_admin then
        v_alnum := regexp_replace(p_new_body, '[^a-zA-Z0-9]', '', 'g');
        if length(v_alnum) < 2 then
            raise exception 'chat: message is too short or lacks content'
                using errcode = 'check_violation';
        end if;

        p_new_body := regexp_replace(p_new_body, '(\r?\n){3,}', E'\n\n', 'g');
        v_newlines := length(p_new_body) - length(replace(p_new_body, E'\n', ''));
        if v_newlines > 4 then
            raise exception 'chat: message contains too many line breaks'
                using errcode = 'check_violation';
        end if;

        if p_new_body ~ '([^a-zA-Z0-9\s])\1{4,}' then
            raise exception 'chat: repetitive character spam is not allowed'
                using errcode = 'check_violation';
        end if;
    end if;

    update public.chat_messages
       set body = p_new_body,
           edited_at = now()
     where id = p_message_id
       and user_id = v_uid;
end;
$$;

revoke all on function public.edit_chat_message(uuid, text) from public;
grant execute on function public.edit_chat_message(uuid, text) to authenticated;

-- ── 4. Admin notifications trigger ─────────────────────────────────────────
create or replace function public.notify_admins_on_chat_message()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
declare
    v_author_name text;
    v_preview     text;
begin
    if NEW.deleted_at is not null then
        return NEW;
    end if;

    select name into v_author_name
      from public.profiles
     where id = NEW.user_id;

    if NEW.kind = 'image' then
        v_preview := '📷 Shared an image' || case when NEW.body is not null and btrim(NEW.body) <> '' then ': ' || NEW.body else '' end;
    elsif NEW.kind = 'voice' then
        v_preview := '🎤 Voice note';
    else
        v_preview := substring(coalesce(NEW.body, '') from 1 for 120);
    end if;

    -- Insert in-app notifications for admins (except message author).
    -- Existing trg_push_on_notification on public.notifications will forward
    -- this to the push-notification edge function.
    insert into public.notifications (user_id, title, body, action_type, action_data)
    select p.id,
           coalesce(v_author_name, 'Titan') || ' in Titans Room',
           v_preview,
           'chat',
           jsonb_build_object(
               'cta_route', '/chat',
               'message_id', NEW.id,
               'author_name', v_author_name,
               'author_id', NEW.user_id
           )
      from public.profiles p
     where coalesce(p.is_admin, false) = true
       and p.id is distinct from NEW.user_id;

    return NEW;
exception
    when others then
        -- Chat posting must never fail because a notification couldn't be created
        return NEW;
end;
$$;

drop trigger if exists trg_chat_notify_admins on public.chat_messages;
create trigger trg_chat_notify_admins
    after insert on public.chat_messages
    for each row execute function public.notify_admins_on_chat_message();
