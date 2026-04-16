-- Some deployments require denormalized parent task id on attachment rows (FK to public.task).
-- The app sends both subtask_id and task_id on insert.

ALTER TABLE public.subtask_attachment
  ADD COLUMN IF NOT EXISTS task_id uuid REFERENCES public.task (id) ON DELETE CASCADE;

UPDATE public.subtask_attachment sa
SET task_id = s.task_id
FROM public.subtask s
WHERE sa.subtask_id = s.id
  AND (sa.task_id IS NULL OR sa.task_id IS DISTINCT FROM s.task_id);

CREATE INDEX IF NOT EXISTS subtask_attachment_task_id_idx ON public.subtask_attachment (task_id);
