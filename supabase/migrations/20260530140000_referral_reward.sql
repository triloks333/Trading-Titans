-- Update public.handle_new_user function to award referral bonuses
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
DECLARE
  ref_by UUID;
  initial_bal NUMERIC := 11000.0;
BEGIN
  ref_by := (new.raw_user_meta_data->>'referred_by')::UUID;
  
  IF ref_by IS NOT NULL THEN
    initial_bal := initial_bal + 5000.0;
    -- Award 5000 dummy cash to referrer
    UPDATE public.profiles 
    SET wallet_balance = wallet_balance + 5000.0 
    WHERE id = ref_by;
  END IF;

  INSERT INTO public.profiles (id, email, name, wallet_balance, subscription_active, plan, total_realized_pnl, referred_by)
  VALUES (
    new.id, 
    new.email, 
    COALESCE(new.raw_user_meta_data->>'name', split_part(new.email, '@', 1)),
    initial_bal, 
    true, 
    'free_starter', 
    0.0,
    ref_by
  );
  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
