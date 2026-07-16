-- ============================================================================
-- JOBSY NOTIFICATION PREFERENCES MIGRATION (v30)
-- ============================================================================
-- Safe to run multiple times. Adds a notifications_enabled flag to profiles
-- so the Edge Function can skip sending pushes to users who opted out.
-- ============================================================================

-- Add the column (defaults to true — everyone gets notifications unless they opt out)
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS notifications_enabled BOOLEAN DEFAULT TRUE;

-- Message alerts: controls whether new_message pushes are sent
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS message_alerts_enabled BOOLEAN DEFAULT TRUE;

-- ============================================================================
-- DONE
-- ============================================================================
