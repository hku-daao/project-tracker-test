-- Fix 42501 on INSERT into public.subtask_attachment (RLS / privileges).
--
-- Typical causes: missing permissive policy for role `anon` (Flutter uses the anon key),
-- or policies dropped when tightening security. This migration is idempotent.

ALTER TABLE public.subtask_attachment ENABLE ROW LEVEL SECURITY;

-- Denormalized parent task id (safe if 042 already applied).
ALTER TABLE public.subtask_attachment
  ADD COLUMN IF NOT EXISTS task_id uuid REFERENCES public.task (id) ON DELETE CASCADE;

UPDATE public.subtask_attachment sa
SET task_id = s.task_id
FROM public.subtask s
WHERE sa.subtask_id = s.id
  AND (sa.task_id IS NULL OR sa.task_id IS DISTINCT FROM s.task_id);

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.subtask_attachment TO anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.subtask_attachment TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.subtask_attachment TO service_role;

DROP POLICY IF EXISTS "anon_all_subtask_attachment" ON public.subtask_attachment;
CREATE POLICY "anon_all_subtask_attachment"
  ON public.subtask_attachment
  FOR ALL
  TO anon
  USING (true)
  WITH CHECK (true);

DROP POLICY IF EXISTS "authenticated_all_subtask_attachment" ON public.subtask_attachment;
CREATE POLICY "authenticated_all_subtask_attachment"
  ON public.subtask_attachment
  FOR ALL
  TO authenticated
  USING (true)
  WITH CHECK (true);
