-- ============================================================================
-- JOBSY: Conversation inbox visibility + peer notifications RPC
-- Run in Supabase → SQL Editor (safe to re-run).
--
-- 1. conversations.inbox_visible — false when the job/application pair is not
--    an active engagement (messages list / unread counts use this).
-- 2. Triggers keep it in sync on job_applications, jobs, new conversations.
-- 3. notify_on_new_message skips hidden threads (no push noise after close).
-- 4. notify_on_application_status — cancelled / withdrawn notify the other
--    party (insert uses SECURITY DEFINER → FCM webhook still works).
-- 5. create_peer_notification — for client-driven events (job marked complete,
--    worker marked done, ratings) now that RLS blocks direct INSERTs.
-- ============================================================================

-- ─── 1. Column ───────────────────────────────────────────────────────────
ALTER TABLE public.conversations
  ADD COLUMN IF NOT EXISTS inbox_visible boolean NOT NULL DEFAULT true;

-- ─── 2. Recompute helper ───────────────────────────────────────────────────
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

-- ─── 3. Initial backfill ────────────────────────────────────────────────────
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

-- ─── 4. Triggers ───────────────────────────────────────────────────────────
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

-- ─── 5. Skip pushes for hidden conversations ───────────────────────────────
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

-- ─── 6. Application status → notify worker / employer ──────────────────────
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

-- ─── 7. RPC for chat / ratings (RLS-safe) ──────────────────────────────────
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

SELECT '=== CONVERSATION INBOX + NOTIFICATIONS MIGRATION APPLIED ===' AS status;
