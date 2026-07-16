-- ============================================================================
-- JOBSY RATINGS MIGRATION
-- Adds mutual completion tracking and a full ratings system.
-- Run this in Supabase SQL Editor.
-- ============================================================================

-- ============================================================================
-- 1. WORKER COMPLETION FLAG ON JOB_APPLICATIONS
-- ============================================================================

ALTER TABLE job_applications
  ADD COLUMN IF NOT EXISTS worker_completed BOOLEAN NOT NULL DEFAULT FALSE;


-- ============================================================================
-- 2. RATINGS TABLE
-- ============================================================================

CREATE TABLE IF NOT EXISTS ratings (
  id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  rater_id        UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  rated_id        UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  job_id          UUID        NOT NULL REFERENCES jobs(id) ON DELETE CASCADE,
  application_id  UUID        NOT NULL REFERENCES job_applications(id) ON DELETE CASCADE,
  rating          INTEGER     NOT NULL CHECK (rating BETWEEN 1 AND 5),
  review          TEXT        CHECK (char_length(review) <= 500),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  -- One rating per rater per application
  UNIQUE (rater_id, application_id)
);

-- ============================================================================
-- 3. RLS ON RATINGS
-- ============================================================================

ALTER TABLE ratings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Ratings are publicly readable"  ON ratings;
DROP POLICY IF EXISTS "Users can insert own ratings"   ON ratings;

CREATE POLICY "Ratings are publicly readable"
  ON ratings FOR SELECT USING (true);

CREATE POLICY "Users can insert own ratings"
  ON ratings FOR INSERT
  WITH CHECK (auth.uid() = rater_id);

-- ============================================================================
-- 4. AUTO-UPDATE profiles.rating WHEN A RATING IS INSERTED
--    Stores a rounded average (1 decimal) of all ratings for that user.
-- ============================================================================

-- Ensure the column exists (it may already be there)
ALTER TABLE profiles
  ADD COLUMN IF NOT EXISTS rating NUMERIC(3,1);

-- SECURITY DEFINER: the rater is not allowed to UPDATE the rated user's row
-- under normal profiles RLS, but the aggregate must still be written.
CREATE OR REPLACE FUNCTION update_profile_rating()
RETURNS TRIGGER LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE profiles
  SET rating = (
    SELECT ROUND(AVG(r.rating)::numeric, 1)
    FROM  ratings r
    WHERE r.rated_id = NEW.rated_id
  )
  WHERE id = NEW.rated_id;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_update_profile_rating ON ratings;
CREATE TRIGGER trg_update_profile_rating
  AFTER INSERT ON ratings
  FOR EACH ROW EXECUTE FUNCTION update_profile_rating();

-- ============================================================================
-- 5. REALTIME FOR RATINGS (so chat screen can react immediately)
-- ============================================================================

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'ratings'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE ratings;
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Realtime publication update skipped: %', SQLERRM;
END;
$$;

-- ============================================================================
-- DONE ✅
-- ============================================================================
SELECT 'RATINGS_MIGRATION complete' AS status;
