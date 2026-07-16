-- ============================================================================
-- JOBSY NEW JOB NOTIFICATION TRIGGER (v30)
-- ============================================================================
-- Safe to run multiple times. When an employer posts a new job (INSERT into
-- jobs with status = 'active'), this trigger creates a notification for
-- every worker who has an FCM token registered (i.e. they use the app).
--
-- This keeps notifications targeted — only active app users get notified,
-- not dormant accounts with no device token.
-- ============================================================================

CREATE OR REPLACE FUNCTION notify_workers_on_new_job()
RETURNS TRIGGER AS $$
DECLARE
    v_employer_name TEXT;
    v_worker RECORD;
BEGIN
    -- Only fire for active jobs (skip drafts etc.)
    IF NEW.status <> 'active' THEN
        RETURN NEW;
    END IF;

    -- Get employer's name
    SELECT COALESCE(full_name, 'An employer')
      INTO v_employer_name
    FROM profiles
    WHERE id = NEW.employer_id;

    IF v_employer_name IS NULL THEN
        v_employer_name := 'An employer';
    END IF;

    -- Notify each worker who has the app installed (has an fcm_token)
    FOR v_worker IN
        SELECT id FROM profiles
        WHERE user_type = 'worker'
          AND fcm_token IS NOT NULL
          AND id <> NEW.employer_id  -- don't notify the poster
    LOOP
        INSERT INTO notifications (
            user_id, type, title, body,
            related_job_id, related_user_id
        ) VALUES (
            v_worker.id,
            'new_job_posted',
            'New job available!',
            v_employer_name || ' posted "' || COALESCE(NEW.title, 'a new job') || '"',
            NEW.id,
            NEW.employer_id
        );
    END LOOP;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_notify_workers_on_new_job ON jobs;
CREATE TRIGGER trg_notify_workers_on_new_job
    AFTER INSERT ON jobs
    FOR EACH ROW
    EXECUTE FUNCTION notify_workers_on_new_job();

-- ============================================================================
-- DONE
-- ============================================================================
