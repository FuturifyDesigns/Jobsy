-- ============================================================================
-- JOBSY: Optional application fields (references, qualifications, extra info)
-- Run in Supabase → SQL Editor. Safe to re-run.
-- ============================================================================

ALTER TABLE public.job_applications
  ADD COLUMN IF NOT EXISTS references_text text,
  ADD COLUMN IF NOT EXISTS additional_info text,
  ADD COLUMN IF NOT EXISTS qualification_files jsonb NOT NULL DEFAULT '[]'::jsonb;

COMMENT ON COLUMN public.job_applications.references_text IS
  'Optional: contactable references (names, relationship, phone/email).';
COMMENT ON COLUMN public.job_applications.additional_info IS
  'Optional: any other relevant details for the employer.';
COMMENT ON COLUMN public.job_applications.qualification_files IS
  'JSON array of { "path", "name" } objects under storage bucket application-qualifications.';

-- Private bucket for certificates / CV excerpts (not profile photos)
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'application-qualifications',
  'application-qualifications',
  false,
  10485760,
  ARRAY[
    'application/pdf',
    'image/jpeg', 'image/png', 'image/webp'
  ]
)
ON CONFLICT (id) DO UPDATE SET
  file_size_limit = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types;

-- Worker: upload only under folders named with their own application id
DROP POLICY IF EXISTS "application_qualifications_insert_worker" ON storage.objects;
CREATE POLICY "application_qualifications_insert_worker"
  ON storage.objects FOR INSERT
  TO authenticated
  WITH CHECK (
    bucket_id = 'application-qualifications'
    AND EXISTS (
      SELECT 1 FROM job_applications ja
      WHERE ja.id::text = (storage.foldername(name))[1]
        AND ja.worker_id = auth.uid()
    )
  );

-- Worker + employer for that job can read (signed URLs from app)
DROP POLICY IF EXISTS "application_qualifications_select_parties" ON storage.objects;
CREATE POLICY "application_qualifications_select_parties"
  ON storage.objects FOR SELECT
  TO authenticated
  USING (
    bucket_id = 'application-qualifications'
    AND EXISTS (
      SELECT 1 FROM job_applications ja
      JOIN jobs j ON j.id = ja.job_id
      WHERE ja.id::text = (storage.foldername(name))[1]
        AND (ja.worker_id = auth.uid() OR j.employer_id = auth.uid())
    )
  );

-- Worker can delete own uploads (e.g. wrong file before employer accepts)
DROP POLICY IF EXISTS "application_qualifications_delete_worker" ON storage.objects;
CREATE POLICY "application_qualifications_delete_worker"
  ON storage.objects FOR DELETE
  TO authenticated
  USING (
    bucket_id = 'application-qualifications'
    AND EXISTS (
      SELECT 1 FROM job_applications ja
      WHERE ja.id::text = (storage.foldername(name))[1]
        AND ja.worker_id = auth.uid()
    )
  );

SELECT 'APPLICATION_EXTRA_FIELDS_MIGRATION complete' AS status;
