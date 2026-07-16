-- ============================================================================
-- EXTERNAL JOBS — enable Supabase Realtime for live Web Jobs feed
-- Run once in Supabase SQL Editor (after EXTERNAL_JOBS_MIGRATION.sql).
-- ============================================================================

ALTER TABLE public.external_jobs REPLICA IDENTITY FULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'external_jobs'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.external_jobs;
  END IF;
END $$;

-- Optional: live updates when employers post new Jobsy listings (worker browse tab).
ALTER TABLE public.jobs REPLICA IDENTITY FULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'jobs'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.jobs;
  END IF;
END $$;
