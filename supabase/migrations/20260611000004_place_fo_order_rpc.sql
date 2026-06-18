CREATE OR REPLACE FUNCTION place_fo_order_transaction(
  p_user_id UUID,
  p_wallet_debit NUMERIC,
  p_wallet_credit NUMERIC,
  p_margin_blocked NUMERIC,
  p_margin_released NUMERIC,
  p_position_data JSONB,
  p_order_data JSONB
) RETURNS VOID AS $$
DECLARE
  v_balance NUMERIC;
BEGIN
  -- 1. Lock profile row & verify balance
  SELECT wallet_balance INTO v_balance FROM profiles WHERE id = p_user_id FOR UPDATE;
  IF v_balance + p_wallet_credit - p_wallet_debit < 0 THEN
    RAISE EXCEPTION 'Insufficient balance inside transaction.';
  END IF;

  -- 2. Update wallet balance
  UPDATE profiles 
  SET wallet_balance = wallet_balance + p_wallet_credit - p_wallet_debit,
      total_realized_pnl = total_realized_pnl + COALESCE((p_order_data->>'realized_pnl')::NUMERIC, 0)
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

  -- 4. Record order details
  INSERT INTO orders (
    user_id, symbol, name, market, side, quantity, price, total, realized_pnl, status, order_type, executed_at, instrument_type, strike_price, option_type, expiry_date
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
    (p_order_data->>'expiry_date')::DATE
  );
END;
$$ LANGUAGE plpgsql;
