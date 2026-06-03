-- Add UPDATE policy for support_tickets
CREATE POLICY "Update support tickets"
    ON public.support_tickets FOR UPDATE
    USING (
        auth.uid() = user_id OR 
        (SELECT is_admin FROM public.profiles WHERE id = auth.uid()) = true
    )
    WITH CHECK (
        auth.uid() = user_id OR 
        (SELECT is_admin FROM public.profiles WHERE id = auth.uid()) = true
    );
