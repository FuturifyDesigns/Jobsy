-- ============================================================================
-- NOTIFICATIONS FIX FOR ATTACHMENTS + DOCUMENT MIME TYPES
-- Run in Supabase SQL Editor. Safe to re-run.
--
-- Fixes two bugs:
-- 1. Sending image/voice/file/location/contact fails with
--    "null value in column body of relation notifications violates not-null"
-- 2. Sending PDF fails with "mime type application/pdf is not supported"
-- ============================================================================

-- Part 1: Rewrite notify_on_new_message so body is never null for attachments
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION notify_on_new_message()
RETURNS TRIGGER AS $$
DECLARE
    v_employer_id UUID;
    v_worker_id UUID;
    v_recipient_id UUID;
    v_sender_name TEXT;
    v_body TEXT;
BEGIN
    SELECT employer_id, worker_id
      INTO v_employer_id, v_worker_id
    FROM conversations
    WHERE id = NEW.conversation_id;

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

    -- Build a never-null body based on message_type.
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
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_notify_on_new_message ON messages;
CREATE TRIGGER trg_notify_on_new_message
    AFTER INSERT ON messages
    FOR EACH ROW
    EXECUTE FUNCTION notify_on_new_message();


-- Part 2: Expand chat-attachments bucket MIME allowlist to include documents
-- ----------------------------------------------------------------------------
UPDATE storage.buckets
SET allowed_mime_types = ARRAY[
    -- Images
    'image/jpeg', 'image/png', 'image/webp', 'image/gif',
    -- Audio (voice notes)
    'audio/mpeg', 'audio/mp4', 'audio/m4a', 'audio/aac',
    'audio/wav', 'audio/webm', 'audio/ogg',
    -- Documents (unblocks PDF sending)
    'application/pdf',
    'application/msword',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'text/plain'
]
WHERE id = 'chat-attachments';

-- Verify:
--   SELECT allowed_mime_types FROM storage.buckets WHERE id = 'chat-attachments';
-- ============================================================================
