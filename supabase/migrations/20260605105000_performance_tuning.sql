-- 1. Create indexes for unindexed foreign keys (unindexed_foreign_keys)
CREATE INDEX IF NOT EXISTS idx_profiles_referred_by ON public.profiles(referred_by);
CREATE INDEX IF NOT EXISTS idx_referral_commissions_referred_id ON public.referral_commissions(referred_id);
CREATE INDEX IF NOT EXISTS idx_support_tickets_user_id ON public.support_tickets(user_id);
CREATE INDEX IF NOT EXISTS idx_waitlist_referred_by ON public.waitlist(referred_by);


-- 2. Tune RLS Policies to prevent re-evaluation of auth.uid() (auth_rls_initplan)

-- A. Table: public.profiles
DROP POLICY IF EXISTS "Users can read own profile" ON public.profiles;
CREATE POLICY "Users can read own profile" ON public.profiles 
    FOR SELECT USING ((select auth.uid()) = id);

DROP POLICY IF EXISTS "Users can update their own profile" ON public.profiles;
CREATE POLICY "Users can update their own profile" ON public.profiles 
    FOR UPDATE USING ((select auth.uid()) = id);


-- B. Table: public.orders
DROP POLICY IF EXISTS "Users can view own orders" ON public.orders;
CREATE POLICY "Users can view own orders" ON public.orders 
    FOR SELECT USING ((select auth.uid()) = user_id);

DROP POLICY IF EXISTS "Users can insert own orders" ON public.orders;
CREATE POLICY "Users can insert own orders" ON public.orders 
    FOR INSERT WITH CHECK ((select auth.uid()) = user_id);

DROP POLICY IF EXISTS "Users can update their own orders" ON public.orders;
CREATE POLICY "Users can update their own orders" ON public.orders 
    FOR UPDATE USING ((select auth.uid()) = user_id);


-- C. Table: public.holdings
DROP POLICY IF EXISTS "Users can view own holdings" ON public.holdings;
CREATE POLICY "Users can view own holdings" ON public.holdings 
    FOR SELECT USING ((select auth.uid()) = user_id);

DROP POLICY IF EXISTS "Users can insert own holdings" ON public.holdings;
CREATE POLICY "Users can insert own holdings" ON public.holdings 
    FOR INSERT WITH CHECK ((select auth.uid()) = user_id);

DROP POLICY IF EXISTS "Users can update own holdings" ON public.holdings;
CREATE POLICY "Users can update own holdings" ON public.holdings 
    FOR UPDATE USING ((select auth.uid()) = user_id);

DROP POLICY IF EXISTS "Users can delete own holdings" ON public.holdings;
CREATE POLICY "Users can delete own holdings" ON public.holdings 
    FOR DELETE USING ((select auth.uid()) = user_id);


-- D. Table: public.watchlist
DROP POLICY IF EXISTS "Users can view own watchlist" ON public.watchlist;
CREATE POLICY "Users can view own watchlist" ON public.watchlist 
    FOR SELECT USING ((select auth.uid()) = user_id);

DROP POLICY IF EXISTS "Users can insert own watchlist" ON public.watchlist;
CREATE POLICY "Users can insert own watchlist" ON public.watchlist 
    FOR INSERT WITH CHECK ((select auth.uid()) = user_id);

DROP POLICY IF EXISTS "Users can update their own watchlist" ON public.watchlist;
CREATE POLICY "Users can update their own watchlist" ON public.watchlist 
    FOR UPDATE USING ((select auth.uid()) = user_id);

DROP POLICY IF EXISTS "Users can delete own watchlist" ON public.watchlist;
CREATE POLICY "Users can delete own watchlist" ON public.watchlist 
    FOR DELETE USING ((select auth.uid()) = user_id);


-- E. Table: public.referral_commissions
DROP POLICY IF EXISTS "Users can view their own referral commissions" ON public.referral_commissions;
CREATE POLICY "Users can view their own referral commissions" ON public.referral_commissions 
    FOR SELECT USING ((select auth.uid()) = referrer_id);

DROP POLICY IF EXISTS "Users can update their own referral commissions" ON public.referral_commissions;
CREATE POLICY "Users can update their own referral commissions" ON public.referral_commissions 
    FOR UPDATE USING ((select auth.uid()) = referrer_id);


-- F. Table: public.notifications
DROP POLICY IF EXISTS "Users can view own notifications" ON public.notifications;
CREATE POLICY "Users can view own notifications" ON public.notifications 
    FOR SELECT USING ((select auth.uid()) = user_id);

DROP POLICY IF EXISTS "Users can insert own notifications" ON public.notifications;
CREATE POLICY "Users can insert own notifications" ON public.notifications 
    FOR INSERT WITH CHECK ((select auth.uid()) = user_id);

DROP POLICY IF EXISTS "Users can update own notifications" ON public.notifications;
CREATE POLICY "Users can update own notifications" ON public.notifications 
    FOR UPDATE USING ((select auth.uid()) = user_id);

DROP POLICY IF EXISTS "Users can delete own notifications" ON public.notifications;
CREATE POLICY "Users can delete own notifications" ON public.notifications 
    FOR DELETE USING ((select auth.uid()) = user_id);


-- G. Table: public.trade_autopsies
DROP POLICY IF EXISTS "Users can view own trade autopsies" ON public.trade_autopsies;
CREATE POLICY "Users can view own trade autopsies" ON public.trade_autopsies 
    FOR SELECT USING ((select auth.uid()) = user_id);

DROP POLICY IF EXISTS "Users can insert own trade autopsies" ON public.trade_autopsies;
CREATE POLICY "Users can insert own trade autopsies" ON public.trade_autopsies 
    FOR INSERT WITH CHECK ((select auth.uid()) = user_id);

DROP POLICY IF EXISTS "Users can update own trade autopsies" ON public.trade_autopsies;
CREATE POLICY "Users can update own trade autopsies" ON public.trade_autopsies 
    FOR UPDATE USING ((select auth.uid()) = user_id);

DROP POLICY IF EXISTS "Users can delete own trade autopsies" ON public.trade_autopsies;
CREATE POLICY "Users can delete own trade autopsies" ON public.trade_autopsies 
    FOR DELETE USING ((select auth.uid()) = user_id);


-- H. Table: public.support_tickets
DROP POLICY IF EXISTS "Select support tickets" ON public.support_tickets;
CREATE POLICY "Select support tickets" ON public.support_tickets 
    FOR SELECT USING ((select auth.uid()) = user_id);

DROP POLICY IF EXISTS "Insert support tickets" ON public.support_tickets;
CREATE POLICY "Insert support tickets" ON public.support_tickets 
    FOR INSERT WITH CHECK ((select auth.uid()) = user_id);

DROP POLICY IF EXISTS "Update support tickets" ON public.support_tickets;
CREATE POLICY "Update support tickets" ON public.support_tickets 
    FOR UPDATE USING ((select auth.uid()) = user_id);


-- I. Table: public.rewards
DROP POLICY IF EXISTS "Users can view own rewards" ON public.rewards;
CREATE POLICY "Users can view own rewards" ON public.rewards 
    FOR SELECT USING ((select auth.uid()) = user_id);

DROP POLICY IF EXISTS "Users can update own rewards" ON public.rewards;
CREATE POLICY "Users can update own rewards" ON public.rewards 
    FOR UPDATE USING ((select auth.uid()) = user_id);
