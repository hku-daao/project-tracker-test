-- Allow Flutter web (anon) to record and read deleted-task audit
ALTER TABLE deleted_tasks ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "anon_select_deleted_tasks" ON deleted_tasks;
CREATE POLICY "anon_select_deleted_tasks" ON deleted_tasks FOR SELECT TO anon USING (true);

DROP POLICY IF EXISTS "anon_insert_deleted_tasks" ON deleted_tasks;
CREATE POLICY "anon_insert_deleted_tasks" ON deleted_tasks FOR INSERT TO anon WITH CHECK (true);

-- Remove task from DB when user deletes in app (cascades to task_assignees, task_milestones if FKs exist)
DROP POLICY IF EXISTS "anon_delete_tasks" ON tasks;
CREATE POLICY "anon_delete_tasks" ON tasks FOR DELETE TO anon USING (true);
