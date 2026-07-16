-- ============================================================================
-- JOBSY PROFILE COVER IMAGE
-- Run in Supabase SQL editor (safe to re-run).
--
-- Adds cover_url to profiles and ensures the avatars bucket is configured
-- for free-tier use: one JPEG per user (upsert), public read, own-folder write.
-- ============================================================================

ALTER TABLE profiles
  ADD COLUMN IF NOT EXISTS cover_url TEXT;

-- Public avatars bucket (profile photos + cover images)
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'avatars',
  'avatars',
  true,
  524288,
  ARRAY['image/jpeg', 'image/png', 'image/webp']::text[]
)
ON CONFLICT (id) DO UPDATE SET
  public = EXCLUDED.public,
  file_size_limit = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types;

-- Authenticated users: upload/update/delete only in their own folder
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects'
      AND policyname = 'avatars_insert_own'
  ) THEN
    EXECUTE $pol$
      CREATE POLICY "avatars_insert_own"
        ON storage.objects FOR INSERT
        TO authenticated
        WITH CHECK (
          bucket_id = 'avatars'
          AND (storage.foldername(name))[1] = auth.uid()::text
        );
    $pol$;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects'
      AND policyname = 'avatars_update_own'
  ) THEN
    EXECUTE $pol$
      CREATE POLICY "avatars_update_own"
        ON storage.objects FOR UPDATE
        TO authenticated
        USING (
          bucket_id = 'avatars'
          AND (storage.foldername(name))[1] = auth.uid()::text
        );
    $pol$;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects'
      AND policyname = 'avatars_delete_own'
  ) THEN
    EXECUTE $pol$
      CREATE POLICY "avatars_delete_own"
        ON storage.objects FOR DELETE
        TO authenticated
        USING (
          bucket_id = 'avatars'
          AND (storage.foldername(name))[1] = auth.uid()::text
        );
    $pol$;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects'
      AND policyname = 'avatars_select_public'
  ) THEN
    EXECUTE $pol$
      CREATE POLICY "avatars_select_public"
        ON storage.objects FOR SELECT
        TO public
        USING (bucket_id = 'avatars');
    $pol$;
  END IF;
END;
$$;
