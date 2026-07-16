-- ============================================================================
-- EXTERNAL JOBS — vacancy expiry (run once in Supabase SQL Editor)
-- Hides expired listings from the app; import cron deactivates them too.
-- ============================================================================

DROP POLICY IF EXISTS external_jobs_select_authenticated ON public.external_jobs;
CREATE POLICY external_jobs_select_authenticated
  ON public.external_jobs FOR SELECT
  TO authenticated
  USING (
    is_active = TRUE
    AND (expires_at IS NULL OR expires_at > NOW())
  );

CREATE OR REPLACE FUNCTION public.deactivate_stale_external_jobs()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count INTEGER;
BEGIN
  UPDATE external_jobs
  SET is_active = FALSE
  WHERE is_active = TRUE
    AND (
      (expires_at IS NOT NULL AND expires_at < NOW())
      OR imported_at < NOW() - INTERVAL '45 days'
    );
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

-- Optional: deactivate already-expired rows immediately
SELECT public.deactivate_stale_external_jobs() AS deactivated_now;
