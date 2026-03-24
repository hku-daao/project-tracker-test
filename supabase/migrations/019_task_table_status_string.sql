-- Singular `task` table: replace int `active` (0/1) with text `status`.

ALTER TABLE public.task
  ADD COLUMN IF NOT EXISTS status text;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'task'
      AND column_name = 'active'
  ) THEN
    UPDATE public.task
    SET status = CASE WHEN active = 0 THEN 'deleted' ELSE 'active' END
    WHERE status IS NULL;
  END IF;
END $$;

ALTER TABLE public.task
  ALTER COLUMN status SET DEFAULT 'active';

UPDATE public.task
SET status = 'active'
WHERE status IS NULL OR trim(status) = '';

ALTER TABLE public.task
  ALTER COLUMN status SET NOT NULL;

ALTER TABLE public.task
  DROP COLUMN IF EXISTS active;

ALTER TABLE public.task
  DROP CONSTRAINT IF EXISTS task_status_check;

ALTER TABLE public.task
  ADD CONSTRAINT task_status_check CHECK (status IN ('active', 'deleted'));

COMMENT ON COLUMN public.task.status IS 'active = row in use; deleted = soft-deleted / inactive (replaces legacy active 0/1).';
