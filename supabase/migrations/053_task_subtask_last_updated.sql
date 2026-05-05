-- Denormalized `last_updated` on `task` / `subtask` for list sort + “Last updated” UI.
-- Value = greatest of row `update_date` and max comment activity:
--   comment: COALESCE(update_date, create_date) per row on public."comment"
--   subtask_comment: COALESCE(update_date, create_date) per row on subtask_comment

ALTER TABLE public.task
  ADD COLUMN IF NOT EXISTS last_updated timestamptz;

ALTER TABLE public.subtask
  ADD COLUMN IF NOT EXISTS last_updated timestamptz;

COMMENT ON COLUMN public.task.last_updated IS
  'Max of task.update_date and latest task comment instant; refreshed by triggers.';
COMMENT ON COLUMN public.subtask.last_updated IS
  'Max of subtask.update_date and latest subtask_comment instant; refreshed by triggers.';

-- --- task -------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.task_refresh_last_updated(p_task_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_upd       timestamptz;
  v_comm_max  timestamptz;
  v_result    timestamptz;
BEGIN
  SELECT t.update_date INTO v_upd FROM public.task t WHERE t.id = p_task_id;
  SELECT MAX(COALESCE(c.update_date, c.create_date)) INTO v_comm_max
  FROM public."comment" c
  WHERE c.task_id = p_task_id;

  IF v_upd IS NULL AND v_comm_max IS NULL THEN
    UPDATE public.task SET last_updated = NULL WHERE id = p_task_id;
    RETURN;
  END IF;
  IF v_upd IS NULL THEN
    v_result := v_comm_max;
  ELSIF v_comm_max IS NULL THEN
    v_result := v_upd;
  ELSE
    v_result := GREATEST(v_upd, v_comm_max);
  END IF;
  UPDATE public.task SET last_updated = v_result WHERE id = p_task_id;
END;
$fn$;

CREATE OR REPLACE FUNCTION public._trg_task_after_write_refresh_last_updated()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
BEGIN
  PERFORM public.task_refresh_last_updated(NEW.id);
  RETURN NEW;
END;
$fn$;

DROP TRIGGER IF EXISTS task_refresh_last_updated_trg ON public.task;
CREATE TRIGGER task_refresh_last_updated_trg
  AFTER INSERT OR UPDATE OF update_date ON public.task
  FOR EACH ROW
  EXECUTE PROCEDURE public._trg_task_after_write_refresh_last_updated();

CREATE OR REPLACE FUNCTION public._trg_comment_touch_task_last_updated()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  tid uuid;
BEGIN
  IF TG_OP = 'DELETE' THEN
    PERFORM public.task_refresh_last_updated(OLD.task_id);
    RETURN OLD;
  END IF;
  PERFORM public.task_refresh_last_updated(NEW.task_id);
  IF TG_OP = 'UPDATE' AND OLD.task_id IS DISTINCT FROM NEW.task_id THEN
    PERFORM public.task_refresh_last_updated(OLD.task_id);
  END IF;
  RETURN NEW;
END;
$fn$;

DROP TRIGGER IF EXISTS comment_touch_task_last_updated_trg ON public."comment";
CREATE TRIGGER comment_touch_task_last_updated_trg
  AFTER INSERT OR UPDATE OR DELETE ON public."comment"
  FOR EACH ROW
  EXECUTE PROCEDURE public._trg_comment_touch_task_last_updated();

-- --- subtask ----------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.subtask_refresh_last_updated(p_subtask_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_upd       timestamptz;
  v_comm_max  timestamptz;
  v_result    timestamptz;
BEGIN
  SELECT s.update_date INTO v_upd FROM public.subtask s WHERE s.id = p_subtask_id;
  SELECT MAX(COALESCE(sc.update_date, sc.create_date)) INTO v_comm_max
  FROM public.subtask_comment sc
  WHERE sc.subtask_id = p_subtask_id;

  IF v_upd IS NULL AND v_comm_max IS NULL THEN
    UPDATE public.subtask SET last_updated = NULL WHERE id = p_subtask_id;
    RETURN;
  END IF;
  IF v_upd IS NULL THEN
    v_result := v_comm_max;
  ELSIF v_comm_max IS NULL THEN
    v_result := v_upd;
  ELSE
    v_result := GREATEST(v_upd, v_comm_max);
  END IF;
  UPDATE public.subtask SET last_updated = v_result WHERE id = p_subtask_id;
END;
$fn$;

CREATE OR REPLACE FUNCTION public._trg_subtask_after_write_refresh_last_updated()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
BEGIN
  PERFORM public.subtask_refresh_last_updated(NEW.id);
  RETURN NEW;
END;
$fn$;

DROP TRIGGER IF EXISTS subtask_refresh_last_updated_trg ON public.subtask;
CREATE TRIGGER subtask_refresh_last_updated_trg
  AFTER INSERT OR UPDATE OF update_date ON public.subtask
  FOR EACH ROW
  EXECUTE PROCEDURE public._trg_subtask_after_write_refresh_last_updated();

CREATE OR REPLACE FUNCTION public._trg_subtask_comment_touch_last_updated()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  sid uuid;
BEGIN
  IF TG_OP = 'DELETE' THEN
    PERFORM public.subtask_refresh_last_updated(OLD.subtask_id);
    RETURN OLD;
  END IF;
  PERFORM public.subtask_refresh_last_updated(NEW.subtask_id);
  IF TG_OP = 'UPDATE' AND OLD.subtask_id IS DISTINCT FROM NEW.subtask_id THEN
    PERFORM public.subtask_refresh_last_updated(OLD.subtask_id);
  END IF;
  RETURN NEW;
END;
$fn$;

DROP TRIGGER IF EXISTS subtask_comment_touch_last_updated_trg ON public.subtask_comment;
CREATE TRIGGER subtask_comment_touch_last_updated_trg
  AFTER INSERT OR UPDATE OR DELETE ON public.subtask_comment
  FOR EACH ROW
  EXECUTE PROCEDURE public._trg_subtask_comment_touch_last_updated();

-- --- Backfill ---------------------------------------------------------------

DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN SELECT id FROM public.task LOOP
    PERFORM public.task_refresh_last_updated(r.id);
  END LOOP;
  FOR r IN SELECT id FROM public.subtask LOOP
    PERFORM public.subtask_refresh_last_updated(r.id);
  END LOOP;
END $$;
