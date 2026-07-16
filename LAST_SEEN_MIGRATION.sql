-- ============================================================================
-- LAST SEEN MIGRATION
-- Run in Supabase SQL Editor. Safe to re-run.
-- Adds `last_seen_at` to profiles for "Last seen Xm ago" indicators in chat.
-- Event-based — clients write on app open, chat open, message send, chat-list open.
-- ============================================================================

ALTER TABLE profiles
  ADD COLUMN IF NOT EXISTS last_seen_at timestamptz;

-- Index for the rare query where we look up someone's last_seen directly
-- (typical access pattern is a full SELECT on profile row, so this is optional)
CREATE INDEX IF NOT EXISTS idx_profiles_last_seen ON profiles(last_seen_at);

-- Existing profiles RLS already allows authenticated users to SELECT any profile
-- (needed for showing names/avatars in chat), so no new policy needed.

-- Allow users to UPDATE their own last_seen_at.
-- This policy may already exist if users can update their own profile —
-- we check and only add if missing.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'profiles'
      AND policyname = 'Users can update own profile'
  ) THEN
    CREATE POLICY "Users can update own profile"
    ON profiles FOR UPDATE
    TO authenticated
    USING (auth.uid() = id)
    WITH CHECK (auth.uid() = id);
  END IF;
END $$;

-- Done.
-- ============================================================================
