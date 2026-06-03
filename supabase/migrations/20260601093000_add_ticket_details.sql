-- Add title and image_url columns to support_tickets
ALTER TABLE public.support_tickets
ADD COLUMN title TEXT,
ADD COLUMN image_url TEXT;

-- Create support_attachments bucket if not exists
INSERT INTO storage.buckets (id, name, public) VALUES ('support_attachments', 'support_attachments', true) ON CONFLICT (id) DO NOTHING;

-- Storage Insert Policy: Allow authenticated users to upload to support_attachments
CREATE POLICY "Allow authenticated upload support_attachments"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (bucket_id = 'support_attachments');

-- Storage Select Policy: Allow public read access to support_attachments
CREATE POLICY "Allow public read support_attachments"
ON storage.objects FOR SELECT
TO public
USING (bucket_id = 'support_attachments');
