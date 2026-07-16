-- ============================================================================
-- JOBSY: Role-aware notifications (dual-role / role switching)
-- Run in Supabase → SQL Editor. Safe to re-run.
--
-- Adds target_role to notifications so push + in-app know which mode applies.
-- Fixes new-job alerts for users currently in employer mode.
-- ============================================================================

ALTER TABLE public.notifications
  ADD COLUMN IF NOT EXISTS target_role TEXT;

ALTER TABLE public.notifications
  DROP CONSTRAINT IF EXISTS notifications_target_role_check;

ALTER TABLE public.notifications
  ADD CONSTRAINT notifications_target_role_check
  CHECK (target_role IS NULL OR target_role IN ('worker', 'employer'));

CREATE INDEX IF NOT EXISTS idx_notifications_user_role_unread
  ON public.notifications (user_id, target_role, is_read)
  WHERE is_read = FALSE;

-- Backfill legacy rows
UPDATE public.notifications
SET target_role = CASE type
  WHEN 'new_application' THEN 'employer'
  WHEN 'worker_withdrew' THEN 'employer'
  WHEN 'worker_done' THEN 'employer'
  WHEN 'application_accepted' THEN 'worker'
  WHEN 'application_rejected' THEN 'worker'
  WHEN 'application_cancelled' THEN 'worker'
  WHEN 'new_job_posted' THEN 'worker'
  WHEN 'job_completed' THEN 'worker'
  ELSE target_role
END
WHERE target_role IS NULL;

-- ─── New message ───────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.notify_on_new_message()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_employer_id uuid;
  v_worker_id uuid;
  v_recipient_id uuid;
  v_recipient_role text;
  v_sender_name text;
  v_body text;
  v_inbox_visible boolean;
BEGIN
  SELECT c.employer_id, c.worker_id, COALESCE(c.inbox_visible, true)
  INTO v_employer_id, v_worker_id, v_inbox_visible
  FROM conversations c
  WHERE c.id = NEW.conversation_id;

  IF NOT COALESCE(v_inbox_visible, true) THEN
    RETURN NEW;
  END IF;

  IF NEW.sender_id = v_employer_id THEN
    v_recipient_id := v_worker_id;
    v_recipient_role := 'worker';
  ELSE
    v_recipient_id := v_employer_id;
    v_recipient_role := 'employer';
  END IF;

  SELECT COALESCE(full_name, 'Someone')
  INTO v_sender_name
  FROM profiles
  WHERE id = NEW.sender_id;

  IF v_sender_name IS NULL THEN
    v_sender_name := 'Someone';
  END IF;

  v_body := CASE NEW.message_type
    WHEN 'image'    THEN '📷 Photo'
    WHEN 'voice'    THEN '🎤 Voice message'
    WHEN 'file'     THEN '📎 Document'
    WHEN 'location' THEN '📍 Location'
    WHEN 'contact'  THEN '👤 Contact'
    ELSE NULL
  END;

  IF v_body IS NULL THEN
    IF NEW.message IS NULL OR NEW.message = '' THEN
      v_body := 'New message';
    ELSIF LENGTH(NEW.message) > 80 THEN
      v_body := SUBSTRING(NEW.message, 1, 80) || '...';
    ELSE
      v_body := NEW.message;
    END IF;
  END IF;

  INSERT INTO notifications (
    user_id, type, title, body, target_role,
    related_conversation_id, related_user_id
  ) VALUES (
    v_recipient_id,
    'new_message',
    v_sender_name,
    v_body,
    v_recipient_role,
    NEW.conversation_id,
    NEW.sender_id
  );

  RETURN NEW;
END;
$$;

-- ─── New application → employer ──────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.notify_on_new_application()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_employer_id uuid;
  v_job_title text;
  v_worker_name text;
BEGIN
  SELECT employer_id, title
    INTO v_employer_id, v_job_title
  FROM jobs
  WHERE id = NEW.job_id;

  SELECT COALESCE(full_name, 'A worker')
    INTO v_worker_name
  FROM profiles
  WHERE id = NEW.worker_id;

  IF v_worker_name IS NULL THEN
    v_worker_name := 'A worker';
  END IF;

  INSERT INTO notifications (
    user_id, type, title, body, target_role,
    related_job_id, related_application_id, related_user_id
  ) VALUES (
    v_employer_id,
    'new_application',
    'New Application',
    v_worker_name || ' applied to "' || COALESCE(v_job_title, 'your job') || '"',
    'employer',
    NEW.job_id,
    NEW.id,
    NEW.worker_id
  );

  RETURN NEW;
END;
$$;

-- ─── Application status changes ────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.notify_on_application_status()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_job_title text;
  v_employer_id uuid;
  v_worker_name text;
BEGIN
  IF NEW.status = OLD.status THEN
    RETURN NEW;
  END IF;

  IF NEW.status = 'accepted' THEN
    SELECT title INTO v_job_title FROM jobs WHERE id = NEW.job_id;
    INSERT INTO notifications (
      user_id, type, title, body, target_role,
      related_job_id, related_application_id
    ) VALUES (
      NEW.worker_id,
      'application_accepted',
      'You got the job!',
      'Your application for "' || COALESCE(v_job_title, 'a job') || '" was accepted',
      'worker',
      NEW.job_id,
      NEW.id
    );
  ELSIF NEW.status = 'rejected' THEN
    SELECT title INTO v_job_title FROM jobs WHERE id = NEW.job_id;
    INSERT INTO notifications (
      user_id, type, title, body, target_role,
      related_job_id, related_application_id
    ) VALUES (
      NEW.worker_id,
      'application_rejected',
      'Application Update',
      'Your application for "' || COALESCE(v_job_title, 'a job') || '" was not accepted this time',
      'worker',
      NEW.job_id,
      NEW.id
    );
  ELSIF NEW.status = 'cancelled' THEN
    SELECT title INTO v_job_title FROM jobs WHERE id = NEW.job_id;
    INSERT INTO notifications (
      user_id, type, title, body, target_role,
      related_job_id, related_application_id
    ) VALUES (
      NEW.worker_id,
      'application_cancelled',
      'Application closed',
      'Your application for "' || COALESCE(v_job_title, 'a job')
        || '" was closed and the listing may be open again.',
      'worker',
      NEW.job_id,
      NEW.id
    );
  ELSIF NEW.status = 'withdrawn' THEN
    SELECT j.title, j.employer_id INTO v_job_title, v_employer_id FROM jobs j WHERE j.id = NEW.job_id;
    SELECT COALESCE(full_name, 'A worker') INTO v_worker_name FROM profiles WHERE id = NEW.worker_id;
    INSERT INTO notifications (
      user_id, type, title, body, target_role,
      related_job_id, related_application_id
    ) VALUES (
      v_employer_id,
      'worker_withdrew',
      'Worker withdrew',
      v_worker_name || ' withdrew from "' || COALESCE(v_job_title, 'a job') || '".',
      'employer',
      NEW.job_id,
      NEW.id
    );
  END IF;

  RETURN NEW;
END;
$$;

-- ─── New job posted → all users except poster (not only current worker mode) ─
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
    WHERE id IS DISTINCT FROM p_job.employer_id
      AND COALESCE(notifications_enabled, true) = true
  LOOP
    INSERT INTO notifications (
      user_id, type, title, body, target_role,
      related_job_id, related_user_id
    ) VALUES (
      v_worker.id,
      'new_job_posted',
      'New job available!',
      v_employer_name || ' posted "' || COALESCE(p_job.title, 'a new job') || '"',
      'worker',
      p_job.id,
      p_job.employer_id
    );
  END LOOP;
END;
$$;

-- ─── Client-driven peer notifications (RLS-safe) ───────────────────────────
CREATE OR REPLACE FUNCTION public.create_peer_notification(
  p_target_user_id uuid,
  p_type text,
  p_title text,
  p_body text,
  p_related_job_id uuid,
  p_target_role text DEFAULT NULL,
  p_related_conversation_id uuid DEFAULT NULL,
  p_related_application_id uuid DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  IF p_target_user_id IS NULL OR p_target_user_id = auth.uid() THEN
    RETURN;
  END IF;

  IF p_related_job_id IS NULL THEN
    RAISE EXCEPTION 'related_job_id required';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM jobs j
    WHERE j.id = p_related_job_id
    AND (
      (j.employer_id = auth.uid() AND EXISTS (
        SELECT 1 FROM job_applications a
        WHERE a.job_id = j.id AND a.worker_id = p_target_user_id))
      OR
      (j.employer_id = p_target_user_id AND EXISTS (
        SELECT 1 FROM job_applications a
        WHERE a.job_id = j.id AND a.worker_id = auth.uid()))
    )
  ) THEN
    RAISE EXCEPTION 'Not allowed';
  END IF;

  INSERT INTO notifications (
    user_id, type, title, body, target_role,
    related_job_id, related_conversation_id, related_application_id
  ) VALUES (
    p_target_user_id,
    p_type,
    p_title,
    p_body,
    p_target_role,
    p_related_job_id,
    p_related_conversation_id,
    p_related_application_id
  );
END;
$$;

REVOKE ALL ON FUNCTION public.create_peer_notification(
  uuid, text, text, text, uuid, text, uuid, uuid
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_peer_notification(
  uuid, text, text, text, uuid, text, uuid, uuid
) TO authenticated;

SELECT '=== NOTIFICATIONS ROLE-AWARE MIGRATION APPLIED ===' AS status;
