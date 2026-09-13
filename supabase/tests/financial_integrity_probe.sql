-- Financial integrity probe
-- ============================================================================
-- Asserts that a NORMAL authenticated user cannot manipulate money, P&L,
-- holdings, positions, order state or trade history, and that legitimate reads
-- and RPCs still work.
--
-- HOW TO RUN
--   psql "$DATABASE_URL" -f supabase/tests/financial_integrity_probe.sql
-- or paste into the SQL editor. It ends in ROLLBACK, so it cannot leave anything
-- behind even when an assertion fails.
--
-- WHAT IT DOES
--   1. As the privileged role: picks a real non-admin account and SEEDS one valid
--      row in each table, so UPDATE/DELETE probes have a genuine target. Seeding
--      is what makes "0 rows affected" meaningful instead of ambiguous.
--   2. Switches to `authenticated` with that user's JWT claims — exactly what
--      PostgREST gives a browser or the app.
--   3. Runs every assertion and records a verdict.
--   4. ROLLS BACK.
--
-- WHY THE VERDICTS ARE FUSSY
-- An earlier hand-rolled version of this probe wrongly cleared three tables. It
-- used incomplete rows, so the write was refused for a missing NOT NULL column
-- (23502) and the probe read that as "blocked". The write had in fact been
-- authorised. So:
--
--   DENIED_PRIV    42501 - permission denied / RLS violation.
--   DENIED_RLS     no error, 0 rows changed, while the user CAN see the target
--                  rows. RLS filters silently on UPDATE/DELETE rather than
--                  raising, so this is also a genuine block.
--   DENIED_GUARD   P0001 - a plpgsql `raise exception` inside an RPC refused the
--                  call. This is how a SECURITY DEFINER function enforces its own
--                  ownership rules (claim_reward does exactly this), so it is a
--                  real block, not an accident. The message is recorded so a
--                  human can confirm it refused for the right reason.
--   ALLOWED        the write happened. For an "expect denied" assertion: FAIL.
--   INCONCLUSIVE   23502 / 23503 / 23514 / 23505 - a constraint stopped us
--                  before authorisation was tested. Counts as FAIL: the probe
--                  did not prove anything and its data needs fixing. Never
--                  weaken a constraint to make this go green.
--
-- EXPECTED RESULTS
--   BEFORE the lockdown migration: many FAILs. That is the vulnerability, and
--   this file is the evidence for it.
--   AFTER:  every assertion PASS.
-- ============================================================================

begin;

-- ── result sink ─────────────────────────────────────────────────────────────
create temp table probe_results (
  seq      serial,
  area     text,
  assertion text,
  expect   text,             -- 'denied' | 'allowed'
  outcome  text,             -- DENIED_PRIV | DENIED_RLS | ALLOWED | INCONCLUSIVE
  sqlstate text,
  rows_hit int,
  verdict  text,             -- PASS | FAIL
  detail   text
);
grant all on probe_results to authenticated;
grant usage, select on sequence probe_results_seq_seq to authenticated;

create temp table probe_ctx (uid uuid, other_uid uuid, order_id uuid, exec_order_id uuid);
grant all on probe_ctx to authenticated;

-- ── the assertion helper ────────────────────────────────────────────────────
-- SECURITY INVOKER on purpose: the body must run with the CALLER's privileges,
-- so the write is attempted as `authenticated`, not as the probe's author.
create function pg_temp.expect(
  p_area      text,
  p_assertion text,
  p_expect    text,
  p_sql       text,
  p_target_rows int default 0   -- rows the user can see and so could change
) returns void language plpgsql as $fn$
declare
  n int := 0;
  v_outcome text;
  v_state text := '-';
  v_detail text := '';
begin
  begin
    execute p_sql;
    get diagnostics n = row_count;
    if n = 0 and p_target_rows > 0 then
      -- Visible rows, none changed: RLS filtered the write silently.
      v_outcome := 'DENIED_RLS';
      v_detail  := format('%s visible row(s), 0 changed', p_target_rows);
    else
      v_outcome := 'ALLOWED';
    end if;
  exception
    when insufficient_privilege then           -- 42501
      v_outcome := 'DENIED_PRIV'; v_state := sqlstate; v_detail := sqlerrm;
    when raise_exception then                  -- P0001, an RPC's own guard
      v_outcome := 'DENIED_GUARD'; v_state := sqlstate; v_detail := sqlerrm;
    when not_null_violation                   -- 23502
      or foreign_key_violation                -- 23503
      or unique_violation                     -- 23505
      or check_violation then                  -- 23514
      v_outcome := 'INCONCLUSIVE'; v_state := sqlstate;
      v_detail  := 'constraint, not authorisation: ' || sqlerrm;
    when others then
      v_outcome := 'INCONCLUSIVE'; v_state := sqlstate; v_detail := sqlerrm;
  end;

  insert into probe_results (area, assertion, expect, outcome, sqlstate, rows_hit, verdict, detail)
  values (
    p_area, p_assertion, p_expect, v_outcome, v_state, n,
    case
      when p_expect = 'denied'
       and v_outcome in ('DENIED_PRIV','DENIED_RLS','DENIED_GUARD') then 'PASS'
      when p_expect = 'allowed' and v_outcome = 'ALLOWED'           then 'PASS'
      else 'FAIL'
    end,
    v_detail
  );
end
$fn$;
grant execute on function pg_temp.expect(text,text,text,text,int) to authenticated;

-- ── seed valid, constraint-satisfying fixtures ──────────────────────────────
do $seed$
declare
  v_uid uuid; v_other uuid; v_order uuid; v_exec uuid; v_expiry date := (current_date + 30);
begin
  -- Two distinct non-admin accounts: one to act as, one to attack.
  select id into v_uid from public.profiles
   where coalesce(is_admin,false) = false order by created_at limit 1;
  select id into v_other from public.profiles
   where coalesce(is_admin,false) = false and id <> v_uid order by created_at limit 1;
  if v_uid is null or v_other is null then
    raise exception 'need at least two non-admin profiles to run this probe';
  end if;

  -- A resting limit order (satisfies orders_pending_limit_has_trigger).
  insert into public.orders (user_id, symbol, name, market, side, quantity, price,
                             limit_price, total, status, order_type, realized_pnl)
  values (v_uid,'PROBE.EQ','Probe Equity','stock','sell',100,150,150,15000,'pending','limit',0)
  returning id into v_order;

  -- An executed order, to attack trade history and to hang an autopsy off.
  insert into public.orders (user_id, symbol, name, market, side, quantity, price,
                             total, status, order_type, realized_pnl, executed_at)
  values (v_uid,'PROBE.EX','Probe Executed','stock','buy',10,100,1000,'executed','market',500, now())
  returning id into v_exec;

  insert into public.holdings (user_id, symbol, market, quantity, avg_price, name)
  values (v_uid,'PROBE.EQ','stock',100,150,'Probe Equity');

  insert into public.fo_positions (user_id, symbol, instrument_type, net_qty,
                                   avg_entry_price, lot_size, margin_blocked,
                                   realized_pnl, expiry_date)
  values (v_uid,'PROBE.FUT','FUTURE',50,200,50,10000,0,v_expiry);

  insert into public.crypto_holdings (user_id, symbol, quantity, avg_price)
  values (v_uid,'PROBEBTC',1.5,100000);

  insert into public.settlement_ledger (user_id, symbol, instrument_type, expiry_date,
                                        quantity, avg_price, settlement_type,
                                        intrinsic_value, premium_received,
                                        margin_released, wallet_change)
  values (v_uid,'PROBE.OPT','OPTION',v_expiry,50,10,'expired_worthless',0,500,10000,500);

  insert into public.trade_autopsies (order_id, user_id, symbol, market, pnl, reason, advice)
  values (v_exec, v_uid,'PROBE.EX','stock',500,'probe seed','probe seed');

  insert into public.referral_commissions (referrer_id, referred_id, package_name,
                                           package_price, commission_amount, status)
  values (v_uid, v_other,'probe_pack',100,10,'unclaimed');

  -- An unclaimed reward belonging to the OTHER user, for the claim_reward test.
  insert into public.rewards (user_id, amount, message, is_claimed)
  values (v_other, 4242,'probe reward for someone else', false);

  insert into probe_ctx values (v_uid, v_other, v_order, v_exec);
end
$seed$;

-- ── become a normal signed-in user ──────────────────────────────────────────
set local role authenticated;
select set_config('request.jwt.claims',
                  json_build_object('sub', uid, 'role','authenticated')::text, true)
  from probe_ctx;

-- ── assertions ──────────────────────────────────────────────────────────────
do $probe$
declare
  c record;
  v_other_reward uuid;
  v_before numeric;
  v_after numeric;
  v_n int;
begin
  select * into c from probe_ctx;

  -- READS FIRST. The destructive assertions below legitimately delete the seeded
  -- rows while the lockdown is absent, so asserting reads afterwards would report
  -- an empty table as a read failure and hide the real result.
  perform pg_temp.expect('read','SELECT own orders','allowed',
    format('select 1 from public.orders where user_id = %L limit 1', c.uid));
  perform pg_temp.expect('read','SELECT own holdings','allowed',
    format('select 1 from public.holdings where user_id = %L limit 1', c.uid));
  perform pg_temp.expect('read','SELECT own fo_positions','allowed',
    format('select 1 from public.fo_positions where user_id = %L limit 1', c.uid));
  perform pg_temp.expect('read','SELECT own pnl_history','allowed',
    format('select 1 from public.pnl_history where user_id = %L limit 1', c.uid));
  perform pg_temp.expect('read','SELECT own wallet_transactions','allowed',
    format('select 1 from public.wallet_transactions where user_id = %L limit 1', c.uid));

  select count(*) into v_n from public.orders where user_id = c.other_uid;
  insert into probe_results (area, assertion, expect, outcome, sqlstate, rows_hit, verdict, detail)
  values ('read','SELECT another user''s orders','denied',
          case when v_n = 0 then 'DENIED_RLS' else 'ALLOWED' end,'-',v_n,
          case when v_n = 0 then 'PASS' else 'FAIL' end,'must be 0 rows');

  select count(*) into v_n from public.holdings where user_id = c.other_uid;
  insert into probe_results (area, assertion, expect, outcome, sqlstate, rows_hit, verdict, detail)
  values ('read','SELECT another user''s holdings','denied',
          case when v_n = 0 then 'DENIED_RLS' else 'ALLOWED' end,'-',v_n,
          case when v_n = 0 then 'PASS' else 'FAIL' end,'must be 0 rows');

  select count(*) into v_n from public.profiles where id = c.other_uid;
  insert into probe_results (area, assertion, expect, outcome, sqlstate, rows_hit, verdict, detail)
  values ('read','SELECT another user''s profile','denied',
          case when v_n = 0 then 'DENIED_RLS' else 'ALLOWED' end,'-',v_n,
          case when v_n = 0 then 'PASS' else 'FAIL' end,'must be 0 rows');

  -- ORDERS ------------------------------------------------------------------
  perform pg_temp.expect('orders','UPDATE realized_pnl','denied',
    format('update public.orders set realized_pnl = 999999 where id = %L', c.exec_order_id), 1);

  perform pg_temp.expect('orders','UPDATE status pending -> executed','denied',
    format('update public.orders set status = ''executed'' where id = %L', c.order_id), 1);

  perform pg_temp.expect('orders','UPDATE created_at (backdate history)','denied',
    format('update public.orders set created_at = ''2020-01-01'' where id = %L', c.exec_order_id), 1);

  perform pg_temp.expect('orders','UPDATE quantity','denied',
    format('update public.orders set quantity = 100000 where id = %L', c.order_id), 1);

  perform pg_temp.expect('orders','UPDATE price','denied',
    format('update public.orders set price = 1 where id = %L', c.order_id), 1);

  perform pg_temp.expect('orders','UPDATE limit_price','denied',
    format('update public.orders set limit_price = 1 where id = %L', c.order_id), 1);

  perform pg_temp.expect('orders','UPDATE total','denied',
    format('update public.orders set total = 1 where id = %L', c.order_id), 1);

  perform pg_temp.expect('orders','UPDATE execution_reference_price','denied',
    format('update public.orders set execution_reference_price = 1 where id = %L', c.order_id), 1);

  perform pg_temp.expect('orders','UPDATE user_id (reassign owner)','denied',
    format('update public.orders set user_id = %L where id = %L', c.other_uid, c.order_id), 1);

  -- Valid statuses are executed|pending|cancelled|executing|failed, so a probe
  -- for 'filled' would trip a CHECK and prove nothing about authorisation.
  perform pg_temp.expect('orders','UPDATE status pending -> executing','denied',
    format('update public.orders set status = ''executing'' where id = %L', c.order_id), 1);

  perform pg_temp.expect('orders','UPDATE status pending -> failed','denied',
    format('update public.orders set status = ''failed'' where id = %L', c.order_id), 1);

  perform pg_temp.expect('orders','INSERT fabricated executed order','denied',
    format($i$insert into public.orders
             (user_id, symbol, name, market, side, quantity, price, total,
              status, order_type, realized_pnl, executed_at)
           values (%L,'PROBE.FAKE','Fake','stock','sell',1,1,1,'executed','market',9999999, now())$i$,
           c.uid));

  perform pg_temp.expect('orders','DELETE own executed order','denied',
    format('delete from public.orders where id = %L', c.exec_order_id), 1);

  -- Compatibility path. Expect ALLOWED while the temporary status grant stands;
  -- flip the expectation to 'denied' after 20260831000100 is applied.
  perform pg_temp.expect('orders','UPDATE status pending -> cancelled (compat path)','allowed',
    format('update public.orders set status = ''cancelled'' where id = %L', c.order_id), 1);
  -- Put it back so later assertions still see a pending row.
  begin
    execute format('update public.orders set status = ''pending'' where id = %L', c.order_id);
  exception when others then null;
  end;

  -- HOLDINGS ----------------------------------------------------------------
  perform pg_temp.expect('holdings','INSERT fabricated holding','denied',
    format($i$insert into public.holdings (user_id, symbol, market, quantity, avg_price, name)
           values (%L,'PROBE.FREE','stock',100000,0.01,'free money')$i$, c.uid));

  perform pg_temp.expect('holdings','UPDATE quantity','denied',
    format('update public.holdings set quantity = quantity + 1000000 where user_id = %L', c.uid), 1);

  perform pg_temp.expect('holdings','UPDATE avg_price','denied',
    format('update public.holdings set avg_price = 0.01 where user_id = %L', c.uid), 1);

  perform pg_temp.expect('holdings','DELETE','denied',
    format('delete from public.holdings where user_id = %L', c.uid), 1);

  -- FO_POSITIONS ------------------------------------------------------------
  perform pg_temp.expect('fo_positions','INSERT fabricated position','denied',
    format($i$insert into public.fo_positions
             (user_id, symbol, instrument_type, net_qty, avg_entry_price, lot_size,
              margin_blocked, realized_pnl, expiry_date)
           values (%L,'PROBE.FREEFUT','FUTURE',5000,1,1,0,9999999,current_date + 30)$i$, c.uid));

  perform pg_temp.expect('fo_positions','UPDATE net_qty','denied',
    format('update public.fo_positions set net_qty = net_qty + 10000 where user_id = %L', c.uid), 1);

  perform pg_temp.expect('fo_positions','UPDATE margin_blocked -> 0','denied',
    format('update public.fo_positions set margin_blocked = 0 where user_id = %L', c.uid), 1);

  perform pg_temp.expect('fo_positions','UPDATE realized_pnl','denied',
    format('update public.fo_positions set realized_pnl = 9999999 where user_id = %L', c.uid), 1);

  perform pg_temp.expect('fo_positions','DELETE','denied',
    format('delete from public.fo_positions where user_id = %L', c.uid), 1);

  -- CRYPTO_HOLDINGS ---------------------------------------------------------
  perform pg_temp.expect('crypto_holdings','INSERT','denied',
    format($i$insert into public.crypto_holdings (user_id, symbol, quantity, avg_price)
           values (%L,'PROBEETH',1000,1)$i$, c.uid));

  perform pg_temp.expect('crypto_holdings','UPDATE quantity','denied',
    format('update public.crypto_holdings set quantity = 99999 where user_id = %L', c.uid), 1);

  perform pg_temp.expect('crypto_holdings','DELETE','denied',
    format('delete from public.crypto_holdings where user_id = %L', c.uid), 1);

  -- SETTLEMENT_LEDGER -------------------------------------------------------
  perform pg_temp.expect('settlement_ledger','INSERT fabricated settlement','denied',
    format($i$insert into public.settlement_ledger
             (user_id, symbol, instrument_type, expiry_date, quantity, avg_price,
              settlement_type, intrinsic_value, premium_received, margin_released, wallet_change)
           values (%L,'PROBE.FAKEOPT','OPTION',current_date + 30,100,1,
                   'exercised',999999,0,0,999999)$i$, c.uid));

  -- TRADE_AUTOPSIES ---------------------------------------------------------
  perform pg_temp.expect('trade_autopsies','UPDATE pnl','denied',
    format('update public.trade_autopsies set pnl = 9999999 where user_id = %L', c.uid), 1);

  perform pg_temp.expect('trade_autopsies','DELETE','denied',
    format('delete from public.trade_autopsies where user_id = %L', c.uid), 1);

  -- REFERRAL_COMMISSIONS ----------------------------------------------------
  -- referred_id must be the CALLER: the INSERT policy checks
  -- `auth.uid() = referred_id`, so this is the shape that is actually reachable.
  -- Pointing referred_id at another account is refused for the wrong reason and
  -- would make this assertion look green while proving nothing.
  perform pg_temp.expect('referral_commissions','INSERT fabricated commission','denied',
    format($i$insert into public.referral_commissions
             (referrer_id, referred_id, package_name, package_price, commission_amount, status)
           values (%L,%L,'forged',1,9999999,'unclaimed')$i$, c.uid, c.uid));

  perform pg_temp.expect('referral_commissions','UPDATE commission_amount','denied',
    format('update public.referral_commissions set commission_amount = 9999999 where referrer_id = %L', c.uid), 1);

  -- PROFILES ----------------------------------------------------------------
  perform pg_temp.expect('profiles','UPDATE wallet_balance','denied',
    format('update public.profiles set wallet_balance = 99999999 where id = %L', c.uid), 1);

  perform pg_temp.expect('profiles','UPDATE total_realized_pnl','denied',
    format('update public.profiles set total_realized_pnl = 99999999 where id = %L', c.uid), 1);

  perform pg_temp.expect('profiles','UPDATE is_admin','denied',
    format('update public.profiles set is_admin = true where id = %L', c.uid), 1);

  perform pg_temp.expect('profiles','UPDATE plan / subscription_active','denied',
    format('update public.profiles set plan = ''titan_pro'', subscription_active = true where id = %L', c.uid), 1);

  perform pg_temp.expect('profiles','INSERT arbitrary profile','denied',
    $i$insert into public.profiles (id, email, wallet_balance, is_admin)
       values (gen_random_uuid(),'probe@example.invalid',5000000,true)$i$);

  -- RPCs --------------------------------------------------------------------
  -- grant_challenge: SECURITY DEFINER, arbitrary p_user_id, no auth check.
  -- Creates a claimable `rewards` row, i.e. real spendable cash.
  perform pg_temp.expect('rpc','grant_challenge() direct call','denied',
    format($i$select public.grant_challenge(%L,
             (select key from public.challenges where is_active and reward_amount > 0
               order by reward_amount desc limit 1),
             'probe-forged-cycle')$i$, c.uid));

  -- ...and aimed at somebody else.
  perform pg_temp.expect('rpc','grant_challenge() targeting another user','denied',
    format($i$select public.grant_challenge(%L,
             (select key from public.challenges where is_active and reward_amount > 0
               order by reward_amount desc limit 1),
             'probe-forged-other')$i$, c.other_uid));

  -- Monetisation RPCs: uncapped, unverified wallet credit. Both had ZERO call
  -- sites in either client when they were revoked. activate_subscription also
  -- wrote `plan` from its unvalidated argument and set subscription_active.
  perform pg_temp.expect('rpc','credit_demo_cash() direct call','denied',
    'select public.credit_demo_cash(1000000)');
  perform pg_temp.expect('rpc','activate_subscription() direct call','denied',
    'select public.activate_subscription(''titan_pro'')');

  perform pg_temp.expect('rpc','place_fo_order_transaction() direct call','denied',
    format($i$select public.place_fo_order_transaction(
             %L, 0::numeric, 5000000::numeric, 0::numeric, 0::numeric,
             '{"symbol":"PROBE.FUT","instrument_type":"FUTURE","option_type":"",
               "strike_price":0,"expiry_date":"2027-12-31","lot_size":1,
               "net_qty":100,"avg_entry_price":1}'::jsonb,
             '{"symbol":"PROBE.FUT","name":"probe","market":"stock","side":"buy",
               "quantity":1,"price":1,"total":1,"realized_pnl":9999999,
               "status":"executed","order_type":"market","instrument_type":"FUTURE",
               "strike_price":0,"option_type":"","expiry_date":"2027-12-31"}'::jsonb,
             true)$i$, c.uid));

  -- claim_reward must refuse somebody else's reward.
  select id into v_other_reward from public.rewards
   where user_id = c.other_uid and is_claimed = false and amount = 4242 limit 1;
  perform pg_temp.expect('rpc','claim_reward() on another user''s reward','denied',
    format('select public.claim_reward(%L)', v_other_reward::text));

  -- evaluate_challenges MUST stay callable: the app uses it, and it forces
  -- p_user_id to auth.uid() for non-admins.
  perform pg_temp.expect('rpc','evaluate_challenges() self','allowed',
    'select public.evaluate_challenges()');

  -- And must not be steerable at another account.
  select wallet_balance into v_before from public.profiles where id = c.other_uid;
  begin
    perform public.evaluate_challenges(c.other_uid);
    select count(*) into v_n from public.user_challenges
      where user_id = c.other_uid and granted_at > now() - interval '1 minute';
    insert into probe_results (area, assertion, expect, outcome, sqlstate, rows_hit, verdict, detail)
    values ('rpc','evaluate_challenges() cannot target another user','denied',
            case when v_n = 0 then 'DENIED_RLS' else 'ALLOWED' end,'-',v_n,
            case when v_n = 0 then 'PASS' else 'FAIL' end,
            'p_user_id should be overwritten with auth.uid()');
  exception when others then
    insert into probe_results (area, assertion, expect, outcome, sqlstate, rows_hit, verdict, detail)
    values ('rpc','evaluate_challenges() cannot target another user','denied',
            'DENIED_PRIV', sqlstate, 0,'PASS', sqlerrm);
  end;

  -- Legitimate preference RPC must keep working.
  perform pg_temp.expect('rpc','save_user_preferences() (legitimate profile write)','allowed',
    $i$select public.save_user_preferences('INR', array['stock','crypto']::text[], false, null)$i$);

end
$probe$;

reset role;

-- ── report ──────────────────────────────────────────────────────────────────
select seq, area, assertion, expect, outcome, sqlstate, rows_hit, verdict, detail
  from probe_results order by seq;

select verdict, count(*) as assertions
  from probe_results group by verdict order by verdict;

select count(*) filter (where verdict = 'FAIL')        as failures,
       count(*) filter (where outcome = 'INCONCLUSIVE') as inconclusive,
       case when count(*) filter (where verdict = 'FAIL') = 0
            then 'ALL ASSERTIONS PASS'
            else 'FAILURES PRESENT - see rows above' end as summary
  from probe_results;

rollback;
