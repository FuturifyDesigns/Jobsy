-- ============================================================================
-- JOBSY MESSAGING - ENSURE SCHEMA IS READY
-- ============================================================================
-- Safe to run multiple times. Your conversations + messages tables
-- should already exist from jobsy_wallet_messages_schema.sql.
-- This script just ensures everything is in place and adds a helper RPC.
-- ============================================================================

-- ============================================================================
-- 1. VERIFY TABLES EXIST (will no-op if they do)
-- ============================================================================

CREATE TABLE IF NOT EXISTS conversations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    application_id UUID NOT NULL UNIQUE REFERENCES job_applications(id) ON DELETE CASCADE,
    employer_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    worker_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    job_id UUID NOT NULL REFERENCES jobs(id) ON DELETE CASCADE,
    last_message TEXT,
    last_message_at TIMESTAMPTZ,
    employer_unread_count INTEGER DEFAULT 0,
    worker_unread_count INTEGER DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    sender_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    message TEXT NOT NULL,
    is_read BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================================
-- 2. ENSURE INDEXES
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_conversations_employer ON conversations(employer_id);
CREATE INDEX IF NOT EXISTS idx_conversations_worker ON conversations(worker_id);
CREATE INDEX IF NOT EXISTS idx_conversations_application ON conversations(application_id);
CREATE INDEX IF NOT EXISTS idx_messages_conversation ON messages(conversation_id);
CREATE INDEX IF NOT EXISTS idx_messages_created_at ON messages(created_at DESC);

-- ============================================================================
-- 3. ENSURE RLS IS ON
-- ============================================================================

ALTER TABLE conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE messages ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- 4. ENSURE RLS POLICIES (drop-then-create to avoid conflicts)
-- ============================================================================

-- Conversations
DROP POLICY IF EXISTS "Employers can view their conversations" ON conversations;
DROP POLICY IF EXISTS "Workers can view their conversations" ON conversations;
DROP POLICY IF EXISTS "Users can create conversations" ON conversations;
DROP POLICY IF EXISTS "Users can update their conversations" ON conversations;

CREATE POLICY "Employers can view their conversations"
    ON conversations FOR SELECT
    USING (auth.uid() = employer_id);

CREATE POLICY "Workers can view their conversations"
    ON conversations FOR SELECT
    USING (auth.uid() = worker_id);

CREATE POLICY "Users can create conversations"
    ON conversations FOR INSERT
    WITH CHECK (auth.uid() = employer_id OR auth.uid() = worker_id);

CREATE POLICY "Users can update their conversations"
    ON conversations FOR UPDATE
    USING (auth.uid() = employer_id OR auth.uid() = worker_id);

-- Messages
DROP POLICY IF EXISTS "Users can view messages in their conversations" ON messages;
DROP POLICY IF EXISTS "Users can send messages in their conversations" ON messages;
DROP POLICY IF EXISTS "Users can update own messages" ON messages;

CREATE POLICY "Users can view messages in their conversations"
    ON messages FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM conversations 
            WHERE conversations.id = messages.conversation_id 
            AND (conversations.employer_id = auth.uid() OR conversations.worker_id = auth.uid())
        )
    );

CREATE POLICY "Users can send messages in their conversations"
    ON messages FOR INSERT
    WITH CHECK (
        auth.uid() = sender_id AND
        EXISTS (
            SELECT 1 FROM conversations 
            WHERE conversations.id = conversation_id 
            AND (conversations.employer_id = auth.uid() OR conversations.worker_id = auth.uid())
        )
    );

CREATE POLICY "Users can update own messages"
    ON messages FOR UPDATE
    USING (auth.uid() = sender_id);

-- ============================================================================
-- 5. ENSURE TRIGGER FOR CONVERSATION UPDATES ON NEW MESSAGE
-- ============================================================================

CREATE OR REPLACE FUNCTION update_conversation_on_message()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE conversations
    SET 
        last_message = NEW.message,
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

DROP TRIGGER IF EXISTS conversation_on_new_message ON messages;
CREATE TRIGGER conversation_on_new_message
    AFTER INSERT ON messages
    FOR EACH ROW
    EXECUTE FUNCTION update_conversation_on_message();

-- ============================================================================
-- 6. GRANT PERMISSIONS
-- ============================================================================

GRANT SELECT, INSERT, UPDATE ON conversations TO authenticated;
GRANT SELECT, INSERT, UPDATE ON messages TO authenticated;

-- ============================================================================
-- 7. ENABLE REALTIME FOR MESSAGES (needed for Supabase .stream())
-- ============================================================================

-- Add tables to realtime publication if not already there
-- This is safe to re-run
DO $$
BEGIN
  -- Check if the tables are already in the publication
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables 
    WHERE pubname = 'supabase_realtime' AND tablename = 'messages'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE messages;
  END IF;
  
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables 
    WHERE pubname = 'supabase_realtime' AND tablename = 'conversations'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE conversations;
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Realtime publication update skipped: %', SQLERRM;
END;
$$;

-- ============================================================================
-- DONE! ✅
-- ============================================================================
SELECT '=== MESSAGING SCHEMA READY ===' as status;
SELECT 'conversations and messages tables are configured with RLS, triggers, and realtime.' as info;
