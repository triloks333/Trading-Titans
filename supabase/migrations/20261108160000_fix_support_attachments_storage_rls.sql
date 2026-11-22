-- Migration: 20261108160000_fix_support_attachments_storage_rls.sql
-- Description: Fix RLS policies on storage.objects for support_attachments bucket.
-- Allows upload, upsert (requires UPDATE policy), read (public), and delete.

-- 1. Ensure support_attachments bucket exists and is public
INSERT INTO storage.buckets (id, name, public)
VALUES ('support_attachments', 'support_attachments', true)
ON CONFLICT (id) DO UPDATE SET public = true;

-- 2. Storage Policies on storage.objects for support_attachments
DROP POLICY IF EXISTS "Allow authenticated upload support_attachments" ON storage.objects;
DROP POLICY IF EXISTS "Allow authenticated update support_attachments" ON storage.objects;
DROP POLICY IF EXISTS "Allow public read support_attachments" ON storage.objects;
DROP POLICY IF EXISTS "Allow authenticated delete support_attachments" ON storage.objects;
DROP POLICY IF EXISTS "Allow upload support_attachments" ON storage.objects;
DROP POLICY IF EXISTS "Allow update support_attachments" ON storage.objects;
DROP POLICY IF EXISTS "Allow read support_attachments" ON storage.objects;
DROP POLICY IF EXISTS "Allow delete support_attachments" ON storage.objects;

CREATE POLICY "Allow upload support_attachments"
ON storage.objects FOR INSERT TO public
WITH CHECK (bucket_id = 'support_attachments');

CREATE POLICY "Allow update support_attachments"
ON storage.objects FOR UPDATE TO public
USING (bucket_id = 'support_attachments')
WITH CHECK (bucket_id = 'support_attachments');

CREATE POLICY "Allow read support_attachments"
ON storage.objects FOR SELECT TO public
USING (bucket_id = 'support_attachments');

CREATE POLICY "Allow delete support_attachments"
ON storage.objects FOR DELETE TO public
USING (bucket_id = 'support_attachments');
