-- Create waitlist table for Trading Titans emails collection
create table if not exists public.waitlist (
    id uuid default gen_random_uuid() primary key,
    email text unique not null,
    created_at timestamp with time zone default timezone('utc'::text, now()) not null,
    referral_code text unique default substring(md5(random()::text) from 1 for 8) not null,
    referred_by text references public.waitlist(referral_code) on delete set null,
    status text default 'pending'::text check (status in ('pending', 'invited', 'active')),
    metadata jsonb default '{}'::jsonb
);

-- Enable RLS (Row Level Security)
alter table public.waitlist enable row level security;

-- Drop existing policies if they exist to prevent errors
drop policy if exists "Allow public inserts" on public.waitlist;
drop policy if exists "Allow users to view their status" on public.waitlist;

-- Policies for public signup
create policy "Allow public inserts" on public.waitlist
    for insert with check (true);

create policy "Allow users to view their status" on public.waitlist
    for select using (true);
