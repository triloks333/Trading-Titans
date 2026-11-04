-- Deleting a news post in the app hides it from the app only. The website keeps it.
--
-- Every post is also an SSR page on thetradingtitans.com/blog/<slug> that Google
-- indexes, so a hard delete threw away search traffic just to tidy the app's feed.
--
-- The swap happens in the database, not only in the app, so admins on app
-- versions that still call DELETE are covered too. A delete from a signed-in
-- user becomes `hidden_in_app = true` and the row stays. Deletes made with the
-- service role (SQL editor, scripts) still remove the row, for the rare post that
-- really has to go.
--
-- ── AFFECTED OBJECTS ───────────────────────────────────────────────────────
--   public.blog_posts.hidden_in_app        new column, default false
--   public.blog_posts_hide_instead()       new trigger function
--   trigger blog_posts_hide_instead        new, BEFORE DELETE
--
-- ── CLIENT COMPATIBILITY ───────────────────────────────────────────────────
-- Additive. The website reads published rows and never looks at this column.
-- App 1.2.14+ filters hidden rows out of the feed; older apps still show them
-- until users update.
--
-- ── ROLLBACK ───────────────────────────────────────────────────────────────
--   drop trigger if exists blog_posts_hide_instead on public.blog_posts;
--   drop function if exists public.blog_posts_hide_instead();
--   alter table public.blog_posts drop column if exists hidden_in_app;

alter table public.blog_posts
  add column if not exists hidden_in_app boolean not null default false;

create or replace function public.blog_posts_hide_instead()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if auth.role() = 'authenticated' then
    update public.blog_posts set hidden_in_app = true where id = old.id;
    return null; -- cancels the DELETE
  end if;
  return old;
end;
$$;

drop trigger if exists blog_posts_hide_instead on public.blog_posts;
create trigger blog_posts_hide_instead
  before delete on public.blog_posts
  for each row execute function public.blog_posts_hide_instead();
