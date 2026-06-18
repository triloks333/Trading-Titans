-- Enable trigram extension for fuzzy duplicate matching
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- Create feature requests table
CREATE TABLE public.feature_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    title TEXT NOT NULL CHECK (char_length(title) >= 5),
    description TEXT NOT NULL CHECK (char_length(description) >= 10),
    image_url TEXT,
    status TEXT NOT NULL DEFAULT 'proposed' CHECK (status IN ('proposed', 'planned', 'in_progress', 'completed', 'declined')),
    released_in_version TEXT,
    is_moderated BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Trigram Index for fuzzy title search
CREATE INDEX idx_feature_requests_title_trgm ON public.feature_requests USING gist (title gist_trgm_ops);

-- Create upvotes table
CREATE TABLE public.feature_upvotes (
    feature_id UUID REFERENCES public.feature_requests(id) ON DELETE CASCADE,
    user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (feature_id, user_id)
);

-- Create reports table
CREATE TABLE public.feature_reports (
    feature_id UUID REFERENCES public.feature_requests(id) ON DELETE CASCADE,
    user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (feature_id, user_id)
);

-- Trigger for Weekly Submissions Rate Limit (max 3 submissions per user per week)
CREATE OR REPLACE FUNCTION check_wishlist_rate_limit()
RETURNS TRIGGER AS $$
BEGIN
    IF (
        SELECT COUNT(*) 
        FROM public.feature_requests 
        WHERE user_id = NEW.user_id 
          AND created_at >= NOW() - INTERVAL '7 days'
    ) >= 3 THEN
        RAISE EXCEPTION 'Rate limit exceeded: You can only submit up to 3 feature requests per week.';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_wishlist_rate_limit
BEFORE INSERT ON public.feature_requests
FOR EACH ROW
EXECUTE FUNCTION check_wishlist_rate_limit();

-- Enable RLS
ALTER TABLE public.feature_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.feature_upvotes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.feature_reports ENABLE ROW LEVEL SECURITY;

-- RLS policies for feature_requests
CREATE POLICY "Select public feature requests"
    ON public.feature_requests FOR SELECT
    USING (
        auth.uid() IS NOT NULL AND (
            (SELECT COUNT(*) FROM public.feature_reports r WHERE r.feature_id = id) < 3 OR 
            is_moderated = true OR 
            auth.uid() = user_id OR
            (SELECT is_admin FROM public.profiles WHERE id = auth.uid()) = true
        )
    );

CREATE POLICY "Insert feature requests"
    ON public.feature_requests FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Update feature requests"
    ON public.feature_requests FOR UPDATE
    USING (
        (SELECT is_admin FROM public.profiles WHERE id = auth.uid()) = true OR
        (auth.uid() = user_id AND status = 'proposed')
    );

CREATE POLICY "Delete feature requests"
    ON public.feature_requests FOR DELETE
    USING (
        auth.uid() = user_id OR
        (SELECT is_admin FROM public.profiles WHERE id = auth.uid()) = true
    );

-- RLS policies for feature_upvotes
CREATE POLICY "Select feature upvotes"
    ON public.feature_upvotes FOR SELECT
    USING (auth.uid() IS NOT NULL);

CREATE POLICY "Insert feature upvotes"
    ON public.feature_upvotes FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Delete feature upvotes"
    ON public.feature_upvotes FOR DELETE
    USING (auth.uid() = user_id);

-- RLS policies for feature_reports
CREATE POLICY "Select feature reports"
    ON public.feature_reports FOR SELECT
    USING ((SELECT is_admin FROM public.profiles WHERE id = auth.uid()) = true);

CREATE POLICY "Insert feature reports"
    ON public.feature_reports FOR INSERT
    WITH CHECK (auth.uid() = user_id);

-- Server-side Trending Score Function
CREATE OR REPLACE FUNCTION public.get_trending_features()
RETURNS TABLE (
    id UUID,
    user_id UUID,
    title TEXT,
    description TEXT,
    image_url TEXT,
    status TEXT,
    released_in_version TEXT,
    is_moderated BOOLEAN,
    created_at TIMESTAMPTZ,
    upvotes_count BIGINT,
    trending_score DOUBLE PRECISION
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        f.id, f.user_id, f.title, f.description, f.image_url, 
        f.status, f.released_in_version, f.is_moderated, f.created_at,
        COALESCE(COUNT(u.user_id), 0) AS upvotes_count,
        ((COALESCE(COUNT(u.user_id), 0) + 1.0) / 
        POWER(EXTRACT(EPOCH FROM (now() - f.created_at)) / 3600.0 + 2.0, 1.2))::double precision AS trending_score
    FROM 
        public.feature_requests f
    LEFT JOIN 
        public.feature_upvotes u ON f.id = u.feature_id
    GROUP BY 
        f.id, f.user_id, f.title, f.description, f.image_url, 
        f.status, f.released_in_version, f.is_moderated, f.created_at
    ORDER BY 
        trending_score DESC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Fuzzy Duplicate Search Function
CREATE OR REPLACE FUNCTION public.search_similar_features(search_title TEXT, similarity_threshold REAL)
RETURNS TABLE (
    id UUID,
    title TEXT,
    description TEXT,
    status TEXT,
    similarity_score REAL
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        f.id, f.title, f.description, f.status,
        similarity(f.title, search_title)::REAL AS similarity_score
    FROM 
        public.feature_requests f
    WHERE 
        similarity(f.title, search_title) > similarity_threshold
    ORDER BY 
        similarity_score DESC
    LIMIT 5;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
