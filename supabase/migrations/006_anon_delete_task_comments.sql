-- Let anon remove task comments when a task is deleted (audit flow)
DROP POLICY IF EXISTS "anon_delete_task_comments" ON comments;
CREATE POLICY "anon_delete_task_comments" ON comments
  FOR DELETE TO anon
  USING (entity_type = 'task');
