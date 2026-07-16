-- ============================================================================
-- JOBSY: Delete jobs, applications, and chat for two users (data cleanup only)
-- ============================================================================
-- Run the whole script once in Supabase → SQL Editor (single run).
--
-- Targets:
--   14eb40b3-ef2d-4bad-89aa-9c311fed3244
--   b501c655-4c38-43f3-8af4-ff4f93c928ea
--
-- Uses a PL/pgSQL DO block so it works even when the editor splits statements;
-- no TEMP TABLE (those can disappear between batches).
--
-- Does NOT touch: storage, profiles, auth.users
-- ============================================================================

DO $$
DECLARE
  victims uuid[] := ARRAY[
    '14eb40b3-ef2d-4bad-89aa-9c311fed3244'::uuid,
    'b501c655-4c38-43f3-8af4-ff4f93c928ea'::uuid
  ];
BEGIN
  DELETE FROM notifications n
  WHERE n.user_id = ANY (victims)
     OR n.related_user_id = ANY (victims);

  DELETE FROM saved_jobs s
  WHERE s.worker_id = ANY (victims);

  DELETE FROM job_applications a
  WHERE a.worker_id = ANY (victims)
     OR a.job_id IN (
       SELECT j.id FROM jobs j
       WHERE j.employer_id = ANY (victims)
     );

  DELETE FROM jobs j
  WHERE j.employer_id = ANY (victims);
END $$;

SELECT 'Jobs, applications, and related chat cleared (profiles & storage untouched).' AS status;
