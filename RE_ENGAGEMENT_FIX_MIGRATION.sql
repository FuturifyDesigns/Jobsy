-- ============================================================================
-- RE-ENGAGEMENT FIX — run once in Supabase SQL Editor
-- Ensures inactive-user detection works for re-engagement pushes.
-- ============================================================================

-- 1. Backfill last_seen_at so users aren't excluded with NULL timestamps
UPDATE public.profiles
SET last_seen_at = COALESCE(last_seen_at, created_at, NOW())
WHERE last_seen_at IS NULL;

-- 2. Index for re-engagement scans (notifications on + last activity)
CREATE INDEX IF NOT EXISTS idx_profiles_reengagement
  ON public.profiles (last_seen_at)
  WHERE COALESCE(notifications_enabled, true) = true;

-- 3. Ensure target_role exists (from NOTIFICATIONS_ROLE_AWARE_MIGRATION)
ALTER TABLE public.notifications
  ADD COLUMN IF NOT EXISTS target_role TEXT;

SELECT '=== RE-ENGAGEMENT FIX APPLIED ===' AS status;
