-- Migration: seed_2026_market_holidays
-- Description: Seeds the full official NSE/BSE and US market trading holidays for 2026
-- and grants read permissions to anon so guest/fresh-install sessions can see market closures.

insert into public.market_holidays (market, holiday_date, name) values
    ('stock', '2026-01-26', 'Republic Day'),
    ('stock', '2026-03-03', 'Holi'),
    ('stock', '2026-03-26', 'Shri Ram Navami'),
    ('stock', '2026-03-31', 'Shri Mahavir Jayanti'),
    ('stock', '2026-04-03', 'Good Friday'),
    ('stock', '2026-04-14', 'Dr. Baba Saheb Ambedkar Jayanti'),
    ('stock', '2026-05-01', 'Maharashtra Day'),
    ('stock', '2026-05-28', 'Bakri Id'),
    ('stock', '2026-06-26', 'Muharram'),
    ('stock', '2026-09-14', 'Ganesh Chaturthi'),
    ('stock', '2026-10-02', 'Mahatma Gandhi Jayanti'),
    ('stock', '2026-10-20', 'Dussehra'),
    ('stock', '2026-11-10', 'Diwali-Balipratipada'),
    ('stock', '2026-11-24', 'Prakash Gurpurb Sri Guru Nanak Dev'),
    ('stock', '2026-12-25', 'Christmas'),
    ('us_stock', '2026-01-01', 'New Year''s Day'),
    ('us_stock', '2026-01-19', 'Martin Luther King Jr. Day'),
    ('us_stock', '2026-02-16', 'Washington''s Birthday'),
    ('us_stock', '2026-04-03', 'Good Friday'),
    ('us_stock', '2026-05-25', 'Memorial Day'),
    ('us_stock', '2026-06-19', 'Juneteenth National Independence Day'),
    ('us_stock', '2026-07-03', 'Independence Day (Observed)'),
    ('us_stock', '2026-09-07', 'Labor Day'),
    ('us_stock', '2026-11-26', 'Thanksgiving Day'),
    ('us_stock', '2026-12-25', 'Christmas Day')
on conflict (market, holiday_date) do update
    set name = excluded.name;

-- Ensure anon can read market holidays so new app installs / unauthenticated visitors see closures correctly
grant select on public.market_holidays to anon;

drop policy if exists market_holidays_anon_read on public.market_holidays;
create policy market_holidays_anon_read on public.market_holidays
    for select to anon using (true);
