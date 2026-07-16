-- ============================================================================
-- JOBSY ROLE SWITCH (base + security)
-- Run BOTH sections in Supabase SQL editor (safe to re-run).
--
-- 1) ROLE_SWITCH_MIGRATION.sql        — allows user_type to change
-- 2) ROLE_SWITCH_SECURITY_MIGRATION.sql — RPC, anti-exploit, RLS hardening
-- ============================================================================

-- Allow signed-in users to switch between worker and employer roles.
CREATE OR REPLACE FUNCTION prevent_user_type_change()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.user_type NOT IN ('worker', 'employer') THEN
      RAISE EXCEPTION 'Invalid user_type: %. Must be worker or employer.', NEW.user_type;
    END IF;
    RETURN NEW;
  END IF;

  IF NEW.user_type IS DISTINCT FROM OLD.user_type THEN
    IF NEW.user_type NOT IN ('worker', 'employer') THEN
      RAISE EXCEPTION 'Invalid user_type: %. Must be worker or employer.', NEW.user_type;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

-- ⚠️  After this file, also run: ROLE_SWITCH_SECURITY_MIGRATION.sql
--     That file adds RPC validation, self-dealing blocks, and RLS hardening.
