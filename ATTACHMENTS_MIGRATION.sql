-- ============================================================================
-- ATTACHMENTS MIGRATION
-- Run this in Supabase SQL Editor. Safe to re-run (uses IF NOT EXISTS).
-- Adds support for image (and later voice) attachments in chat messages.
-- ============================================================================

-- 1. Add columns to messages table
-- message_type: 'text' | 'image' | 'voice' | 'file'
-- attachment_url: public URL to the uploaded file
-- attachment_meta: JSON blob for future extensibility (size, mime, width/height, duration)
-- ----------------------------------------------------------------------------
ALTER TABLE messages
  ADD COLUMN IF NOT EXISTS message_type text NOT NULL DEFAULT 'text',
  ADD COLUMN IF NOT EXISTS attachment_url text,
  ADD COLUMN IF NOT EXISTS attachment_meta jsonb;

-- Allow 'message' column to be nullable for attachment-only messages (e.g. image with no caption)
ALTER TABLE messages ALTER COLUMN message DROP NOT NULL;

-- Add index on message_type for querying attachments efficiently
CREATE INDEX IF NOT EXISTS idx_messages_type ON messages(message_type);


-- 2. Create chat-attachments storage bucket (private — signed URLs only)
-- ----------------------------------------------------------------------------
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'chat-attachments',
  'chat-attachments',
  false,  -- private bucket, access via signed URLs
  10485760,  -- 10 MB cap per file
  ARRAY[
    'image/jpeg', 'image/png', 'image/webp', 'image/gif',
    'audio/mpeg', 'audio/mp4', 'audio/m4a', 'audio/aac', 'audio/wav', 'audio/webm', 'audio/ogg'
  ]
) ON CONFLICT (id) DO UPDATE SET
  file_size_limit = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types;


-- 3. RLS policies on storage.objects for this bucket
-- Path convention: {conversation_id}/{message_id}.{ext}
-- Authenticated users can read any attachment in a conversation they participate in.
-- Authenticated users can upload to a conversation they participate in.
-- ----------------------------------------------------------------------------

-- Drop old policies if present so re-runs don't fail
DROP POLICY IF EXISTS "chat_attachments_select" ON storage.objects;
DROP POLICY IF EXISTS "chat_attachments_insert" ON storage.objects;
DROP POLICY IF EXISTS "chat_attachments_delete" ON storage.objects;

-- SELECT: user can read a file if they are a participant in the conversation
-- (folder name = conversation_id, we check conversations table for membership)
CREATE POLICY "chat_attachments_select"
ON storage.objects FOR SELECT
TO authenticated
USING (
  bucket_id = 'chat-attachments'
  AND EXISTS (
    SELECT 1 FROM conversations c
    WHERE c.id::text = (storage.foldername(name))[1]
      AND (c.employer_id = auth.uid() OR c.worker_id = auth.uid())
  )
);

-- INSERT: user can upload to a conversation they participate in
CREATE POLICY "chat_attachments_insert"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'chat-attachments'
  AND EXISTS (
    SELECT 1 FROM conversations c
    WHERE c.id::text = (storage.foldername(name))[1]
      AND (c.employer_id = auth.uid() OR c.worker_id = auth.uid())
  )
);

-- DELETE: user can delete their own files (optional — we don't expose delete UI yet)
CREATE POLICY "chat_attachments_delete"
ON storage.objects FOR DELETE
TO authenticated
USING (
  bucket_id = 'chat-attachments'
  AND owner = auth.uid()
);


-- 4. Update the conversation-preview trigger so attachment messages get a nice
--    placeholder preview (e.g. "📷 Photo") instead of NULL.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION update_conversation_on_message()
RETURNS TRIGGER AS $$
DECLARE
    preview_text text;
BEGIN
    -- Build a preview based on message_type
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
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- 5. Done. Verify with:
-- ----------------------------------------------------------------------------
-- SELECT column_name, data_type, is_nullable FROM information_schema.columns WHERE table_name = 'messages';
-- SELECT * FROM storage.buckets WHERE id = 'chat-attachments';
-- SELECT policyname FROM pg_policies WHERE tablename = 'objects' AND policyname LIKE 'chat_attachments%';

-- ============================================================================
-- NOTE ON CONVERSATIONS SCHEMA
-- This migration assumes your conversations table has columns:
--   id (uuid), employer_id (uuid), worker_id (uuid)
-- If your column names differ (e.g. user1_id / user2_id), adjust the 3 policies above accordingly.
-- ============================================================================
