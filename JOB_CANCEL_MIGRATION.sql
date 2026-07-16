-- ============================================================================
-- JOBSY: Cancel job / worker withdraw
-- Run once in Supabase → SQL Editor
-- ============================================================================
-- Workers cannot UPDATE jobs (RLS). This function lets a worker withdraw from
-- an accepted/in_progress application and puts the job back to `active` so the
-- employer can hire someone else.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.worker_withdraw_from_job(p_application_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_app job_applications%ROWTYPE;
BEGIN
  SELECT * INTO v_app FROM job_applications WHERE id = p_application_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Application not found';
  END IF;
  IF v_app.worker_id IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'Not allowed';
  END IF;
  IF v_app.status NOT IN ('accepted', 'in_progress') THEN
    RAISE EXCEPTION 'Cannot withdraw from this application';
  END IF;

  UPDATE job_applications
  SET status = 'withdrawn', updated_at = now()
  WHERE id = p_application_id;

  UPDATE jobs
  SET status = 'active', updated_at = now()
  WHERE id = v_app.job_id
    AND status IN ('active', 'in_progress');
END;
$$;

REVOKE ALL ON FUNCTION public.worker_withdraw_from_job(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.worker_withdraw_from_job(uuid) TO authenticated;
