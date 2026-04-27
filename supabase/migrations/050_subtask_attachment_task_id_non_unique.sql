-- Multiple subtask_attachment rows for the same subtask share the same denormalized
-- task_id (042). If subtask_attachment_task_id_idx was created UNIQUE by mistake,
-- the second attachment fails with:
-- duplicate key value violates unique constraint "subtask_attachment_task_id_idx" (23505).

DROP INDEX IF EXISTS public.subtask_attachment_task_id_idx;

CREATE INDEX IF NOT EXISTS subtask_attachment_task_id_idx ON public.subtask_attachment (task_id);
