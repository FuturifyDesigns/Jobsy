-- ============================================================================
-- JOBSY ROLE SWITCH SECURITY
-- Run in Supabase SQL editor after ROLE_SWITCH_MIGRATION.sql (safe to re-run).
--
-- Hardens role switching and closes self-dealing exploits:
--   • Role changes only via switch_user_role() RPC (not direct profile UPDATE)
--   • Cannot apply to your own job postings
--   • Cannot rate yourself
--   • Posting jobs requires employer mode; applying requires worker mode
--   • Cooldown between role switches
-- ============================================================================

-- Track last switch for cooldown / audit
ALTER TABLE profiles
  ADD COLUMN IF NOT EXISTS last_role_switch_at TIMESTAMPTZ;

-- ─── Block direct user_type tampering ───────────────────────────────────────

CREATE OR REPLACE FUNCTION prevent_user_type_change()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.user_type NOT IN ('worker', 'employer') THEN
      RAISE EXCEPTION 'Invalid user_type: %. Must be worker or employer.', NEW.user_type;
    END IF;
    RETURN NEW;
  END IF;

  IF NEW.user_type IS DISTINCT FROM OLD.user_type THEN
    IF NEW.user_type NOT IN ('worker', 'employer') THEN
      RAISE EXCEPTION 'Invalid user_type: %. Must be worker or employer.', NEW.user_type;
    END IF;
    IF COALESCE(current_setting('app.allow_role_switch', true), '') <> 'true' THEN
      RAISE EXCEPTION 'Role cannot be changed directly. Use the in-app role switch.';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_prevent_user_type_change ON profiles;
CREATE TRIGGER trg_prevent_user_type_change
  BEFORE INSERT OR UPDATE ON profiles
  FOR EACH ROW EXECUTE FUNCTION prevent_user_type_change();

-- ─── Validated role switch RPC ────────────────────────────────────────────

CREATE OR REPLACE FUNCTION switch_user_role(p_target_role TEXT)
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

REVOKE ALL ON FUNCTION switch_user_role(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION switch_user_role(TEXT) TO authenticated;

-- ─── Onboarding role pick (profile not yet complete) ───────────────────────

CREATE OR REPLACE FUNCTION set_onboarding_user_role(p_target_role TEXT)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_complete BOOLEAN;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  IF p_target_role NOT IN ('worker', 'employer') THEN
    RAISE EXCEPTION 'Invalid role. Must be worker or employer.';
  END IF;

  SELECT is_profile_complete INTO v_complete
  FROM profiles
  WHERE id = v_user_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Profile not found';
  END IF;

  IF COALESCE(v_complete, false) = true THEN
    RAISE EXCEPTION 'Use the in-app role switch after your profile is complete.';
  END IF;

  PERFORM set_config('app.allow_role_switch', 'true', true);

  UPDATE profiles
  SET user_type = p_target_role
  WHERE id = v_user_id;

  PERFORM set_config('app.allow_role_switch', 'false', true);

  RETURN p_target_role;
END;
$$;

REVOKE ALL ON FUNCTION set_onboarding_user_role(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION set_onboarding_user_role(TEXT) TO authenticated;

-- ─── Anti self-dealing: job applications ─────────────────────────────────

CREATE OR REPLACE FUNCTION prevent_self_job_application()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM jobs j
    WHERE j.id = NEW.job_id
      AND j.employer_id = NEW.worker_id
  ) THEN
    RAISE EXCEPTION 'You cannot apply to your own job posting.';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_prevent_self_job_application ON job_applications;
CREATE TRIGGER trg_prevent_self_job_application
  BEFORE INSERT ON job_applications
  FOR EACH ROW EXECUTE FUNCTION prevent_self_job_application();

DROP POLICY IF EXISTS "Workers can apply to jobs" ON job_applications;
CREATE POLICY "Workers can apply to jobs"
  ON job_applications FOR INSERT
  TO authenticated
  WITH CHECK (
    auth.uid() = worker_id
    AND EXISTS (
      SELECT 1 FROM profiles p
      WHERE p.id = auth.uid()
        AND p.user_type = 'worker'
    )
    AND EXISTS (
      SELECT 1 FROM jobs j
      WHERE j.id = job_id
        AND j.status = 'active'
        AND j.employer_id IS DISTINCT FROM auth.uid()
    )
  );

-- ─── Jobs: only post while in employer mode ───────────────────────────────

DROP POLICY IF EXISTS "Employers can insert jobs" ON jobs;
CREATE POLICY "Employers can insert jobs"
  ON jobs FOR INSERT
  TO authenticated
  WITH CHECK (
    auth.uid() = employer_id
    AND EXISTS (
      SELECT 1 FROM profiles p
      WHERE p.id = auth.uid()
        AND p.user_type = 'employer'
    )
  );

DROP POLICY IF EXISTS "Employers can update own jobs" ON jobs;
CREATE POLICY "Employers can update own jobs"
  ON jobs FOR UPDATE
  TO authenticated
  USING (
    auth.uid() = employer_id
    AND EXISTS (
      SELECT 1 FROM profiles p
      WHERE p.id = auth.uid()
        AND p.user_type = 'employer'
    )
  );

DROP POLICY IF EXISTS "Employers can delete own jobs" ON jobs;
CREATE POLICY "Employers can delete own jobs"
  ON jobs FOR DELETE
  TO authenticated
  USING (
    auth.uid() = employer_id
    AND EXISTS (
      SELECT 1 FROM profiles p
      WHERE p.id = auth.uid()
        AND p.user_type = 'employer'
    )
  );

-- Worker completion flag may only be set while in worker mode
CREATE OR REPLACE FUNCTION enforce_worker_completed_role()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.worker_completed IS DISTINCT FROM OLD.worker_completed
     AND NEW.worker_completed = true THEN
    IF NOT EXISTS (
      SELECT 1 FROM profiles p
      WHERE p.id = auth.uid()
        AND p.user_type = 'worker'
    ) THEN
      RAISE EXCEPTION 'Switch to Worker mode to mark a job as complete.';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_enforce_worker_completed_role ON job_applications;
CREATE TRIGGER trg_enforce_worker_completed_role
  BEFORE UPDATE ON job_applications
  FOR EACH ROW EXECUTE FUNCTION enforce_worker_completed_role();

-- Job status → completed may only be set by employer mode
CREATE OR REPLACE FUNCTION enforce_job_completed_role()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.status IS DISTINCT FROM OLD.status
     AND NEW.status = 'completed' THEN
    IF NOT EXISTS (
      SELECT 1 FROM profiles p
      WHERE p.id = auth.uid()
        AND p.user_type = 'employer'
    ) THEN
      RAISE EXCEPTION 'Switch to Employer mode to confirm job completion.';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_enforce_job_completed_role ON jobs;
CREATE TRIGGER trg_enforce_job_completed_role
  BEFORE UPDATE ON jobs
  FOR EACH ROW EXECUTE FUNCTION enforce_job_completed_role();

-- ─── Ratings: no self-rating ────────────────────────────────────────────────

ALTER TABLE ratings DROP CONSTRAINT IF EXISTS chk_no_self_rating;
ALTER TABLE ratings
  ADD CONSTRAINT chk_no_self_rating CHECK (rater_id <> rated_id);

DROP POLICY IF EXISTS "Users can insert own ratings" ON ratings;
CREATE POLICY "Users can insert own ratings"
  ON ratings FOR INSERT
  WITH CHECK (
    auth.uid() = rater_id
    AND rater_id IS DISTINCT FROM rated_id
  );

SELECT 'ROLE_SWITCH_SECURITY complete' AS status;
