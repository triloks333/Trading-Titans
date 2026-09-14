-- A cancelled-but-paid-up subscription keeps its tier until the period actually ends.
--
-- ── WHY THIS FILE EXISTS ────────────────────────────────────────────────────
-- CAPTURED AFTER THE FACT. Version 20260909073537 is already recorded in
-- production's supabase_migrations.schema_migrations, but its .sql was never
-- committed, so a fresh database built from this directory would have had the
-- ORIGINAL current_tier from 20260902000000 while production ran a newer body.
-- Reconstructed verbatim from pg_get_functiondef() against production.
--
-- Because the version is already in schema_migrations, `supabase db push` skips
-- this file against production. It exists so a fresh environment matches, and so
-- the change is reviewable at all.
--
-- ── WHAT CHANGED, AGAINST 20260902000000 ────────────────────────────────────
-- The original granted a tier only for status in ('active','pending'). Razorpay
-- marks a subscription 'cancelled' the moment the user cancels, not when the paid
-- period runs out, so someone who cancelled on day 2 of a month they had already
-- paid for lost Pro immediately. They are owed the rest of the period.
--
-- So a second branch was added: 'cancelled' also grants the tier, but ONLY with a
-- non-null current_period_end in the future. That proviso is the whole safety of
-- it — a cancellation on a mandate that was never charged has no future end date
-- and therefore grants nothing.
--
-- 'halted' and 'expired' stay excluded: a failed or finished mandate must not
-- grant a tier. And because the grant is compared against now(), it lapses on its
-- own. There is no cron here to forget to run.
--
-- Note the asymmetry in the null handling, which is deliberate rather than an
-- oversight: an 'active' subscription tolerates a null current_period_end,
-- because being active is itself proof it is still being paid for. A 'cancelled'
-- one does not, because nothing is paying for it any more.
--
-- ── AFFECTED OBJECTS ───────────────────────────────────────────────────────
--   public.current_tier(uuid)   body only; signature unchanged
--
-- Read by public.user_tiers (the PRO/TITAN badge on profiles and the League
-- screen), by the clients, and by place-order. All of them call this function
-- rather than deriving access from plan strings, which is why one edit here is
-- enough and there is no second copy of the rule to update.
--
-- ── PRIVILEGES: INTENTIONALLY ABSENT ───────────────────────────────────────
-- No revoke/grant statements, and no `comment on function`. Both are already
-- correct from 20260902000000 and CREATE OR REPLACE FUNCTION preserves them.
--
-- Production's ACL reads {postgres=X, anon=X, authenticated=X, service_role=X},
-- which looks like it disagrees with 20260902000000's `revoke execute from public;
-- grant execute to authenticated, service_role`. It does not. Supabase's default
-- privileges grant anon EXECUTE at creation time, and `revoke ... from PUBLIC`
-- does not remove a grant held by the anon role itself. A fresh database replaying
-- the original migration lands on the same ACL, so re-issuing grants here would be
-- a permission change dressed up as a drift fix.
--
-- ── CLIENT COMPATIBILITY ───────────────────────────────────────────────────
-- None needed. Same name, same signature, same return type. Strictly more
-- generous: no user who had a tier before loses one.
--
-- ── ROLLBACK ───────────────────────────────────────────────────────────────
-- Re-run the current_tier block from 20260902000000, which restores the
-- active/pending-only rule. Doing so revokes access from anyone currently inside
-- a cancelled-but-paid-up period, so it is a user-visible downgrade, not a
-- neutral revert.

CREATE OR REPLACE FUNCTION public.current_tier(p_user_id uuid DEFAULT auth.uid())
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select coalesce((select s.tier from public.subscriptions s
     where s.user_id = p_user_id
       and (
         -- Running normally. A null period end is tolerated only here, because an
         -- active subscription is by definition still being paid for.
         (s.status in ('active','pending')
            and (s.current_period_end is null or s.current_period_end > now()))
         -- Cancelled but paid up. Requires a real future end date, so a
         -- cancellation on a mandate that was never charged grants nothing.
         --
         -- `halted` and `expired` stay out on purpose: a failed or finished mandate
         -- must not grant a tier. And because this is compared against now(), the
         -- grant expires on its own with no cron to forget to run.
         or (s.status = 'cancelled'
            and s.current_period_end is not null
            and s.current_period_end > now())
       )
     order by case s.tier when 'titan' then 2 when 'pro' then 1 else 0 end desc
     limit 1), 'free');
$function$
