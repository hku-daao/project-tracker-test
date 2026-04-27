-- If migration 036/043 never ran on this project, public.attachment still has
-- UNIQUE (task_id) from 034, and saving more than one attachment fails with:
-- duplicate key value violates unique constraint "attachment_task_id_uidx" (23505).

DROP INDEX IF EXISTS public.attachment_task_id_uidx;

CREATE INDEX IF NOT EXISTS attachment_task_id_idx ON public.attachment (task_id);

DROP INDEX IF EXISTS public.subtask_attachment_subtask_uidx;

CREATE INDEX IF NOT EXISTS subtask_attachment_subtask_id_idx ON public.subtask_attachment (subtask_id);
