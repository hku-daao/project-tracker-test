-- Stored overdue calendar fields (HK day vs due_date) for filtering and list cards.
-- Recomputed on INSERT/UPDATE; schedule public.refresh_all_overdue_fields() daily (e.g. pg_cron)
-- so rows with unchanged due_date still get correct overdue after calendar rolls.

-- --- task ------------------------------------------------------------------
ALTER TABLE public.task
  ADD COLUMN IF NOT EXISTS overdue_day integer NOT NULL DEFAULT 0;
ALTER TABLE public.task
  ADD COLUMN IF NOT EXISTS overdue text NOT NULL DEFAULT 'No';

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'task_overdue_value_check'
  ) THEN
    ALTER TABLE public.task
      ADD CONSTRAINT task_overdue_value_check
      CHECK (overdue = ANY (ARRAY['Yes'::text, 'No'::text]));
  END IF;
END $$;

COMMENT ON COLUMN public.task.overdue_day IS
  'Non-negative HK calendar days past due when status is not complete and due_date is before today (Asia/Hong_Kong).';
COMMENT ON COLUMN public.task.overdue IS
  'Yes if overdue_day > 0, else No.';

CREATE OR REPLACE FUNCTION public._task_set_overdue_fields()
RETURNS trigger
LANGUAGE plpgsql
AS $fn$
DECLARE
  hk_today date := (current_timestamp AT TIME ZONE 'Asia/Hong_Kong')::date;
  st        text := lower(trim(coalesce(NEW.status, '')));
  d         date := NEW.due_date;
BEGIN
  -- Completed, deleted, or no due: not overdue
  IF st = ANY (ARRAY['completed', 'complete', 'deleted', 'delete'])
     OR d IS NULL THEN
    NEW.overdue_day := 0;
    NEW.overdue := 'No';
  ELSIF d < hk_today THEN
    NEW.overdue_day := GREATEST(0, (hk_today - d));
    IF NEW.overdue_day > 0 THEN
      NEW.overdue := 'Yes';
    ELSE
      NEW.overdue := 'No';
    END IF;
  ELSE
    NEW.overdue_day := 0;
    NEW.overdue := 'No';
  END IF;
  RETURN NEW;
END;
$fn$;

DROP TRIGGER IF EXISTS task_set_overdue_trg ON public.task;
CREATE TRIGGER task_set_overdue_trg
  BEFORE INSERT OR UPDATE
  ON public.task
  FOR EACH ROW
  EXECUTE PROCEDURE public._task_set_overdue_fields();

-- Backfill
UPDATE public.task t SET id = t.id;

-- --- subtask ---------------------------------------------------------------
ALTER TABLE public.subtask
  ADD COLUMN IF NOT EXISTS overdue_day integer NOT NULL DEFAULT 0;
ALTER TABLE public.subtask
  ADD COLUMN IF NOT EXISTS overdue text NOT NULL DEFAULT 'No';

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'subtask_overdue_value_check'
  ) THEN
    ALTER TABLE public.subtask
      ADD CONSTRAINT subtask_overdue_value_check
      CHECK (overdue = ANY (ARRAY['Yes'::text, 'No'::text]));
  END IF;
END $$;

COMMENT ON COLUMN public.subtask.overdue_day IS
  'Non-negative HK calendar days past subtask.due when status is not complete and not deleted (Asia/Hong_Kong).';
COMMENT ON COLUMN public.subtask.overdue IS
  'Yes if overdue_day > 0, else No.';

CREATE OR REPLACE FUNCTION public._subtask_set_overdue_fields()
RETURNS trigger
LANGUAGE plpgsql
AS $fn$
DECLARE
  hk_today date := (current_timestamp AT TIME ZONE 'Asia/Hong_Kong')::date;
  st        text := lower(trim(coalesce(NEW.status, '')));
  d         date := NEW.due_date;
BEGIN
  IF st = ANY (ARRAY['completed', 'complete', 'deleted', 'delete'])
     OR d IS NULL THEN
    NEW.overdue_day := 0;
    NEW.overdue := 'No';
  ELSIF d < hk_today THEN
    NEW.overdue_day := GREATEST(0, (hk_today - d));
    IF NEW.overdue_day > 0 THEN
      NEW.overdue := 'Yes';
    ELSE
      NEW.overdue := 'No';
    END IF;
  ELSE
    NEW.overdue_day := 0;
    NEW.overdue := 'No';
  END IF;
  RETURN NEW;
END;
$fn$;

DROP TRIGGER IF EXISTS subtask_set_overdue_trg ON public.subtask;
CREATE TRIGGER subtask_set_overdue_trg
  BEFORE INSERT OR UPDATE
  ON public.subtask
  FOR EACH ROW
  EXECUTE PROCEDURE public._subtask_set_overdue_fields();

UPDATE public.subtask s SET id = s.id;

-- --- Nightly (or on-demand) refresh: rows that had no file write still age -------
CREATE OR REPLACE FUNCTION public.refresh_all_overdue_fields()
RETURNS void
LANGUAGE plpgsql
AS $fn$
BEGIN
  UPDATE public.task t SET id = t.id;
  UPDATE public.subtask s SET id = s.id;
END;
$fn$;

COMMENT ON FUNCTION public.refresh_all_overdue_fields() IS
  'Recomputes task/subtask overdue_day and overdue for all rows (e.g. daily at HK midnight).';
