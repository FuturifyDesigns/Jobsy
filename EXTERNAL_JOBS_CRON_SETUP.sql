-- ============================================================================
-- EXTERNAL JOBS — CRON SCHEDULE + VAULT SECRET (run AFTER EXTERNAL_JOBS_MIGRATION.sql)
--
-- This schedules import-external-jobs every 8 hours via pg_cron + pg_net.
-- Alternative: Supabase Dashboard → Edge Functions → import-external-jobs
--              → Schedules → Add → Cron: 0 */8 * * *
--
-- Project: jvulfleleybcoljcmpwq
-- ============================================================================

-- 1) Enable extensions (safe if already on)
CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog;
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;

-- 2) Store URL + service role in Vault (skip if secrets already exist in Vault)
SELECT vault.create_secret(
  'https://jvulfleleybcoljcmpwq.supabase.co',
  'jobsy_project_url'
);

SELECT vault.create_secret(
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imp2dWxmbGVsZXliY29samNtcHdxIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2ODc0MDg4OCwiZXhwIjoyMDg0MzE2ODg4fQ.tkX5VP2oBX-Dhruv6zUrpL8p9EmlBFVqf5TYGiuSaeA',
  'jobsy_service_role_key'
);

-- 3) Remove old schedule if re-running this script
SELECT cron.unschedule(jobid)
FROM cron.job
WHERE jobname = 'jobsy-import-external-jobs';

-- 4) Schedule: every 8 hours (0:00, 8:00, 16:00 UTC)
SELECT cron.schedule(
  'jobsy-import-external-jobs',
  '0 */8 * * *',
  $$
  SELECT net.http_post(
    url := (
      SELECT decrypted_secret
      FROM vault.decrypted_secrets
      WHERE name = 'jobsy_project_url'
      LIMIT 1
    ) || '/functions/v1/import-external-jobs',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || (
        SELECT decrypted_secret
        FROM vault.decrypted_secrets
        WHERE name = 'jobsy_service_role_key'
        LIMIT 1
      )
    ),
    body := '{}'::jsonb
  ) AS request_id;
  $$
);

-- 5) Verify schedule exists
SELECT jobid, jobname, schedule, active
FROM cron.job
WHERE jobname = 'jobsy-import-external-jobs';

-- ============================================================================
-- SerpAPI (Google Jobs) — REQUIRED NAME: SERPAPI_API_KEY
--
-- 1. Sign up: https://serpapi.com/users/sign_up
-- 2. Copy key: https://serpapi.com/manage-api-key
-- 3. Supabase Dashboard → Edge Functions → import-external-jobs → Secrets
--    Add secret:  Name = SERPAPI_API_KEY   Value = your key
-- 4. Redeploy function if it was deployed before adding the secret
--
-- Free plan ≈ 100 searches/month. Importer alternates Google Jobs + Facebook (~90/mo each).
-- Without this key, RSS boards still import (Indeed, Sky Jobs, etc.).
-- ============================================================================

-- Manual test (run once after deploy):
-- SELECT net.http_post(
--   url := 'https://jvulfleleybcoljcmpwq.supabase.co/functions/v1/import-external-jobs',
--   headers := jsonb_build_object(
--     'Content-Type', 'application/json',
--     'Authorization', 'Bearer <service_role from Dashboard → Settings → API>'
--   ),
--   body := '{}'::jsonb
-- );
--
-- If you get 401 Unauthorized: redeploy import-external-jobs (auth fix in index.ts),
-- OR set Edge Function secret CRON_SECRET and send Bearer <CRON_SECRET> instead.
