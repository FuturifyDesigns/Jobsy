-- ============================================================================
-- JOB GPS COORDINATES — exact map pins for GPS-posted jobs
-- Run once in Supabase SQL Editor. Safe to re-run.
-- ============================================================================

ALTER TABLE public.jobs
  ADD COLUMN IF NOT EXISTS latitude DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS longitude DOUBLE PRECISION;

ALTER TABLE public.jobs
  DROP CONSTRAINT IF EXISTS chk_job_coordinates_pair;

ALTER TABLE public.jobs
  ADD CONSTRAINT chk_job_coordinates_pair
    CHECK (
      (latitude IS NULL AND longitude IS NULL)
      OR (
        latitude IS NOT NULL
        AND longitude IS NOT NULL
        AND latitude BETWEEN -90 AND 90
        AND longitude BETWEEN -180 AND 180
      )
    );

COMMENT ON COLUMN public.jobs.latitude IS
  'GPS latitude when employer used "Use my current location" while posting.';
COMMENT ON COLUMN public.jobs.longitude IS
  'GPS longitude when employer used "Use my current location" while posting.';
