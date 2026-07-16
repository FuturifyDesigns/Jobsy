-- ============================================================================
-- JOBSY: Only allow new applications while the job listing is `active`
-- Run in Supabase → SQL Editor (after REALTIME_RLS_FIX_MIGRATION or equivalent)
-- ============================================================================

DROP POLICY IF EXISTS "Workers can apply to jobs" ON job_applications;

CREATE POLICY "Workers can apply to jobs"
  ON job_applications FOR INSERT
  TO authenticated
  WITH CHECK (
    auth.uid() = worker_id
    AND EXISTS (
      SELECT 1
      FROM jobs j
      WHERE j.id = job_id
        AND j.status = 'active'
    )
  );

SELECT 'JOB_APPLICATIONS_ACTIVE_JOB_ONLY complete' AS status;
