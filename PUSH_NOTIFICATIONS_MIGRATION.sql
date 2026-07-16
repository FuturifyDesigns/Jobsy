-- ============================================================================
-- JOBSY PUSH NOTIFICATIONS MIGRATION (v30)
-- ============================================================================
-- Safe to run multiple times (all statements are idempotent).
-- Adds FCM token storage to profiles so Supabase Edge Functions can
-- look up the recipient's device token and send push notifications.
-- ============================================================================

-- 1. Add FCM token column to profiles
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS fcm_token TEXT;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS device_platform TEXT; -- 'android' or 'ios'

-- 2. Index for quick token lookups by user ID (the Edge Function does this)
CREATE INDEX IF NOT EXISTS idx_profiles_fcm_token
    ON profiles(id)
    WHERE fcm_token IS NOT NULL;

-- 3. RLS: users can update their own fcm_token
-- (The existing "Users can update own profile" policy should cover this,
--  but if it doesn't exist, create it.)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'profiles'
          AND policyname = 'Users can update own profile'
    ) THEN
        CREATE POLICY "Users can update own profile"
            ON profiles FOR UPDATE
            USING (auth.uid() = id)
            WITH CHECK (auth.uid() = id);
    END IF;
END $$;

-- ============================================================================
-- DONE — Now deploy the Edge Function (see PUSH_NOTIFICATIONS_GUIDE.md)
-- ============================================================================
