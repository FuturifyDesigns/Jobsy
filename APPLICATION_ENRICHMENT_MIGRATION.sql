-- ============================================================================
-- JOB APPLICATION ENRICHMENT
-- Extra optional fields for workers when applying + storage for qualification docs.
-- Run in Supabase SQL Editor. Safe to re-run (IF NOT EXISTS / ON CONFLICT).
-- ============================================================================

-- 1. Columns on job_applications
ALTER TABLE job_applications
  ADD COLUMN IF NOT EXISTS relevant_experience TEXT,
  ADD COLUMN IF NOT EXISTS availability_note TEXT,
  ADD COLUMN IF NOT EXISTS qualification_doc_path TEXT,
  ADD COLUMN IF NOT EXISTS qualification_doc_meta JSONB,
  ADD COLUMN IF NOT EXISTS references_json JSONB;

COMMENT ON COLUMN job_applications.relevant_experience IS 'Optional: why the worker fits / relevant background';
COMMENT ON COLUMN job_applications.availability_note IS 'Optional: when they can start or schedule notes';
COMMENT ON COLUMN job_applications.qualification_doc_path IS 'Private storage path in application-documents bucket';
COMMENT ON COLUMN job_applications.qualification_doc_meta IS 'Optional: {filename, mime, size}';
COMMENT ON COLUMN job_applications.references_json IS 'Optional JSON array: [{name, relationship, contact}]';


-- 2. Storage bucket (private — signed URLs in the app)
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'application-documents',
  'application-documents',
  false,
  5242880,
  ARRAY[
    'application/pdf',
    'image/jpeg',
    'image/png',
    'image/webp'
  ]
)
ON CONFLICT (id) DO UPDATE SET
  file_size_limit = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types;


-- 3. RLS: path = {job_id}/{worker_id}/{filename}
DROP POLICY IF EXISTS "app_documents_select" ON storage.objects;
DROP POLICY IF EXISTS "app_documents_insert" ON storage.objects;
DROP POLICY IF EXISTS "app_documents_delete" ON storage.objects;

CREATE POLICY "app_documents_select"
ON storage.objects FOR SELECT
TO authenticated
USING (
  bucket_id = 'application-documents'
  AND (
    (storage.foldername(name))[2] = auth.uid()::text
    OR EXISTS (
      SELECT 1 FROM jobs j
      WHERE j.id::text = (storage.foldername(name))[1]
        AND j.employer_id = auth.uid()
    )
  )
);

CREATE POLICY "app_documents_insert"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'application-documents'
  AND (storage.foldername(name))[2] = auth.uid()::text
  AND EXISTS (
    SELECT 1 FROM jobs j
    WHERE j.id::text = (storage.foldername(name))[1]
  )
);

CREATE POLICY "app_documents_delete"
ON storage.objects FOR DELETE
TO authenticated
USING (
  bucket_id = 'application-documents'
  AND (storage.foldername(name))[2] = auth.uid()::text
);
