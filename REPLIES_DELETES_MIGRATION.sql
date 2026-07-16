-- ============================================================================
-- REPLIES & DELETES MIGRATION
-- Run in Supabase SQL Editor. Safe to re-run (uses IF NOT EXISTS).
-- Adds reply-to, delete-for-me, and delete-for-everyone to messages.
-- ============================================================================

-- 1. Add columns
-- reply_to_id: references another message.id; null for non-reply messages
-- deleted_at: timestamp if "deleted for everyone" by sender (tombstoned)
-- hidden_for: array of user ids who ran "delete for me" (private hide)
-- ----------------------------------------------------------------------------
ALTER TABLE messages
  ADD COLUMN IF NOT EXISTS reply_to_id uuid REFERENCES messages(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS deleted_at timestamptz,
  ADD COLUMN IF NOT EXISTS hidden_for uuid[] NOT NULL DEFAULT ARRAY[]::uuid[];

CREATE INDEX IF NOT EXISTS idx_messages_reply_to ON messages(reply_to_id);
CREATE INDEX IF NOT EXISTS idx_messages_deleted_at ON messages(deleted_at);


-- 2. Conversation preview trigger: tombstoned messages should not update preview
-- with their (now-irrelevant) content. Also, attachments keep the emoji prefix.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION update_conversation_on_message()
RETURNS TRIGGER AS $$
DECLARE
    preview_text text;
BEGIN
    -- If this is a tombstone update (deleted_at being set), set a tombstone preview
    IF TG_OP = 'UPDATE' AND OLD.deleted_at IS NULL AND NEW.deleted_at IS NOT NULL THEN
        UPDATE conversations
        SET last_message = '🚫 This message was deleted',
            updated_at = NOW()
        WHERE id = NEW.conversation_id
          AND last_message_at <= NEW.created_at + INTERVAL '1 second';  -- only if this was the last one
        RETURN NEW;
    END IF;

    -- For inserts, build the preview based on message_type
    IF TG_OP = 'INSERT' THEN
        IF NEW.message_type = 'image' THEN
            preview_text := '📷 Photo';
        ELSIF NEW.message_type = 'voice' THEN
            preview_text := '🎤 Voice message';
        ELSIF NEW.message_type = 'file' THEN
            preview_text := '📎 File';
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

-- Attach trigger to both INSERT and UPDATE
DROP TRIGGER IF EXISTS conversation_on_new_message ON messages;
CREATE TRIGGER conversation_on_new_message
AFTER INSERT OR UPDATE ON messages
FOR EACH ROW EXECUTE FUNCTION update_conversation_on_message();


-- 3. RLS: allow message sender to update their own messages (for delete_for_everyone)
--    and allow any participant to update hidden_for (for delete_for_me)
-- ----------------------------------------------------------------------------
DO $$
BEGIN
  -- Check if the update policy already exists and drop it to re-create
  IF EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'messages' AND policyname = 'Users can update their own messages or hide'
  ) THEN
    DROP POLICY "Users can update their own messages or hide" ON messages;
  END IF;
END $$;

CREATE POLICY "Users can update their own messages or hide"
ON messages FOR UPDATE
TO authenticated
USING (
  -- Sender can update their own message (for tombstoning)
  sender_id = auth.uid()
  OR
  -- Any conversation participant can update (we check WHAT they update in app code: only hidden_for)
  EXISTS (
    SELECT 1 FROM conversations c
    WHERE c.id = messages.conversation_id
      AND (c.employer_id = auth.uid() OR c.worker_id = auth.uid())
  )
)
WITH CHECK (
  sender_id = auth.uid()
  OR
  EXISTS (
    SELECT 1 FROM conversations c
    WHERE c.id = messages.conversation_id
      AND (c.employer_id = auth.uid() OR c.worker_id = auth.uid())
  )
);


-- 4. Done. Verify:
-- SELECT column_name FROM information_schema.columns WHERE table_name = 'messages' AND column_name IN ('reply_to_id','deleted_at','hidden_for');
-- SELECT policyname FROM pg_policies WHERE tablename = 'messages';
-- ============================================================================
