-- Create Support Tickets Table
CREATE TABLE public.support_tickets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE NOT NULL,
    email TEXT NOT NULL,
    type TEXT NOT NULL CHECK (type IN ('feature', 'issue')),
    content TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Enable RLS
ALTER TABLE public.support_tickets ENABLE ROW LEVEL SECURITY;

-- Select policy: User can read their own, OR any admin user can read ALL support tickets
CREATE POLICY "Select support tickets"
    ON public.support_tickets FOR SELECT
    USING (
        auth.uid() = user_id OR 
        (SELECT is_admin FROM public.profiles WHERE id = auth.uid()) = true
    );

-- Insert policy: Any authenticated user can insert tickets for themselves
CREATE POLICY "Insert support tickets"
    ON public.support_tickets FOR INSERT
    WITH CHECK (auth.uid() = user_id);
