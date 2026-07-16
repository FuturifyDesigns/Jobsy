-- ============================================================================
-- JOBSY NOTIFICATIONS SYSTEM
-- ============================================================================
-- Safe to run multiple times. Creates notifications table with RLS,
-- indexes, realtime support, and triggers that auto-create notifications
-- when significant events happen (new messages, new applications,
-- application status changes).
-- ============================================================================

-- ============================================================================
-- 1. NOTIFICATIONS TABLE
-- ============================================================================

CREATE TABLE IF NOT EXISTS notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    type TEXT NOT NULL,           -- 'new_message', 'new_application',
                                  -- 'application_accepted', 'application_rejected',
                                  -- 'job_update', 'system'
    title TEXT NOT NULL,
    body TEXT NOT NULL,
    
    -- optional links to related entities (all nullable)
    related_job_id UUID REFERENCES jobs(id) ON DELETE CASCADE,
    related_application_id UUID REFERENCES job_applications(id) ON DELETE CASCADE,
    related_conversation_id UUID REFERENCES conversations(id) ON DELETE CASCADE,
    related_user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    
    is_read BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================================
-- 2. INDEXES
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_notifications_user
    ON notifications(user_id);
CREATE INDEX IF NOT EXISTS idx_notifications_user_unread
    ON notifications(user_id, is_read)
    WHERE is_read = FALSE;
CREATE INDEX IF NOT EXISTS idx_notifications_created
    ON notifications(created_at DESC);

-- ============================================================================
-- 3. ROW LEVEL SECURITY
-- ============================================================================

ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own notifications" ON notifications;
DROP POLICY IF EXISTS "Users can update own notifications" ON notifications;
DROP POLICY IF EXISTS "Users can delete own notifications" ON notifications;
DROP POLICY IF EXISTS "Authenticated users can insert notifications" ON notifications;

-- Users can only SEE their own notifications
CREATE POLICY "Users can view own notifications"
    ON notifications FOR SELECT
    USING (auth.uid() = user_id);

-- Users can mark their own notifications as read
CREATE POLICY "Users can update own notifications"
    ON notifications FOR UPDATE
    USING (auth.uid() = user_id);

-- Users can delete their own notifications
CREATE POLICY "Users can delete own notifications"
    ON notifications FOR DELETE
    USING (auth.uid() = user_id);

-- Any authenticated user can create notifications
-- (the triggers below will also insert on their behalf, running as the 
-- signed-in user, so they need this policy too)
CREATE POLICY "Authenticated users can insert notifications"
    ON notifications FOR INSERT
    WITH CHECK (auth.role() = 'authenticated');

-- ============================================================================
-- 4. TRIGGERS: AUTO-CREATE NOTIFICATIONS ON EVENTS
-- ============================================================================

-- ---------- New message -> notify the recipient ----------
CREATE OR REPLACE FUNCTION notify_on_new_message()
RETURNS TRIGGER AS $$
DECLARE
    v_employer_id UUID;
    v_worker_id UUID;
    v_recipient_id UUID;
    v_sender_name TEXT;
BEGIN
    -- Find the conversation participants
    SELECT employer_id, worker_id
      INTO v_employer_id, v_worker_id
    FROM conversations
    WHERE id = NEW.conversation_id;

    -- Recipient is whichever participant isn't the sender
    IF NEW.sender_id = v_employer_id THEN
        v_recipient_id := v_worker_id;
    ELSE
        v_recipient_id := v_employer_id;
    END IF;

    -- Pull the sender's display name (best effort)
    SELECT COALESCE(full_name, 'Someone')
      INTO v_sender_name
    FROM profiles
    WHERE id = NEW.sender_id;

    IF v_sender_name IS NULL THEN
        v_sender_name := 'Someone';
    END IF;

    INSERT INTO notifications (
        user_id, type, title, body,
        related_conversation_id, related_user_id
    ) VALUES (
        v_recipient_id,
        'new_message',
        v_sender_name,
        CASE
            WHEN LENGTH(NEW.message) > 80
                THEN SUBSTRING(NEW.message, 1, 80) || '...'
            ELSE NEW.message
        END,
        NEW.conversation_id,
        NEW.sender_id
    );

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_notify_on_new_message ON messages;
CREATE TRIGGER trg_notify_on_new_message
    AFTER INSERT ON messages
    FOR EACH ROW
    EXECUTE FUNCTION notify_on_new_message();

-- ---------- New application -> notify the employer ----------
CREATE OR REPLACE FUNCTION notify_on_new_application()
RETURNS TRIGGER AS $$
DECLARE
    v_employer_id UUID;
    v_job_title TEXT;
    v_worker_name TEXT;
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
        user_id, type, title, body,
        related_job_id, related_application_id, related_user_id
    ) VALUES (
        v_employer_id,
        'new_application',
        'New Application',
        v_worker_name || ' applied to "' || COALESCE(v_job_title, 'your job') || '"',
        NEW.job_id,
        NEW.id,
        NEW.worker_id
    );

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_notify_on_new_application ON job_applications;
CREATE TRIGGER trg_notify_on_new_application
    AFTER INSERT ON job_applications
    FOR EACH ROW
    EXECUTE FUNCTION notify_on_new_application();

-- ---------- Application status change -> notify the worker ----------
CREATE OR REPLACE FUNCTION notify_on_application_status()
RETURNS TRIGGER AS $$
DECLARE
    v_job_title TEXT;
    v_notif_type TEXT;
    v_notif_title TEXT;
    v_notif_body TEXT;
BEGIN
    -- Only fire when status actually changes
    IF NEW.status = OLD.status THEN
        RETURN NEW;
    END IF;

    -- Only notify on accepted/rejected
    IF NEW.status NOT IN ('accepted', 'rejected') THEN
        RETURN NEW;
    END IF;

    SELECT title INTO v_job_title FROM jobs WHERE id = NEW.job_id;

    IF NEW.status = 'accepted' THEN
        v_notif_type  := 'application_accepted';
        v_notif_title := 'You got the job!';
        v_notif_body  := 'Your application for "' ||
                          COALESCE(v_job_title, 'a job') ||
                          '" was accepted';
    ELSE
        v_notif_type  := 'application_rejected';
        v_notif_title := 'Application Update';
        v_notif_body  := 'Your application for "' ||
                          COALESCE(v_job_title, 'a job') ||
                          '" was not accepted this time';
    END IF;

    INSERT INTO notifications (
        user_id, type, title, body,
        related_job_id, related_application_id
    ) VALUES (
        NEW.worker_id,
        v_notif_type,
        v_notif_title,
        v_notif_body,
        NEW.job_id,
        NEW.id
    );

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_notify_on_application_status ON job_applications;
CREATE TRIGGER trg_notify_on_application_status
    AFTER UPDATE ON job_applications
    FOR EACH ROW
    EXECUTE FUNCTION notify_on_application_status();

-- ============================================================================
-- 5. REALTIME PUBLICATION
-- ============================================================================
-- Make sure supabase_realtime publication includes the table so that
-- Flutter can subscribe. Wrapped in DO block so it no-ops if already added.

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables
        WHERE pubname = 'supabase_realtime'
          AND tablename = 'notifications'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE notifications;
    END IF;
EXCEPTION WHEN OTHERS THEN
    -- ignore if publication doesn't exist (self-hosted setups)
    NULL;
END $$;

-- ============================================================================
-- DONE
-- ============================================================================
