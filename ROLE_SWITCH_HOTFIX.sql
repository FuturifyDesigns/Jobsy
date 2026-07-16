-- ============================================================================
-- ROLE SWITCH HOTFIX — run in Supabase SQL Editor (fixes switch to Worker)
--
-- Bug: switch_user_role referenced v_experience_level (undefined variable)
--      causing "couldn't complete / check connection" in the app.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.switch_user_role(p_target_role TEXT)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_current TEXT;
  v_complete BOOLEAN;
  v_last_switch TIMESTAMPTZ;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  IF p_target_role NOT IN ('worker', 'employer') THEN
    RAISE EXCEPTION 'Invalid role. Must be worker or employer.';
  END IF;

  SELECT user_type, is_profile_complete, last_role_switch_at
  INTO v_current, v_complete, v_last_switch
  FROM profiles
  WHERE id = v_user_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Profile not found';
  END IF;

  IF COALESCE(v_complete, false) = false THEN
    RAISE EXCEPTION 'Complete your profile before switching roles.';
  END IF;

  IF v_current = p_target_role THEN
    RAISE EXCEPTION 'You are already in % mode.', p_target_role;
  END IF;

  IF v_last_switch IS NOT NULL
     AND v_last_switch > NOW() - INTERVAL '30 seconds' THEN
    RAISE EXCEPTION 'Please wait % seconds before switching roles again.',
      GREATEST(1, CEIL(EXTRACT(EPOCH FROM (v_last_switch + INTERVAL '30 seconds' - NOW()))))::INT;
  END IF;

  IF p_target_role = 'worker' THEN
    NULL; -- Browse worker mode freely; apply requires profile fields (enforced in app).
  END IF;

  IF v_current = 'employer' AND p_target_role = 'worker' THEN
    IF EXISTS (
      SELECT 1 FROM jobs j
      WHERE j.employer_id = v_user_id
        AND j.status = 'in_progress'
    ) THEN
      RAISE EXCEPTION 'You have a job in progress. Confirm completion or cancel it before switching to Worker mode.';
    END IF;

    IF EXISTS (
      SELECT 1 FROM jobs j
      JOIN job_applications a ON a.job_id = j.id
      WHERE j.employer_id = v_user_id
        AND j.status NOT IN ('completed', 'cancelled')
        AND a.worker_completed = true
        AND a.status IN ('accepted', 'in_progress')
    ) THEN
      RAISE EXCEPTION 'A worker marked a job as done. Confirm completion in Employer mode before switching.';
    END IF;

    IF EXISTS (
      SELECT 1 FROM jobs j
      JOIN job_applications a ON a.job_id = j.id
      WHERE j.employer_id = v_user_id
        AND j.status IN ('active', 'in_progress')
        AND a.status IN ('accepted', 'in_progress')
    ) THEN
      RAISE EXCEPTION 'You have a hired worker on an active job. Finish that job before switching to Worker mode.';
    END IF;
  END IF;

  IF v_current = 'worker' AND p_target_role = 'employer' THEN
    IF EXISTS (
      SELECT 1 FROM job_applications a
      JOIN jobs j ON j.id = a.job_id
      WHERE a.worker_id = v_user_id
        AND a.status IN ('accepted', 'in_progress')
        AND j.status NOT IN ('completed', 'cancelled')
    ) THEN
      RAISE EXCEPTION 'You have an active job assignment. Complete it or withdraw before switching to Employer mode.';
    END IF;
  END IF;

  PERFORM set_config('app.allow_role_switch', 'true', true);

  UPDATE profiles
  SET user_type = p_target_role,
      last_role_switch_at = NOW()
  WHERE id = v_user_id;

  PERFORM set_config('app.allow_role_switch', 'false', true);

  RETURN p_target_role;
END;
$$;

REVOKE ALL ON FUNCTION public.switch_user_role(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.switch_user_role(TEXT) TO authenticated;

SELECT '=== ROLE SWITCH HOTFIX APPLIED ===' AS status;
