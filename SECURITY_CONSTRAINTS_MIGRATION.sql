-- ============================================================================
-- JOBSY SECURITY CONSTRAINTS MIGRATION
-- Addresses: SEC-04 (content enforcement), SEC-09 (user_type guard),
--            SEC-10 (message length), SEC-11 (budget validation),
--            SEC-08 (storage policies documented as SQL comments)
-- Safe to run multiple times (uses IF NOT EXISTS / OR REPLACE patterns).
-- ============================================================================

-- ============================================================================
-- 1. LOCK user_type AFTER CREATION (SEC-09)
--    Prevent clients from changing their role post-signup.
-- ============================================================================

CREATE OR REPLACE FUNCTION prevent_user_type_change()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  -- Validate allowed values on insert
  IF TG_OP = 'INSERT' THEN
    IF NEW.user_type NOT IN ('worker', 'employer') THEN
      RAISE EXCEPTION 'Invalid user_type: %. Must be worker or employer.', NEW.user_type;
    END IF;
    RETURN NEW;
  END IF;

  -- Block changes to user_type after the row exists
  IF NEW.user_type IS DISTINCT FROM OLD.user_type THEN
    RAISE EXCEPTION 'user_type cannot be changed after account creation.';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_prevent_user_type_change ON profiles;
CREATE TRIGGER trg_prevent_user_type_change
  BEFORE INSERT OR UPDATE ON profiles
  FOR EACH ROW EXECUTE FUNCTION prevent_user_type_change();


-- ============================================================================
-- 2. MESSAGE LENGTH CONSTRAINT (SEC-10)
--    Prevent excessively large messages from bloating the database and
--    degrading realtime subscriptions.
-- ============================================================================

ALTER TABLE messages
  DROP CONSTRAINT IF EXISTS chk_message_length;

ALTER TABLE messages
  ADD CONSTRAINT chk_message_length
    CHECK (char_length(message) BETWEEN 1 AND 4000);


-- ============================================================================
-- 3. BUDGET AMOUNT CONSTRAINT (SEC-11)
--    Enforce sensible budget bounds server-side so the client cannot be
--    bypassed.
-- ============================================================================

ALTER TABLE jobs
  DROP CONSTRAINT IF EXISTS chk_budget_amount;

ALTER TABLE jobs
  ADD CONSTRAINT chk_budget_amount
    CHECK (budget_amount > 0 AND budget_amount <= 1000000);


-- ============================================================================
-- 4. SERVER-SIDE CONTENT POLICY TRIGGER (SEC-04)
--    Block obviously abusive or empty job content at the database level.
--    This is a backstop — it does not replace the client-side profanity
--    filter, which provides immediate UX feedback.
-- ============================================================================

CREATE OR REPLACE FUNCTION validate_job_content()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
  bad_words TEXT[] := ARRAY[
    'fuck','shit','bitch','cunt','nigger','nigga','faggot',
    'motherfucker','asshole','msunu','sefebe'
  ];
  w TEXT;
  title_lower TEXT;
  desc_lower  TEXT;
BEGIN
  -- Enforce minimum lengths
  IF char_length(trim(NEW.title)) < 3 THEN
    RAISE EXCEPTION 'Job title is too short (minimum 3 characters).';
  END IF;

  IF char_length(trim(NEW.description)) < 20 THEN
    RAISE EXCEPTION 'Job description is too short (minimum 20 characters).';
  END IF;

  -- Enforce maximum lengths
  IF char_length(NEW.title) > 200 THEN
    RAISE EXCEPTION 'Job title exceeds maximum length of 200 characters.';
  END IF;

  IF char_length(NEW.description) > 5000 THEN
    RAISE EXCEPTION 'Job description exceeds maximum length of 5000 characters.';
  END IF;

  title_lower := lower(NEW.title);
  desc_lower  := lower(NEW.description);

  FOREACH w IN ARRAY bad_words LOOP
    IF title_lower ~ ('\m' || w || '\M') OR desc_lower ~ ('\m' || w || '\M') THEN
      RAISE EXCEPTION 'Job content contains inappropriate language.';
    END IF;
  END LOOP;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validate_job_content ON jobs;
CREATE TRIGGER trg_validate_job_content
  BEFORE INSERT OR UPDATE ON jobs
  FOR EACH ROW EXECUTE FUNCTION validate_job_content();


-- ============================================================================
-- 5. PHONE NUMBER FORMAT CHECK (SEC-07)
--    Accept international E.164 format or local formats starting with digits.
-- ============================================================================

ALTER TABLE profiles
  DROP CONSTRAINT IF EXISTS chk_phone_format;

ALTER TABLE profiles
  ADD CONSTRAINT chk_phone_format
    CHECK (
      phone IS NULL
      OR phone = ''
      OR phone ~ '^\+?[0-9][0-9 \-]{6,18}[0-9]$'
    );


-- ============================================================================
-- 6. STORAGE BUCKET POLICIES (SEC-08)
--    The SQL below uses Supabase's storage schema helpers.
--    Run this after creating the buckets in the dashboard, OR configure
--    bucket policies directly in Dashboard → Storage → Policies.
-- ============================================================================

-- profile-photos bucket: authenticated users may only upload to their own folder
DO $$
BEGIN
  -- Allow authenticated users to INSERT into their own folder
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects'
      AND policyname = 'profile_photos_insert_own'
  ) THEN
    EXECUTE $pol$
      CREATE POLICY "profile_photos_insert_own"
        ON storage.objects FOR INSERT
        TO authenticated
        WITH CHECK (
          bucket_id = 'profile-photos'
          AND (storage.foldername(name))[1] = auth.uid()::text
        );
    $pol$;
  END IF;

  -- Allow authenticated users to SELECT from their own folder
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects'
      AND policyname = 'profile_photos_select_own'
  ) THEN
    EXECUTE $pol$
      CREATE POLICY "profile_photos_select_own"
        ON storage.objects FOR SELECT
        TO authenticated
        USING (
          bucket_id = 'profile-photos'
          AND (storage.foldername(name))[1] = auth.uid()::text
        );
    $pol$;
  END IF;
END;
$$;

-- job-photos bucket: authenticated users may only upload to their own folder
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects'
      AND policyname = 'job_photos_insert_own'
  ) THEN
    EXECUTE $pol$
      CREATE POLICY "job_photos_insert_own"
        ON storage.objects FOR INSERT
        TO authenticated
        WITH CHECK (
          bucket_id = 'job-photos'
          AND (storage.foldername(name))[1] = auth.uid()::text
        );
    $pol$;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects'
      AND policyname = 'job_photos_select_public'
  ) THEN
    EXECUTE $pol$
      CREATE POLICY "job_photos_select_public"
        ON storage.objects FOR SELECT
        USING (bucket_id = 'job-photos');
    $pol$;
  END IF;
END;
$$;

-- ============================================================================
-- NOTE: To enforce MIME-type and file-size limits on buckets,
-- configure these in Dashboard → Storage → [bucket] → Configuration:
--   - Allowed MIME types: image/jpeg, image/png, image/webp, image/gif
--   - Max file size: 5242880  (5 MB)
-- ============================================================================


-- ============================================================================
-- DONE ✅
-- ============================================================================
SELECT 'SECURITY_CONSTRAINTS_MIGRATION complete' AS status;
