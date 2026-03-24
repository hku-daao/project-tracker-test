-- Audit columns on singular `task` table.

ALTER TABLE public.task
  ADD COLUMN IF NOT EXISTS create_by text,
  ADD COLUMN IF NOT EXISTS create_date timestamptz NOT NULL DEFAULT now(),
  ADD COLUMN IF NOT EXISTS update_by text,
  ADD COLUMN IF NOT EXISTS update_date timestamptz;

COMMENT ON COLUMN public.task.create_by IS 'Who created the row (e.g. email or user id).';
COMMENT ON COLUMN public.task.create_date IS 'When the row was created.';
COMMENT ON COLUMN public.task.update_by IS 'Who last updated the row.';
COMMENT ON COLUMN public.task.update_date IS 'When the row was last updated (NULL if never updated after insert).';
