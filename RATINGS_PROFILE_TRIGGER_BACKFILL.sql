-- ============================================================================
-- JOBSY: Fix rating trigger (SECURITY DEFINER) + backfill profiles.rating
-- Run if ratings exist but profiles.rating stayed null (RLS blocked updates).
-- Safe to run multiple times.
-- ============================================================================

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

UPDATE profiles p
SET rating = sub.avg_r
FROM (
  SELECT rated_id, ROUND(AVG(rating::numeric), 1) AS avg_r
  FROM ratings
  GROUP BY rated_id
) sub
WHERE p.id = sub.rated_id;

SELECT 'RATINGS_PROFILE_TRIGGER_BACKFILL complete' AS status;
