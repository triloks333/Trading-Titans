ALTER TABLE public.fo_positions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own fo_positions" ON public.fo_positions;
DROP POLICY IF EXISTS "Users can insert own fo_positions" ON public.fo_positions;
DROP POLICY IF EXISTS "Users can update own fo_positions" ON public.fo_positions;
DROP POLICY IF EXISTS "Users can delete own fo_positions" ON public.fo_positions;

CREATE POLICY "Users can view own fo_positions"
  ON public.fo_positions
  FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own fo_positions"
  ON public.fo_positions
  FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own fo_positions"
  ON public.fo_positions
  FOR UPDATE
  TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can delete own fo_positions"
  ON public.fo_positions
  FOR DELETE
  TO authenticated
  USING (auth.uid() = user_id);
