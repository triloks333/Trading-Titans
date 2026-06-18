-- Exit-order support for place_fo_order_transaction.
--
-- Adds a trailing parameter `p_skip_balance_check BOOLEAN DEFAULT FALSE` so exit/
-- close orders bypass the internal balance guard (closing a position reduces
-- exposure and releases capital, so it must never be blocked on balance).
-- DEFAULT FALSE keeps every existing 7-arg call signature identical and
-- backward-compatible.
--
-- IMPORTANT: this definition is based on the CURRENT live function (which
-- includes the charges + net-realized-P&L logic added by later migrations:
-- the wallet update subtracts total_charges, and the orders INSERT records
-- charge_config_id/brokerage/stamp_duty/tax_charges/total_charges). Do NOT
-- regenerate this from the original base RPC or those columns will be lost.
--
-- search_path is pinned to (public, pg_temp) to resolve the
-- function_search_path_mutable security advisor while keeping the existing
-- unqualified table references (profiles, fo_positions, orders) resolvable.
CREATE OR REPLACE FUNCTION public.place_fo_order_transaction(
  p_user_id uuid,
  p_wallet_debit numeric,
  p_wallet_credit numeric,
  p_margin_blocked numeric,
  p_margin_released numeric,
  p_position_data jsonb,
  p_order_data jsonb,
  p_skip_balance_check boolean DEFAULT false
)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path = public, pg_temp
AS $function$
DECLARE
  v_balance NUMERIC;
BEGIN
  -- 1. Lock profile row & verify balance (skipped for exits/closes)
  SELECT wallet_balance INTO v_balance FROM profiles WHERE id = p_user_id FOR UPDATE;
  IF NOT p_skip_balance_check AND v_balance + p_wallet_credit - p_wallet_debit < 0 THEN
    RAISE EXCEPTION 'Insufficient balance inside transaction.';
  END IF;

  -- 2. Update wallet balance and net realized P&L
  UPDATE profiles
  SET wallet_balance = wallet_balance + p_wallet_credit - p_wallet_debit,
      total_realized_pnl = total_realized_pnl + COALESCE((p_order_data->>'realized_pnl')::NUMERIC, 0) - COALESCE((p_order_data->>'total_charges')::NUMERIC, 0)
  WHERE id = p_user_id;

  -- 3. Upsert position
  IF (p_position_data->>'net_qty')::INT = 0 THEN
    -- Delete ONLY the exact closed contract
    DELETE FROM fo_positions
    WHERE user_id = p_user_id
      AND symbol = p_position_data->>'symbol'
      AND instrument_type = p_position_data->>'instrument_type'
      AND option_type = p_position_data->>'option_type'
      AND strike_price = (p_position_data->>'strike_price')::NUMERIC
      AND expiry_date = (p_position_data->>'expiry_date')::DATE
      AND is_settled = FALSE;
  ELSE
    INSERT INTO fo_positions (
      user_id, symbol, instrument_type, option_type, strike_price, expiry_date, lot_size, net_qty, avg_entry_price, margin_blocked
    ) VALUES (
      p_user_id,
      p_position_data->>'symbol',
      p_position_data->>'instrument_type',
      p_position_data->>'option_type',
      (p_position_data->>'strike_price')::NUMERIC,
      (p_position_data->>'expiry_date')::DATE,
      (p_position_data->>'lot_size')::INT,
      (p_position_data->>'net_qty')::INT,
      (p_position_data->>'avg_entry_price')::NUMERIC,
      p_margin_blocked
    )
    ON CONFLICT (user_id, symbol, instrument_type, option_type, strike_price, expiry_date) WHERE is_settled = FALSE
    DO UPDATE SET
      net_qty = EXCLUDED.net_qty,
      avg_entry_price = EXCLUDED.avg_entry_price,
      margin_blocked = EXCLUDED.margin_blocked;
  END IF;

  -- 4. Record order details with charges
  INSERT INTO orders (
    user_id, symbol, name, market, side, quantity, price, total, realized_pnl, status, order_type, executed_at, instrument_type, strike_price, option_type, expiry_date,
    charge_config_id, brokerage, stamp_duty, tax_charges, total_charges
  ) VALUES (
    p_user_id,
    p_order_data->>'symbol',
    p_order_data->>'name',
    p_order_data->>'market',
    p_order_data->>'side',
    (p_order_data->>'quantity')::NUMERIC,
    (p_order_data->>'price')::NUMERIC,
    (p_order_data->>'total')::NUMERIC,
    (p_order_data->>'realized_pnl')::NUMERIC,
    p_order_data->>'status',
    p_order_data->>'order_type',
    NOW(),
    p_order_data->>'instrument_type',
    (p_order_data->>'strike_price')::NUMERIC,
    p_order_data->>'option_type',
    (p_order_data->>'expiry_date')::DATE,
    (p_order_data->>'charge_config_id')::UUID,
    COALESCE((p_order_data->>'brokerage')::NUMERIC, 0.0),
    COALESCE((p_order_data->>'stamp_duty')::NUMERIC, 0.0),
    COALESCE((p_order_data->>'tax_charges')::NUMERIC, 0.0),
    COALESCE((p_order_data->>'total_charges')::NUMERIC, 0.0)
  );
END;
$function$;

-- Drop the original 7-arg overload so 7-arg calls (non-exit orders from the
-- Dart client) unambiguously resolve to the new 8-arg function above.
DROP FUNCTION IF EXISTS public.place_fo_order_transaction(
  uuid, numeric, numeric, numeric, numeric, jsonb, jsonb
);
