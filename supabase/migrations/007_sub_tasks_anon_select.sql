-- Fix: sub-tasks saved to DB but disappear after refresh on web.
-- Cause: RLS on sub_tasks had INSERT but no SELECT for anon (e.g. only migration 004 was run).
DROP POLICY IF EXISTS "anon_read_sub_tasks" ON sub_tasks;
CREATE POLICY "anon_read_sub_tasks" ON sub_tasks FOR SELECT TO anon USING (true);
