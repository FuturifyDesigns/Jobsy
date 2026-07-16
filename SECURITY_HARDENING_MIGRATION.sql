-- ============================================================================
-- JOBSY SECURITY HARDENING
-- Run in Supabase SQL editor (safe to re-run).
--
-- • Secure create_profile_for_user RPC (auth.uid() must match)
-- • Profiles: users can only insert/update their own row via RLS
-- ============================================================================

-- Return type changed (e.g. void → uuid); must drop before replace.
DROP FUNCTION IF EXISTS create_profile_for_user(UUID, TEXT, TEXT, TEXT);

CREATE OR REPLACE FUNCTION create_profile_for_user(
  user_id UUID,
  user_email TEXT,
  user_full_name TEXT,
  user_type TEXT DEFAULT 'worker'
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL OR auth.uid() <> user_id THEN
    RAISE EXCEPTION 'Unauthorized profile creation';
  END IF;

  IF user_type NOT IN ('worker', 'employer') THEN
    RAISE EXCEPTION 'Invalid user_type';
  END IF;

  IF user_email IS NULL OR LENGTH(TRIM(user_email)) = 0 THEN
    RAISE EXCEPTION 'Email is required';
  END IF;

  INSERT INTO profiles (
    id,
    email,
    full_name,
    user_type,
    is_profile_complete
  )
  VALUES (
    user_id,
    LOWER(TRIM(user_email)),
    COALESCE(NULLIF(TRIM(user_full_name), ''), 'User'),
    user_type,
    false
  )
  ON CONFLICT (id) DO NOTHING;

  RETURN user_id;
END;
$$;

REVOKE ALL ON FUNCTION create_profile_for_user(UUID, TEXT, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION create_profile_for_user(UUID, TEXT, TEXT, TEXT) TO authenticated;

ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Profiles are viewable by authenticated users" ON profiles;
CREATE POLICY "Profiles are viewable by authenticated users"
  ON profiles FOR SELECT
  TO authenticated
  USING (true);

DROP POLICY IF EXISTS "Users can insert own profile" ON profiles;
CREATE POLICY "Users can insert own profile"
  ON profiles FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = id);

DROP POLICY IF EXISTS "Users can update own profile" ON profiles;
CREATE POLICY "Users can update own profile"
  ON profiles FOR UPDATE
  TO authenticated
  USING (auth.uid() = id)
  WITH CHECK (auth.uid() = id);

DROP POLICY IF EXISTS "Users can delete own profile" ON profiles;
