-- ============================================================================
-- EXTERNAL / WEB JOBS — auto-imported listings from online job boards
-- Run once in Supabase SQL Editor.
--
-- Setup after this migration:
--   1. Deploy: supabase functions deploy import-external-jobs
--   2. Secrets: SERPAPI_API_KEY (optional — Google Jobs + Facebook via Google site: search)
--   3. Schedule cron (recommended): 0 */8 * * *  (every 8 hours)
--      The importer rotates sources each run so rate limits are not hit.
-- ============================================================================

-- ── Listings table ───────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.external_jobs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  external_id TEXT NOT NULL UNIQUE,
  source TEXT NOT NULL DEFAULT 'rss',
  title TEXT NOT NULL,
  description TEXT,
  category TEXT NOT NULL DEFAULT 'Other',
  location TEXT,
  company_name TEXT,
  salary_text TEXT,
  external_url TEXT NOT NULL,
  contact_email TEXT,
  contact_phone TEXT,
  posted_at TIMESTAMPTZ,
  imported_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at TIMESTAMPTZ,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_external_jobs_active
  ON public.external_jobs (is_active, imported_at DESC);

CREATE INDEX IF NOT EXISTS idx_external_jobs_category
  ON public.external_jobs (category) WHERE is_active = TRUE;

CREATE INDEX IF NOT EXISTS idx_external_jobs_source
  ON public.external_jobs (source);

CREATE INDEX IF NOT EXISTS idx_external_jobs_posted
  ON public.external_jobs (posted_at DESC NULLS LAST) WHERE is_active = TRUE;

-- ── Import rotation state (one row — avoids hammering APIs each cron run) ───

CREATE TABLE IF NOT EXISTS public.external_import_state (
  id INT PRIMARY KEY DEFAULT 1 CHECK (id = 1),
  rss_source_index INT NOT NULL DEFAULT 0,
  serpapi_query_index INT NOT NULL DEFAULT 0,
  last_serpapi_at TIMESTAMPTZ,
  last_run_at TIMESTAMPTZ,
  last_run_summary JSONB NOT NULL DEFAULT '{}'::jsonb,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO public.external_import_state (id)
VALUES (1)
ON CONFLICT (id) DO NOTHING;

-- ── RLS ─────────────────────────────────────────────────────────────────────

ALTER TABLE public.external_jobs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS external_jobs_select_authenticated ON public.external_jobs;
CREATE POLICY external_jobs_select_authenticated
  ON public.external_jobs FOR SELECT
  TO authenticated
  USING (
    is_active = TRUE
    AND (expires_at IS NULL OR expires_at > NOW())
  );

-- Edge function uses service_role (bypasses RLS for writes).

ALTER TABLE public.external_import_state ENABLE ROW LEVEL SECURITY;
-- No policies — only service_role reads/writes import state.

-- ── Triggers & maintenance ──────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.touch_external_jobs_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_external_jobs_updated_at ON public.external_jobs;
CREATE TRIGGER trg_external_jobs_updated_at
  BEFORE UPDATE ON public.external_jobs
  FOR EACH ROW EXECUTE FUNCTION public.touch_external_jobs_updated_at();

CREATE OR REPLACE FUNCTION public.deactivate_stale_external_jobs()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count INTEGER;
BEGIN
  UPDATE external_jobs
  SET is_active = FALSE
  WHERE is_active = TRUE
    AND (
      (expires_at IS NOT NULL AND expires_at < NOW())
      OR imported_at < NOW() - INTERVAL '45 days'
    );
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

GRANT EXECUTE ON FUNCTION public.deactivate_stale_external_jobs() TO service_role;

COMMENT ON TABLE public.external_jobs IS
  'Web jobs imported automatically from external boards. Users apply via external_url.';

COMMENT ON TABLE public.external_import_state IS
  'Round-robin cursor for import-external-jobs edge function (rate-limit friendly).';
