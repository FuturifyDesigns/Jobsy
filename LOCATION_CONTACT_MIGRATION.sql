-- ============================================================================
-- LOCATION + CONTACT PREVIEWS MIGRATION
-- Run in Supabase SQL Editor. Safe to re-run.
-- Teaches the conversation-preview trigger about two new message types:
--   'location' — lat/lng + reverse-geocoded address, NO storage object
--   'contact'  — name + phone, NO storage object
-- Document previews (message_type='file') already covered in v21 migration.
-- ============================================================================

CREATE OR REPLACE FUNCTION update_conversation_on_message()
RETURNS TRIGGER AS $$
DECLARE
    preview_text text;
BEGIN
    -- Handle delete-for-everyone tombstoning (from v23 migration)
    IF TG_OP = 'UPDATE' AND OLD.deleted_at IS NULL AND NEW.deleted_at IS NOT NULL THEN
        UPDATE conversations
        SET last_message = '🚫 This message was deleted',
            updated_at = NOW()
        WHERE id = NEW.conversation_id
          AND last_message_at <= NEW.created_at + INTERVAL '1 second';
        RETURN NEW;
    END IF;

    IF TG_OP = 'INSERT' THEN
        IF NEW.message_type = 'image' THEN
            preview_text := '📷 Photo';
        ELSIF NEW.message_type = 'voice' THEN
            preview_text := '🎤 Voice message';
        ELSIF NEW.message_type = 'file' THEN
            preview_text := '📎 Document';
        ELSIF NEW.message_type = 'location' THEN
            preview_text := '📍 Location';
        ELSIF NEW.message_type = 'contact' THEN
            preview_text := '👤 Contact';
        ELSE
            preview_text := NEW.message;
        END IF;

        UPDATE conversations
        SET
            last_message = preview_text,
            last_message_at = NEW.created_at,
            updated_at = NOW(),
            employer_unread_count = CASE
                WHEN NEW.sender_id != employer_id THEN employer_unread_count + 1
                ELSE employer_unread_count
            END,
            worker_unread_count = CASE
                WHEN NEW.sender_id != worker_id THEN worker_unread_count + 1
                ELSE worker_unread_count
            END
        WHERE id = NEW.conversation_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger stays the same; only the function body changed.

-- Done.
-- ============================================================================
