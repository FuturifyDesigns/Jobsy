-- ============================================================
-- REALTIME RLS FIX
-- Supabase Realtime only delivers row updates to clients that
-- have a SELECT RLS policy allowing them to read that row.
-- Without this, the worker's chat screen never receives the
-- job status update when the employer marks it complete —
-- so "Awaiting" never clears.
--
-- Run in Supabase → SQL Editor
-- ============================================================

-- ── jobs table ──────────────────────────────────────────────
-- Authenticated users can read any active or completed job
-- (needed for browse, job details, and realtime status updates)
ALTER TABLE jobs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Jobs are publicly readable" ON jobs;
CREATE POLICY "Jobs are publicly readable"
  ON jobs FOR SELECT
  TO authenticated
  USING (true);

-- Employers can insert their own jobs
DROP POLICY IF EXISTS "Employers can insert jobs" ON jobs;
CREATE POLICY "Employers can insert jobs"
  ON jobs FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = employer_id);

-- Employers can update/delete their own jobs
DROP POLICY IF EXISTS "Employers can update own jobs" ON jobs;
CREATE POLICY "Employers can update own jobs"
  ON jobs FOR UPDATE
  TO authenticated
  USING (auth.uid() = employer_id);

DROP POLICY IF EXISTS "Employers can delete own jobs" ON jobs;
CREATE POLICY "Employers can delete own jobs"
  ON jobs FOR DELETE
  TO authenticated
  USING (auth.uid() = employer_id);


-- ── job_applications table ───────────────────────────────────
-- Workers and employers involved in an application can read it
ALTER TABLE job_applications ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Applications readable by involved parties" ON job_applications;
CREATE POLICY "Applications readable by involved parties"
  ON job_applications FOR SELECT
  TO authenticated
  USING (
    auth.uid() = worker_id
    OR auth.uid() IN (
      SELECT employer_id FROM jobs WHERE id = job_id
    )
  );

-- Workers can insert their own applications
DROP POLICY IF EXISTS "Workers can apply to jobs" ON job_applications;
CREATE POLICY "Workers can apply to jobs"
  ON job_applications FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = worker_id);

-- Workers and employers can update applications they're involved in
DROP POLICY IF EXISTS "Parties can update applications" ON job_applications;
CREATE POLICY "Parties can update applications"
  ON job_applications FOR UPDATE
  TO authenticated
  USING (
    auth.uid() = worker_id
    OR auth.uid() IN (
      SELECT employer_id FROM jobs WHERE id = job_id
    )
  );


-- ── conversations table ──────────────────────────────────────
ALTER TABLE conversations ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Conversations readable by participants" ON conversations;
CREATE POLICY "Conversations readable by participants"
  ON conversations FOR SELECT
  TO authenticated
  USING (
    auth.uid() = employer_id
    OR auth.uid() = worker_id
  );

DROP POLICY IF EXISTS "Participants can insert conversations" ON conversations;
CREATE POLICY "Participants can insert conversations"
  ON conversations FOR INSERT
  TO authenticated
  WITH CHECK (
    auth.uid() = employer_id
    OR auth.uid() = worker_id
  );

DROP POLICY IF EXISTS "Participants can update conversations" ON conversations;
CREATE POLICY "Participants can update conversations"
  ON conversations FOR UPDATE
  TO authenticated
  USING (
    auth.uid() = employer_id
    OR auth.uid() = worker_id
  );


-- ── messages table ───────────────────────────────────────────
ALTER TABLE messages ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Messages readable by conversation participants" ON messages;
CREATE POLICY "Messages readable by conversation participants"
  ON messages FOR SELECT
  TO authenticated
  USING (
    auth.uid() IN (
      SELECT employer_id FROM conversations WHERE id = conversation_id
      UNION
      SELECT worker_id FROM conversations WHERE id = conversation_id
    )
  );

DROP POLICY IF EXISTS "Participants can send messages" ON messages;
CREATE POLICY "Participants can send messages"
  ON messages FOR INSERT
  TO authenticated
  WITH CHECK (
    auth.uid() = sender_id
    AND auth.uid() IN (
      SELECT employer_id FROM conversations WHERE id = conversation_id
      UNION
      SELECT worker_id FROM conversations WHERE id = conversation_id
    )
  );

DROP POLICY IF EXISTS "Participants can update messages" ON messages;
CREATE POLICY "Participants can update messages"
  ON messages FOR UPDATE
  TO authenticated
  USING (
    auth.uid() IN (
      SELECT employer_id FROM conversations WHERE id = conversation_id
      UNION
      SELECT worker_id FROM conversations WHERE id = conversation_id
    )
  );

SELECT 'Realtime RLS fix complete' AS status;
