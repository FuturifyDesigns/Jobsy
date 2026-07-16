-- ============================================================================
-- JOB MATCHING — skill/location-based notifications (run once in SQL Editor)
-- Replaces broadcast "new job" alerts with targeted matches.
-- ============================================================================

-- Normalize skills from jsonb or text[] into lowercase text[]
CREATE OR REPLACE FUNCTION public.jobsy_to_skill_array(p_data jsonb)
RETURNS text[]
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT COALESCE(
    ARRAY(
      SELECT lower(trim(value))
      FROM jsonb_array_elements_text(
        CASE
          WHEN p_data IS NULL THEN '[]'::jsonb
          WHEN jsonb_typeof(p_data) = 'array' THEN p_data
          ELSE '[]'::jsonb
        END
      ) AS value
      WHERE trim(value) <> ''
    ),
    ARRAY[]::text[]
  );
$$;

CREATE OR REPLACE FUNCTION public.jobsy_skill_overlap_count(
  p_worker_skills jsonb,
  p_job_skills jsonb
)
RETURNS integer
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT COUNT(*)::integer
  FROM unnest(public.jobsy_to_skill_array(p_worker_skills)) AS ws(skill)
  JOIN unnest(public.jobsy_to_skill_array(p_job_skills)) AS js(skill)
    ON ws.skill = js.skill
    OR ws.skill LIKE '%' || js.skill || '%'
    OR js.skill LIKE '%' || ws.skill || '%';
$$;

CREATE OR REPLACE FUNCTION public.jobsy_location_match(
  p_worker_location text,
  p_job_location text
)
RETURNS boolean
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  w text := lower(trim(COALESCE(p_worker_location, '')));
  j text := lower(trim(COALESCE(p_job_location, '')));
  part text;
BEGIN
  IF w = '' OR j = '' THEN
    RETURN false;
  END IF;
  IF w LIKE '%' || j || '%' OR j LIKE '%' || w || '%' THEN
    RETURN true;
  END IF;
  FOREACH part IN ARRAY regexp_split_to_array(w, '[,\s]+') LOOP
    IF length(part) > 3 AND j LIKE '%' || part || '%' THEN
      RETURN true;
    END IF;
  END LOOP;
  RETURN false;
END;
$$;

CREATE OR REPLACE FUNCTION public.jobsy_worker_job_match_score(
  p_worker profiles,
  p_job jobs
)
RETURNS integer
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_score integer := 0;
  v_overlap integer;
BEGIN
  v_overlap := public.jobsy_skill_overlap_count(p_worker.skills, p_job.required_skills);
  v_score := v_score + (v_overlap * 22);

  IF public.jobsy_location_match(p_worker.location, p_job.location) THEN
    v_score := v_score + 18;
  END IF;

  IF p_job.category IS NOT NULL
     AND (
       lower(COALESCE(p_worker.bio, '')) LIKE '%' || lower(p_job.category) || '%'
       OR EXISTS (
         SELECT 1
         FROM unnest(public.jobsy_to_skill_array(p_worker.skills)) s(skill)
         WHERE s.skill LIKE '%' || lower(p_job.category) || '%'
       )
     ) THEN
    v_score := v_score + 10;
  END IF;

  RETURN LEAST(v_score, 100);
END;
$$;

-- Workers with score >= 25 get a job_match notification (not everyone)
CREATE OR REPLACE FUNCTION public.notify_workers_on_new_job_row(p_job jobs)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_employer_name text;
  v_worker record;
  v_score integer;
  v_match_count integer := 0;
BEGIN
  IF p_job.status IS DISTINCT FROM 'active' THEN
    RETURN;
  END IF;

  SELECT COALESCE(full_name, company_name, 'An employer')
    INTO v_employer_name
  FROM profiles
  WHERE id = p_job.employer_id;

  FOR v_worker IN
    SELECT *
    FROM profiles
    WHERE id IS DISTINCT FROM p_job.employer_id
      AND COALESCE(notifications_enabled, true) = true
  LOOP
    v_score := public.jobsy_worker_job_match_score(v_worker, p_job);
    IF v_score < 25 THEN
      CONTINUE;
    END IF;

    v_match_count := v_match_count + 1;

    INSERT INTO notifications (
      user_id, type, title, body, target_role,
      related_job_id, related_user_id
    ) VALUES (
      v_worker.id,
      'job_match',
      'Job match for you',
      v_employer_name || ' posted "' || COALESCE(p_job.title, 'a job') ||
        '" — matches your skills' ||
        CASE WHEN public.jobsy_location_match(v_worker.location, p_job.location)
          THEN ' & location' ELSE '' END,
      'worker',
      p_job.id,
      p_job.employer_id
    );
  END LOOP;

  -- Employer: suggest matching candidates who have not applied yet
  SELECT COUNT(*)::integer
    INTO v_match_count
  FROM profiles w
  WHERE w.id IS DISTINCT FROM p_job.employer_id
    AND public.jobsy_worker_job_match_score(w, p_job) >= 35
    AND NOT EXISTS (
      SELECT 1 FROM job_applications a
      WHERE a.job_id = p_job.id AND a.worker_id = w.id
    );

  IF v_match_count > 0 THEN
    INSERT INTO notifications (
      user_id, type, title, body, target_role,
      related_job_id, related_user_id
    ) VALUES (
      p_job.employer_id,
      'candidate_match',
      'Matching candidates found',
      v_match_count::text || ' worker(s) may fit "' || COALESCE(p_job.title, 'your job') ||
        '" based on skills and location. Review applications as they come in.',
      'employer',
      p_job.id,
      NULL
    );
  END IF;
END;
$$;

-- Map new notification types to roles (if column exists)
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'notifications'
      AND column_name = 'target_role'
  ) THEN
    UPDATE notifications
    SET target_role = 'worker'
    WHERE type = 'job_match' AND target_role IS NULL;

    UPDATE notifications
    SET target_role = 'employer'
    WHERE type = 'candidate_match' AND target_role IS NULL;
  END IF;
END $$;

SELECT 'job_matching migration applied' AS status;
