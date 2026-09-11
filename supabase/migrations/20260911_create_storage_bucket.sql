-- Migration: Create revive-photos-r2-proxy bucket and RLS policies

INSERT INTO storage.buckets (id, name, public) 
VALUES ('revive-photos-r2-proxy', 'revive-photos-r2-proxy', true)
ON CONFLICT (id) DO NOTHING;

-- Allow public access to view photos
CREATE POLICY "Public Access" 
ON storage.objects FOR SELECT 
USING ( bucket_id = 'revive-photos-r2-proxy' );

-- Allow authenticated users to upload photos
CREATE POLICY "Auth Upload" 
ON storage.objects FOR INSERT 
WITH CHECK ( bucket_id = 'revive-photos-r2-proxy' AND auth.role() = 'authenticated' );

-- Allow authenticated users to update their own uploads (optional)
CREATE POLICY "Auth Update" 
ON storage.objects FOR UPDATE
WITH CHECK ( bucket_id = 'revive-photos-r2-proxy' AND auth.role() = 'authenticated' );
