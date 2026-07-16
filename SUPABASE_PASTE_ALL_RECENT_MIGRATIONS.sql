-- ============================================================================
-- JOBSY — Paste this entire file into Supabase → SQL Editor → Run once.
-- Safe to re-run for most statements (uses IF NOT EXISTS / OR REPLACE where possible).
--
-- Contains (in order):
--   1) CONVERSATION_INBOX_AND_NOTIFICATIONS_MIGRATION — inbox_visible, triggers,
--      create_peer_notification, notify_on_application_status (cancel/withdraw), etc.
--   2) APPLICATION_EXTRA_FIELDS_MIGRATION — job_applications extras + storage bucket
--   3) NOTIFICATIONS_NEW_JOB_AND_SOUND_FIX — new-job notify all workers + UPDATE path
--
-- If anything errors with "already exists" or your DB predates Jobsy, run the
-- older scripts in the repo first (see list at bottom of this file in comments).
-- ============================================================================

-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  PART 1 — CONVERSATION INBOX + PEER NOTIFICATIONS RPC                     ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

ALTER TABLE public.conversations
  ADD COLUMN IF NOT EXISTS inbox_visible boolean NOT NULL DEFAULT true;

CREATE OR REPLACE FUNCTION public.recompute_conversation_inbox_visible(p_application_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_visible boolean;
BEGIN
  SELECT
    (a.status IN ('accepted', 'in_progress'))
    AND (j.status IN ('active', 'in_progress'))
  INTO v_visible
  FROM job_applications a
  JOIN jobs j ON j.id = a.job_id
  WHERE a.id = p_application_id;

  IF NOT FOUND THEN
    RETURN;
  END IF;

  UPDATE conversations
  SET inbox_visible = v_visible, updated_at = NOW()
  WHERE application_id = p_application_id;
END;
$$;

REVOKE ALL ON FUNCTION public.recompute_conversation_inbox_visible(uuid) FROM PUBLIC;

UPDATE conversations c
SET inbox_visible = sub.v, updated_at = NOW()
FROM (
  SELECT
    c2.id,
    (
      (a.status IN ('accepted', 'in_progress'))
      AND (j.status IN ('active', 'in_progress'))
    ) AS v
  FROM conversations c2
  JOIN job_applications a ON a.id = c2.application_id
  JOIN jobs j ON j.id = c2.job_id
) AS sub
WHERE c.id = sub.id AND c.inbox_visible IS DISTINCT FROM sub.v;

CREATE OR REPLACE FUNCTION public.trg_recompute_inbox_from_application()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.recompute_conversation_inbox_visible(NEW.id);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_job_applications_recompute_inbox ON job_applications;
CREATE TRIGGER trg_job_applications_recompute_inbox
  AFTER INSERT OR UPDATE OF status ON job_applications
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_recompute_inbox_from_application();

CREATE OR REPLACE FUNCTION public.trg_recompute_inbox_from_job()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  r RECORD;
BEGIN
  IF TG_OP = 'UPDATE' AND NEW.status IS NOT DISTINCT FROM OLD.status THEN
    RETURN NEW;
  END IF;
  FOR r IN SELECT id FROM job_applications WHERE job_id = NEW.id LOOP
    PERFORM public.recompute_conversation_inbox_visible(r.id);
  END LOOP;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_jobs_recompute_inbox ON jobs;
CREATE TRIGGER trg_jobs_recompute_inbox
  AFTER INSERT OR UPDATE OF status ON jobs
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_recompute_inbox_from_job();

CREATE OR REPLACE FUNCTION public.trg_recompute_inbox_new_conversation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.recompute_conversation_inbox_visible(NEW.application_id);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_conversations_recompute_inbox ON conversations;
CREATE TRIGGER trg_conversations_recompute_inbox
  AFTER INSERT ON conversations
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_recompute_inbox_new_conversation();

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
  ELSE
    v_recipient_id := v_employer_id;
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
    user_id, type, title, body,
    related_conversation_id, related_user_id
  ) VALUES (
    v_recipient_id,
    'new_message',
    v_sender_name,
    v_body,
    NEW.conversation_id,
    NEW.sender_id
  );

  RETURN NEW;
END;
$$;

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
        user_id, type, title, body,
        related_job_id, related_application_id
    ) VALUES (
        NEW.worker_id,
        'application_accepted',
        'You got the job!',
        'Your application for "' || COALESCE(v_job_title, 'a job') || '" was accepted',
        NEW.job_id,
        NEW.id
    );
  ELSIF NEW.status = 'rejected' THEN
    SELECT title INTO v_job_title FROM jobs WHERE id = NEW.job_id;
    INSERT INTO notifications (
        user_id, type, title, body,
        related_job_id, related_application_id
    ) VALUES (
        NEW.worker_id,
        'application_rejected',
        'Application Update',
        'Your application for "' || COALESCE(v_job_title, 'a job') || '" was not accepted this time',
        NEW.job_id,
        NEW.id
    );
  ELSIF NEW.status = 'cancelled' THEN
    SELECT title INTO v_job_title FROM jobs WHERE id = NEW.job_id;
    INSERT INTO notifications (
        user_id, type, title, body,
        related_job_id, related_application_id
    ) VALUES (
        NEW.worker_id,
        'application_cancelled',
        'Application closed',
        'Your application for "' || COALESCE(v_job_title, 'a job')
          || '" was closed and the listing may be open again.',
        NEW.job_id,
        NEW.id
    );
  ELSIF NEW.status = 'withdrawn' THEN
    SELECT j.title, j.employer_id INTO v_job_title, v_employer_id FROM jobs j WHERE j.id = NEW.job_id;
    SELECT COALESCE(full_name, 'A worker') INTO v_worker_name FROM profiles WHERE id = NEW.worker_id;
    INSERT INTO notifications (
        user_id, type, title, body,
        related_job_id, related_application_id
    ) VALUES (
        v_employer_id,
        'worker_withdrew',
        'Worker withdrew',
        v_worker_name || ' withdrew from "' || COALESCE(v_job_title, 'a job') || '".',
        NEW.job_id,
        NEW.id
    );
  END IF;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.create_peer_notification(
  p_target_user_id uuid,
  p_type text,
  p_title text,
  p_body text,
  p_related_job_id uuid
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

  INSERT INTO notifications (user_id, type, title, body, related_job_id)
  VALUES (p_target_user_id, p_type, p_title, p_body, p_related_job_id);
END;
$$;

REVOKE ALL ON FUNCTION public.create_peer_notification(uuid, text, text, text, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_peer_notification(uuid, text, text, text, uuid) TO authenticated;

CREATE INDEX IF NOT EXISTS idx_conversations_employer_inbox
  ON conversations (employer_id) WHERE inbox_visible = true;

CREATE INDEX IF NOT EXISTS idx_conversations_worker_inbox
  ON conversations (worker_id) WHERE inbox_visible = true;

-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  PART 2 — APPLICATION EXTRA FIELDS + STORAGE                             ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

ALTER TABLE public.job_applications
  ADD COLUMN IF NOT EXISTS references_text text,
  ADD COLUMN IF NOT EXISTS additional_info text,
  ADD COLUMN IF NOT EXISTS qualification_files jsonb NOT NULL DEFAULT '[]'::jsonb;

COMMENT ON COLUMN public.job_applications.references_text IS
  'Optional: contactable references (names, relationship, phone/email).';
COMMENT ON COLUMN public.job_applications.additional_info IS
  'Optional: any other relevant details for the employer.';
COMMENT ON COLUMN public.job_applications.qualification_files IS
  'JSON array of { "path", "name" } objects under storage bucket application-qualifications.';

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'application-qualifications',
  'application-qualifications',
  false,
  10485760,
  ARRAY[
    'application/pdf',
    'image/jpeg', 'image/png', 'image/webp'
  ]
)
ON CONFLICT (id) DO UPDATE SET
  file_size_limit = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types;

DROP POLICY IF EXISTS "application_qualifications_insert_worker" ON storage.objects;
CREATE POLICY "application_qualifications_insert_worker"
  ON storage.objects FOR INSERT
  TO authenticated
  WITH CHECK (
    bucket_id = 'application-qualifications'
    AND EXISTS (
      SELECT 1 FROM job_applications ja
      WHERE ja.id::text = (storage.foldername(name))[1]
        AND ja.worker_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "application_qualifications_select_parties" ON storage.objects;
CREATE POLICY "application_qualifications_select_parties"
  ON storage.objects FOR SELECT
  TO authenticated
  USING (
    bucket_id = 'application-qualifications'
    AND EXISTS (
      SELECT 1 FROM job_applications ja
      JOIN jobs j ON j.id = ja.job_id
      WHERE ja.id::text = (storage.foldername(name))[1]
        AND (ja.worker_id = auth.uid() OR j.employer_id = auth.uid())
    )
  );

DROP POLICY IF EXISTS "application_qualifications_delete_worker" ON storage.objects;
CREATE POLICY "application_qualifications_delete_worker"
  ON storage.objects FOR DELETE
  TO authenticated
  USING (
    bucket_id = 'application-qualifications'
    AND EXISTS (
      SELECT 1 FROM job_applications ja
      WHERE ja.id::text = (storage.foldername(name))[1]
        AND ja.worker_id = auth.uid()
    )
  );

-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  PART 3 — NEW JOB NOTIFICATIONS (all workers + job became active)         ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

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

SELECT 'JOBSY batch complete: inbox + application fields + new-job notifies' AS status;

/*
  OTHER SQL FILES IN THIS REPO (run if your database is missing those features):

  JOB_CANCEL_MIGRATION.sql                    — worker_withdraw_from_job RPC
  REALTIME_RLS_FIX_MIGRATION.sql              — RLS for jobs, applications, chat
  NOTIFICATIONS_RLS_FIX_MIGRATION.sql         — lock down notification INSERT to service role / triggers
  NOTIFICATIONS_MIGRATION.sql                 — base notifications table + triggers
  NOTIFICATIONS_FIX_MIGRATION.sql           — message attachment notification bodies
  NEW_JOB_NOTIFICATION_MIGRATION.sql        — optional; superseded by Part 3 above
  MESSAGING_MIGRATION.sql                     — conversations / messages
  RATINGS_MIGRATION.sql, ATTACHMENTS_MIGRATION.sql, etc.

  Data wipe (optional, destructive):
  WIPE_USERS_14eb40b3_B501C655.sql
*/
