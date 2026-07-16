-- ============================================================================
-- JOBSY: Fix new-job notifications + job became active (UPDATE)
-- Run in Supabase → SQL Editor. Safe to re-run.
--
-- Problems fixed:
-- 1) Old trigger only notified workers with fcm_token — others never got a
--    notifications row (bell empty; push was the only path).
-- 2) Only INSERT fired — jobs set to active later (draft → active) never
--    notified anyone.
--
-- Now: all workers with notifications_enabled (default on) get an in-app
-- notification; push still depends on FCM token + webhook + Edge Function.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.notify_workers_on_new_job_row(p_job jobs)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_employer_name text;
  v_worker record;
BEGIN
  IF p_job.status IS DISTINCT FROM 'active' THEN
    RETURN;
  END IF;

  SELECT COALESCE(full_name, 'An employer')
    INTO v_employer_name
  FROM profiles
  WHERE id = p_job.employer_id;

  IF v_employer_name IS NULL THEN
    v_employer_name := 'An employer';
  END IF;

  FOR v_worker IN
    SELECT id FROM profiles
    WHERE user_type = 'worker'
      AND id IS DISTINCT FROM p_job.employer_id
      AND COALESCE(notifications_enabled, true) = true
  LOOP
    INSERT INTO notifications (
      user_id, type, title, body,
      related_job_id, related_user_id
    ) VALUES (
      v_worker.id,
      'new_job_posted',
      'New job available!',
      v_employer_name || ' posted "' || COALESCE(p_job.title, 'a new job') || '"',
      p_job.id,
      p_job.employer_id
    );
  END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION public.notify_workers_on_new_job()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.notify_workers_on_new_job_row(NEW);
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.notify_workers_on_job_became_active()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.status = 'active' AND OLD.status IS DISTINCT FROM 'active' THEN
    PERFORM public.notify_workers_on_new_job_row(NEW);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_workers_on_new_job ON jobs;
CREATE TRIGGER trg_notify_workers_on_new_job
  AFTER INSERT ON jobs
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_workers_on_new_job();

DROP TRIGGER IF EXISTS trg_notify_workers_on_job_became_active ON jobs;
CREATE TRIGGER trg_notify_workers_on_job_became_active
  AFTER UPDATE OF status ON jobs
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_workers_on_job_became_active();

SELECT 'notify_workers_on_new_job: all eligible workers + UPDATE path applied' AS status;
