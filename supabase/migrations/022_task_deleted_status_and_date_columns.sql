-- Singular `task`: status value Delete → Deleted; `start_date` / `due_date` as `date`.
-- Run in Supabase SQL Editor or via CLI after backup.
-- Adjust any CHECK constraint on `task.status` in your project to allow `Deleted` if needed.

BEGIN;

UPDATE public.task
SET status = 'Deleted'
WHERE lower(trim(status)) = 'delete';

-- Calendar date in Asia/Hong_Kong from existing timestamptz values.
ALTER TABLE public.task
  ALTER COLUMN start_date TYPE date USING (
    CASE
      WHEN start_date IS NULL THEN NULL
      ELSE (start_date AT TIME ZONE 'Asia/Hong_Kong')::date
    END
  ),
  ALTER COLUMN due_date TYPE date USING (
    CASE
      WHEN due_date IS NULL THEN NULL
      ELSE (due_date AT TIME ZONE 'Asia/Hong_Kong')::date
    END
  );

COMMIT;
