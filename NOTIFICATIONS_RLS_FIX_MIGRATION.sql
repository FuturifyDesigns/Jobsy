-- ============================================================
-- NOTIFICATIONS RLS FIX
-- Run this in Supabase → SQL Editor
--
-- Problem: The original INSERT policy was:
--   WITH CHECK (auth.role() = 'authenticated')
-- This lets any signed-in user insert a notification for ANY
-- user_id — a client could spam another user's notification feed.
--
-- Fix: Only the service role (edge functions / webhooks) may
-- INSERT notifications.  Authenticated clients may only SELECT
-- and UPDATE their own rows.
-- ============================================================

-- 1. Drop the overly-permissive original INSERT policy if it exists
DROP POLICY IF EXISTS "Authenticated users can insert notifications" ON notifications;
DROP POLICY IF EXISTS "Users can insert notifications" ON notifications;
DROP POLICY IF EXISTS "Allow authenticated inserts" ON notifications;

-- 2. Make sure RLS is enabled
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;

-- 3. SELECT — users can only see their own notifications
DROP POLICY IF EXISTS "Users can view own notifications" ON notifications;
CREATE POLICY "Users can view own notifications"
  ON notifications FOR SELECT
  USING (auth.uid() = user_id);

-- 4. UPDATE — users can mark their own notifications as read
DROP POLICY IF EXISTS "Users can update own notifications" ON notifications;
CREATE POLICY "Users can update own notifications"
  ON notifications FOR UPDATE
  USING  (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- 5. DELETE — users can delete their own notifications
DROP POLICY IF EXISTS "Users can delete own notifications" ON notifications;
CREATE POLICY "Users can delete own notifications"
  ON notifications FOR DELETE
  USING (auth.uid() = user_id);

-- 6. INSERT — deliberately NO policy for the `authenticated` role.
--    Edge functions use the service_role key which bypasses RLS entirely,
--    so they can still insert.  Regular app clients cannot.
--    (If your app inserts notifications client-side anywhere, move that
--     logic to an edge function or a Postgres function with SECURITY DEFINER.)
