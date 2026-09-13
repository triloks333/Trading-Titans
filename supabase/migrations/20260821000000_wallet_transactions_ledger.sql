-- Wallet statement: an append-only ledger of every change to
-- profiles.wallet_balance, so the Wallet tab can show the user's OWN money
-- history instead of re-listing their orders.
--
-- ─────────────────────────────────────────────────────────────────────────────
-- SAFETY INVARIANTS. This migration must not be able to lose or alter anyone's
-- demo cash, so:
--
--   1. NO money path is modified. Not the execution engine, not
--      place_fo_order_transaction, not claim_reward / credit_demo_cash /
--      activate_subscription / apply_referral_code / handle_new_user. Balances
--      are captured by OBSERVING profiles.wallet_balance from a trigger, which
--      means every existing path — and any future one — is recorded for free.
--   2. The ledger is never the source of truth. profiles.wallet_balance remains
--      authoritative; these rows are a read-only record derived from it.
--   3. A ledger failure can NEVER roll back a money movement. The whole trigger
--      body sits inside BEGIN ... EXCEPTION WHEN OTHERS, so if this table is
--      dropped, full, or locked, the balance update still commits and the user
--      simply misses one history row.
--   4. Clients cannot write here. RLS grants SELECT only; the sole writer is the
--      SECURITY DEFINER trigger below.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.wallet_transactions (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id        UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    -- Signed delta: positive credits the wallet, negative debits it. NUMERIC
    -- without precision, matching profiles.wallet_balance, so nothing rounds.
    amount         NUMERIC NOT NULL,
    balance_before NUMERIC NOT NULL,
    balance_after  NUMERIC NOT NULL,
    -- 'opening' | 'trade' | 'referral' | 'plan' | 'credit', plus anything a
    -- future caller sets via the app.wallet_reason hint. Deliberately NOT a
    -- CHECK constraint: a rejected row would be a silently missing statement
    -- line, and completeness matters more here than a tidy vocabulary.
    kind           TEXT NOT NULL,
    description    TEXT,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_wallet_transactions_user_created
    ON public.wallet_transactions(user_id, created_at DESC);

ALTER TABLE public.wallet_transactions ENABLE ROW LEVEL SECURITY;

-- Read-only for the owner (admins too, so support can reconcile a balance).
DROP POLICY IF EXISTS "Users can view own wallet transactions" ON public.wallet_transactions;
CREATE POLICY "Users can view own wallet transactions"
    ON public.wallet_transactions FOR SELECT
    TO authenticated
    USING ((select auth.uid()) = user_id OR public.is_admin());

-- No INSERT/UPDATE/DELETE policy on purpose: only the trigger function writes,
-- and it is SECURITY DEFINER so it bypasses RLS. This keeps the statement
-- tamper-proof from the client even though profiles is still client-writable.

-- ─────────────────────────────────────────────────────────────────────────────
-- The only writer.
--
-- `kind` is inferred from what else changed on the row in the same statement,
-- because a bare balance delta does not say why it moved:
--
--   total_realized_pnl changed  -> a trade settled (covers sells, F&O closes,
--                                  expiry settlement)
--   referred_by NULL -> set     -> the referee's signup bonus
--   plan changed                -> a plan credit
--   delta < 0                   -> a trade. Trades are the ONLY thing in the app
--                                  that debits a wallet, so an unexplained debit
--                                  is a buy or a margin block.
--   otherwise (delta > 0)       -> 'credit': a claimed reward/challenge payout,
--                                  a self top-up, or being credited as the
--                                  referrer. These are indistinguishable from
--                                  here because each only touches wallet_balance.
--
-- ponytail: that last bucket is the known ceiling — three different credit
-- sources collapse into one label. Upgrade path without touching this function:
-- a caller runs
--     PERFORM set_config('app.wallet_reason', 'reward_claim', true);
-- before its UPDATE, and the hint below is used verbatim instead of the guess.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.record_wallet_transaction()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
    v_before NUMERIC := 0;
    v_after  NUMERIC := 0;
    v_delta  NUMERIC := 0;
    v_kind   TEXT;
    v_desc   TEXT;
    v_hint   TEXT;
BEGIN
    -- Everything is inside this block so that ANY failure here is swallowed and
    -- the surrounding money update still commits (invariant 3).
    BEGIN
        IF TG_OP = 'INSERT' THEN
            v_before := 0;
            v_after  := COALESCE(NEW.wallet_balance, 0);
        ELSE
            v_before := COALESCE(OLD.wallet_balance, 0);
            v_after  := COALESCE(NEW.wallet_balance, 0);
        END IF;

        v_delta := v_after - v_before;

        IF v_delta <> 0 THEN
            -- missing_ok = true, so this is NULL when no caller set a hint.
            v_hint := NULLIF(current_setting('app.wallet_reason', true), '');

            IF TG_OP = 'INSERT' THEN
                v_kind := 'opening';
                v_desc := 'Opening demo cash balance';
            ELSIF v_hint IS NOT NULL THEN
                v_kind := v_hint;
                v_desc := NULL;
            ELSIF OLD.total_realized_pnl IS DISTINCT FROM NEW.total_realized_pnl THEN
                v_kind := 'trade';
                v_desc := CASE WHEN v_delta > 0 THEN 'Trade proceeds' ELSE 'Trade cost' END;
            ELSIF OLD.referred_by IS NULL AND NEW.referred_by IS NOT NULL THEN
                v_kind := 'referral';
                v_desc := 'Referral bonus';
            ELSIF OLD.plan IS DISTINCT FROM NEW.plan THEN
                v_kind := 'plan';
                v_desc := 'Plan credit';
            ELSIF v_delta < 0 THEN
                v_kind := 'trade';
                v_desc := 'Trade cost';
            ELSE
                v_kind := 'credit';
                v_desc := 'Demo cash credited';
            END IF;

            INSERT INTO public.wallet_transactions (
                user_id, amount, balance_before, balance_after, kind, description
            ) VALUES (
                NEW.id, v_delta, v_before, v_after, v_kind, v_desc
            );
        END IF;
    EXCEPTION WHEN OTHERS THEN
        -- Deliberately silent. Losing a history row is acceptable; rolling back
        -- a user's trade or reward because of bookkeeping is not.
        NULL;
    END;

    RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.record_wallet_transaction() FROM PUBLIC;

-- Opening balance for every new account (handle_new_user inserts the profile).
DROP TRIGGER IF EXISTS trg_wallet_tx_on_profile_insert ON public.profiles;
CREATE TRIGGER trg_wallet_tx_on_profile_insert
    AFTER INSERT ON public.profiles
    FOR EACH ROW
    EXECUTE FUNCTION public.record_wallet_transaction();

-- Every subsequent balance change, whoever made it. The WHEN clause means the
-- trigger does not even fire for the many profile updates that leave the balance
-- alone (login streaks, XP, preferences).
DROP TRIGGER IF EXISTS trg_wallet_tx_on_balance_change ON public.profiles;
CREATE TRIGGER trg_wallet_tx_on_balance_change
    AFTER UPDATE OF wallet_balance ON public.profiles
    FOR EACH ROW
    WHEN (OLD.wallet_balance IS DISTINCT FROM NEW.wallet_balance)
    EXECUTE FUNCTION public.record_wallet_transaction();

-- ─────────────────────────────────────────────────────────────────────────────
-- Backfill. Existing accounts have a balance but no history, so without this
-- their statement would start mid-story and never reconcile. One "brought
-- forward" line per account, equal to the balance they hold right now; every
-- change from here on is recorded by the triggers above.
--
-- Guarded by NOT EXISTS, so re-running this migration adds nothing and can
-- never double-count.
-- ─────────────────────────────────────────────────────────────────────────────
INSERT INTO public.wallet_transactions (
    user_id, amount, balance_before, balance_after, kind, description, created_at
)
SELECT p.id,
       COALESCE(p.wallet_balance, 0),
       0,
       COALESCE(p.wallet_balance, 0),
       'opening',
       'Balance brought forward',
       COALESCE(p.created_at, NOW())
FROM public.profiles p
WHERE NOT EXISTS (
    SELECT 1 FROM public.wallet_transactions w WHERE w.user_id = p.id
);
