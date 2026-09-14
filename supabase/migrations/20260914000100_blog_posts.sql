-- Public blog posts, served server-rendered from thetradingtitans.com/blog/<slug>.
--
-- Applied to production as version 20260914024214 (name `blog_posts`). The local
-- filename keeps this directory's tidy ordering, matching how the 13 Sep migrations
-- were already recorded; production's schema_migrations is the authority on what
-- has run. Same documentation-only relationship as
-- 20260709010000_push_on_notification_insert.sql.
--
-- ── WHY ANON CAN READ THIS ─────────────────────────────────────────────────
-- Every other table in this schema is signed-in only. This one is deliberately
-- readable by `anon`, because the entire point is that Googlebot can fetch a post
-- without an account. Only PUBLISHED rows are exposed, and the published predicate
-- lives in the POLICY rather than in the query, so a forgotten filter in some
-- future caller cannot leak a draft.
--
-- Verified by reading as the anon role: published visible, draft hidden, scheduled
-- (published_at in the future) hidden.
--
-- ── AFFECTED OBJECTS ───────────────────────────────────────────────────────
--   public.blog_posts            new
--   public.blog_posts_touch      new (updated_at trigger)
--   storage bucket 'blog-media'  new, PUBLIC (see below)
--
-- ── CLIENT COMPATIBILITY ───────────────────────────────────────────────────
-- Additive. Nothing shipped before 1.2.4 reads it.
--
-- ── ROLLBACK ───────────────────────────────────────────────────────────────
--   drop table if exists public.blog_posts;
--   drop function if exists public.blog_posts_touch();
--   delete from storage.buckets where id = 'blog-media';   -- objects first

create table if not exists public.blog_posts (
    id           uuid primary key default gen_random_uuid(),
    -- The URL. Immutable in practice: changing it breaks every inbound link and
    -- every search result, so the constraint is here to stop a slug that could
    -- never have worked in the first place.
    slug         text not null unique
                 check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$' and length(slug) between 3 and 120),
    title        text not null check (btrim(title) <> '' and length(title) <= 200),
    -- Feeds the index card and the meta description, so it is capped at roughly
    -- what a search result actually shows.
    excerpt      text check (excerpt is null or length(excerpt) <= 320),
    body_markdown text not null check (btrim(body_markdown) <> ''),
    -- A PUBLIC url, not a storage path: it ends up in an <img> on a crawled page
    -- and in og:image, neither of which can refresh an expiring signed link.
    cover_url    text,
    -- NULL means draft. A FUTURE timestamp means scheduled and stays invisible,
    -- which is why the policy compares against now() rather than testing for null.
    published_at timestamptz,
    author_id    uuid references auth.users(id) on delete set null,
    created_at   timestamptz not null default now(),
    updated_at   timestamptz not null default now()
);

comment on table public.blog_posts is
    'Public blog posts rendered server-side at thetradingtitans.com/blog/<slug>. '
    'Readable by anon BY DESIGN so search engines can index them, but only where '
    'published_at <= now(); drafts and scheduled posts are invisible. Admin-only '
    'writes. cover_url is a public URL, not a storage path, because crawlers cannot '
    'use a signed one.';

create index if not exists blog_posts_published_idx
    on public.blog_posts (published_at desc) where published_at is not null;

alter table public.blog_posts enable row level security;

drop policy if exists blog_posts_public_read on public.blog_posts;
create policy blog_posts_public_read on public.blog_posts
    for select to anon, authenticated
    -- The published gate lives HERE, not in the query.
    using (published_at is not null and published_at <= now());

drop policy if exists blog_posts_admin_read on public.blog_posts;
create policy blog_posts_admin_read on public.blog_posts
    for select to authenticated
    using (public.is_admin());

drop policy if exists blog_posts_admin_write on public.blog_posts;
create policy blog_posts_admin_write on public.blog_posts
    for insert to authenticated with check (public.is_admin());

drop policy if exists blog_posts_admin_update on public.blog_posts;
create policy blog_posts_admin_update on public.blog_posts
    for update to authenticated using (public.is_admin()) with check (public.is_admin());

drop policy if exists blog_posts_admin_delete on public.blog_posts;
create policy blog_posts_admin_delete on public.blog_posts
    for delete to authenticated using (public.is_admin());

-- Keeps updated_at honest without the client having to remember. It feeds
-- dateModified in the page's structured data.
create or replace function public.blog_posts_touch()
returns trigger language plpgsql
set search_path to 'public', 'pg_temp'
as $$
begin
    NEW.updated_at := now();
    return NEW;
end;
$$;

drop trigger if exists trg_blog_posts_touch on public.blog_posts;
create trigger trg_blog_posts_touch
    before update on public.blog_posts
    for each row execute function public.blog_posts_touch();

-- Cover images and inline art. PUBLIC, unlike chat-media: an og:image or an <img>
-- in a crawled page has no session to sign a URL with. Nothing private belongs here.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('blog-media', 'blog-media', true, 5242880,
        array['image/jpeg','image/png','image/webp'])
on conflict (id) do update
   set public             = true,
       file_size_limit    = excluded.file_size_limit,
       allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists blog_media_admin_write on storage.objects;
create policy blog_media_admin_write on storage.objects
    for insert to authenticated
    with check (bucket_id = 'blog-media' and public.is_admin());

drop policy if exists blog_media_public_read on storage.objects;
create policy blog_media_public_read on storage.objects
    for select to anon, authenticated
    using (bucket_id = 'blog-media');

do $$
begin
    if not exists (select 1 from storage.buckets where id='blog-media' and public) then
        raise exception 'blog-media must be public or cover images will not render for crawlers';
    end if;
    -- A draft must never be readable by anon. Asserted rather than assumed because
    -- this is the only anon-readable table in the schema.
    if exists (
        select 1 from pg_policies
         where schemaname='public' and tablename='blog_posts'
           and cmd='SELECT' and 'anon' = any(roles)
           and qual not like '%published_at%'
    ) then
        raise exception 'an anon SELECT policy on blog_posts does not gate on published_at';
    end if;
end $$;
