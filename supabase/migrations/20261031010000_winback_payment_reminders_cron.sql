-- =============================================================================
-- Automated 6-Day Win-Back Payment Reminders (Email + SMS + FCM Push)
-- =============================================================================
-- Tracks Razorpay Payment Links and 5-7 day reminder dispatches for users who
-- initiated a checkout in `public.payment_orders` but have not yet completed a
-- payment. Automatically stops (and cancels the Payment Link) once the user
-- completes any purchase.
-- Permanently excludes Trilok Singh, Pawan Kumar, and Manav.
-- =============================================================================

create table if not exists public.winback_reminder_log (
  user_id          uuid primary key references public.profiles(id) on delete cascade,
  email            text not null,
  name             text,
  phone            text,
  sku              text not null,
  payment_link_id  text,
  short_url        text,
  excluded         boolean not null default false,
  reminder_count   integer not null default 0,
  last_sent_at     timestamptz,
  completed_at     timestamptz,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);

alter table public.winback_reminder_log enable row level security;
revoke all on table public.winback_reminder_log from public, anon, authenticated;
grant all on table public.winback_reminder_log to service_role;
