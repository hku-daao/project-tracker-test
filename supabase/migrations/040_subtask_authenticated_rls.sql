-- RLS for sub-task tables: allow both `anon` and `authenticated`.
--
-- This app signs in with Firebase only and initializes Supabase with the anon key
-- without a Supabase Auth session. PostgREST then uses role `anon`, not
-- `authenticated`. Policies only for `authenticated` do not apply and inserts
-- fail with 42501.
--
-- `authenticated` is included for consistency (e.g. Supabase Auth or custom JWT later).

-- --- anon (required for current Flutter + Firebase setup) --------------------

DROP POLICY IF EXISTS "anon_all_subtask" ON public.subtask;
CREATE POLICY "anon_all_subtask"
  ON public.subtask
  FOR ALL
  TO anon
  USING (true)
  WITH CHECK (true);

DROP POLICY IF EXISTS "anon_all_subtask_attachment" ON public.subtask_attachment;
CREATE POLICY "anon_all_subtask_attachment"
  ON public.subtask_attachment
  FOR ALL
  TO anon
  USING (true)
  WITH CHECK (true);

DROP POLICY IF EXISTS "anon_all_subtask_comment" ON public.subtask_comment;
CREATE POLICY "anon_all_subtask_comment"
  ON public.subtask_comment
  FOR ALL
  TO anon
  USING (true)
  WITH CHECK (true);

-- --- authenticated -----------------------------------------------------------

DROP POLICY IF EXISTS "authenticated_all_subtask" ON public.subtask;
CREATE POLICY "authenticated_all_subtask"
  ON public.subtask
  FOR ALL
  TO authenticated
  USING (true)
  WITH CHECK (true);

DROP POLICY IF EXISTS "authenticated_all_subtask_attachment" ON public.subtask_attachment;
CREATE POLICY "authenticated_all_subtask_attachment"
  ON public.subtask_attachment
  FOR ALL
  TO authenticated
  USING (true)
  WITH CHECK (true);

DROP POLICY IF EXISTS "authenticated_all_subtask_comment" ON public.subtask_comment;
CREATE POLICY "authenticated_all_subtask_comment"
  ON public.subtask_comment
  FOR ALL
  TO authenticated
  USING (true)
  WITH CHECK (true);
