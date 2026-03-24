-- Flutter web (anon key): singular `task` must allow SELECT or rows vanish after refresh
-- (same pattern as 007_sub_tasks_anon_select.sql for sub_tasks).

ALTER TABLE public.task ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "anon_select_task_singular" ON public.task;
CREATE POLICY "anon_select_task_singular" ON public.task
  FOR SELECT TO anon USING (true);

DROP POLICY IF EXISTS "anon_insert_task_singular" ON public.task;
CREATE POLICY "anon_insert_task_singular" ON public.task
  FOR INSERT TO anon WITH CHECK (true);

DROP POLICY IF EXISTS "anon_update_task_singular" ON public.task;
CREATE POLICY "anon_update_task_singular" ON public.task
  FOR UPDATE TO anon USING (true);
