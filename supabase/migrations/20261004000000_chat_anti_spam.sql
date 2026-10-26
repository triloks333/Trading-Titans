-- Migration: 20261004000000_chat_anti_spam.sql
-- Enforce chat moderation against excessive line breaks, ASCII art floods, and single-dot spam.

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
    v_alnum    text;
    v_newlines integer;
begin
    if v_uid is null then
        raise exception 'chat: not authenticated'
            using errcode = 'check_violation';
    end if;
    if NEW.user_id is null or NEW.user_id is distinct from v_uid then
        raise exception 'chat: you can only post as yourself'
            using errcode = 'check_violation';
    end if;

    if v_is_guest then
        raise exception 'chat: create a free account to post in the room'
            using errcode = 'check_violation';
    end if;

    select muted_until into v_muted
      from public.chat_mutes where user_id = v_uid;
    if v_muted is not null and v_muted > now() then
        raise exception 'chat: you are muted until %', v_muted
            using errcode = 'check_violation';
    end if;

    -- Links are admin only
    if not v_is_admin and public.chat_contains_link(NEW.body) then
        raise exception 'chat: links can only be posted by admins'
            using errcode = 'check_violation';
    end if;

    -- Text moderation & anti-spam (non-admins)
    if not v_is_admin and NEW.kind = 'text' then
        if NEW.body is null or btrim(NEW.body) = '' then
            raise exception 'chat: message cannot be empty'
                using errcode = 'check_violation';
        end if;

        -- Require at least 2 alphanumeric characters (blocks bare '.', '/', etc.)
        v_alnum := regexp_replace(NEW.body, '[^a-zA-Z0-9]', '', 'g');
        if length(v_alnum) < 2 then
            raise exception 'chat: message is too short or lacks content'
                using errcode = 'check_violation';
        end if;

        -- Collapse 3+ consecutive line breaks into a double newline
        NEW.body := regexp_replace(NEW.body, '(\r?\n){3,}', E'\n\n', 'g');

        -- Count total line breaks; limit to maximum 4 per message
        v_newlines := length(NEW.body) - length(replace(NEW.body, E'\n', ''));
        if v_newlines > 4 then
            raise exception 'chat: message contains too many line breaks'
                using errcode = 'check_violation';
        end if;

        -- Block repetitive punctuation / symbol flood (e.g. /////, ......, -----)
        if NEW.body ~ '([^a-zA-Z0-9\s])\1{4,}' then
            raise exception 'chat: repetitive character spam is not allowed'
                using errcode = 'check_violation';
        end if;
    end if;

    -- Rate limit: 10 messages per 30 seconds
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

    NEW.deleted_at := null;
    NEW.deleted_by := null;
    NEW.created_at := now();

    return NEW;
end;
$$;

-- Soft-delete existing spam and single-dot test messages from the feed
update public.chat_messages
   set deleted_at = now()
 where deleted_at is null
   and kind = 'text'
   and (
       id in ('d191d5cd-852d-4d0f-a68c-279b30cf337d', '892b4e3e-719e-4ae5-a595-41dc6e1b4093')
       or length(regexp_replace(body, '[^a-zA-Z0-9]', '', 'g')) < 2
       or body ~ '(\r?\n){3,}'
       or body ~ '([^a-zA-Z0-9\s])\1{4,}'
   );
