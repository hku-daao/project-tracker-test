-- Milestones (sub-tasks) attached to low-level tasks
CREATE TABLE IF NOT EXISTS task_milestones (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  task_id uuid NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
  label text NOT NULL,
  progress_percent smallint NOT NULL DEFAULT 0,
  is_completed boolean NOT NULL DEFAULT false,
  completed_at timestamptz
);

CREATE INDEX IF NOT EXISTS idx_task_milestones_task ON task_milestones(task_id);

ALTER TABLE task_milestones ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "anon_read_task_milestones" ON task_milestones;
CREATE POLICY "anon_read_task_milestones" ON task_milestones FOR SELECT TO anon USING (true);
DROP POLICY IF EXISTS "anon_insert_task_milestones" ON task_milestones;
CREATE POLICY "anon_insert_task_milestones" ON task_milestones FOR INSERT TO anon WITH CHECK (true);
DROP POLICY IF EXISTS "anon_update_task_milestones" ON task_milestones;
CREATE POLICY "anon_update_task_milestones" ON task_milestones FOR UPDATE TO anon USING (true);

ALTER TABLE tasks ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "anon_read_tasks" ON tasks;
CREATE POLICY "anon_read_tasks" ON tasks FOR SELECT TO anon USING (true);
DROP POLICY IF EXISTS "anon_insert_tasks" ON tasks;
CREATE POLICY "anon_insert_tasks" ON tasks FOR INSERT TO anon WITH CHECK (true);
DROP POLICY IF EXISTS "anon_update_tasks" ON tasks;
CREATE POLICY "anon_update_tasks" ON tasks FOR UPDATE TO anon USING (true);

ALTER TABLE task_assignees ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "anon_read_task_assignees" ON task_assignees;
CREATE POLICY "anon_read_task_assignees" ON task_assignees FOR SELECT TO anon USING (true);
DROP POLICY IF EXISTS "anon_insert_task_assignees" ON task_assignees;
CREATE POLICY "anon_insert_task_assignees" ON task_assignees FOR INSERT TO anon WITH CHECK (true);

-- Comments: INSERT/UPDATE if not already in 003
DROP POLICY IF EXISTS "anon_insert_comments" ON comments;
CREATE POLICY "anon_insert_comments" ON comments FOR INSERT TO anon WITH CHECK (true);

-- Sub-tasks on initiatives: read + insert + update
-- IMPORTANT: anon SELECT is required or sub-tasks vanish after refresh (INSERT works, load returns 0 rows).
ALTER TABLE sub_tasks ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "anon_read_sub_tasks" ON sub_tasks;
CREATE POLICY "anon_read_sub_tasks" ON sub_tasks FOR SELECT TO anon USING (true);
DROP POLICY IF EXISTS "anon_insert_sub_tasks" ON sub_tasks;
CREATE POLICY "anon_insert_sub_tasks" ON sub_tasks FOR INSERT TO anon WITH CHECK (true);
DROP POLICY IF EXISTS "anon_update_sub_tasks" ON sub_tasks;
CREATE POLICY "anon_update_sub_tasks" ON sub_tasks FOR UPDATE TO anon USING (true);
