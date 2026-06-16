-- Expand project people fields:
-- - assignee_01...assignee_20 store project assignees as staff.id text values
-- - pic_01...pic_20 store project PICs as staff.id text values
-- Existing JSON `project.pic` values are backfilled into pic_01...pic_20, then removed.

ALTER TABLE public.project
  ADD COLUMN IF NOT EXISTS assignee_11 text,
  ADD COLUMN IF NOT EXISTS assignee_12 text,
  ADD COLUMN IF NOT EXISTS assignee_13 text,
  ADD COLUMN IF NOT EXISTS assignee_14 text,
  ADD COLUMN IF NOT EXISTS assignee_15 text,
  ADD COLUMN IF NOT EXISTS assignee_16 text,
  ADD COLUMN IF NOT EXISTS assignee_17 text,
  ADD COLUMN IF NOT EXISTS assignee_18 text,
  ADD COLUMN IF NOT EXISTS assignee_19 text,
  ADD COLUMN IF NOT EXISTS assignee_20 text,
  ADD COLUMN IF NOT EXISTS pic_01 text,
  ADD COLUMN IF NOT EXISTS pic_02 text,
  ADD COLUMN IF NOT EXISTS pic_03 text,
  ADD COLUMN IF NOT EXISTS pic_04 text,
  ADD COLUMN IF NOT EXISTS pic_05 text,
  ADD COLUMN IF NOT EXISTS pic_06 text,
  ADD COLUMN IF NOT EXISTS pic_07 text,
  ADD COLUMN IF NOT EXISTS pic_08 text,
  ADD COLUMN IF NOT EXISTS pic_09 text,
  ADD COLUMN IF NOT EXISTS pic_10 text,
  ADD COLUMN IF NOT EXISTS pic_11 text,
  ADD COLUMN IF NOT EXISTS pic_12 text,
  ADD COLUMN IF NOT EXISTS pic_13 text,
  ADD COLUMN IF NOT EXISTS pic_14 text,
  ADD COLUMN IF NOT EXISTS pic_15 text,
  ADD COLUMN IF NOT EXISTS pic_16 text,
  ADD COLUMN IF NOT EXISTS pic_17 text,
  ADD COLUMN IF NOT EXISTS pic_18 text,
  ADD COLUMN IF NOT EXISTS pic_19 text,
  ADD COLUMN IF NOT EXISTS pic_20 text;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'project'
      AND column_name = 'pic'
  ) THEN
    EXECUTE $sql$
      UPDATE public.project AS p
      SET
        pic_01 = pics.vals[1],
        pic_02 = pics.vals[2],
        pic_03 = pics.vals[3],
        pic_04 = pics.vals[4],
        pic_05 = pics.vals[5],
        pic_06 = pics.vals[6],
        pic_07 = pics.vals[7],
        pic_08 = pics.vals[8],
        pic_09 = pics.vals[9],
        pic_10 = pics.vals[10],
        pic_11 = pics.vals[11],
        pic_12 = pics.vals[12],
        pic_13 = pics.vals[13],
        pic_14 = pics.vals[14],
        pic_15 = pics.vals[15],
        pic_16 = pics.vals[16],
        pic_17 = pics.vals[17],
        pic_18 = pics.vals[18],
        pic_19 = pics.vals[19],
        pic_20 = pics.vals[20]
      FROM (
        SELECT project.id, array_agg(e.value ORDER BY e.ordinality) AS vals
        FROM public.project
        CROSS JOIN LATERAL jsonb_array_elements_text(project.pic) WITH ORDINALITY AS e(value, ordinality)
        GROUP BY project.id
      ) AS pics
      WHERE p.id = pics.id
    $sql$;
  END IF;
END $$;

ALTER TABLE public.project
  DROP COLUMN IF EXISTS pic;

COMMENT ON COLUMN public.project.assignee_01 IS 'Project assignee slot 01 (staff.id text)';
COMMENT ON COLUMN public.project.assignee_20 IS 'Project assignee slot 20 (staff.id text)';
COMMENT ON COLUMN public.project.pic_01 IS 'Project PIC slot 01 (staff.id text; chosen from assignees)';
COMMENT ON COLUMN public.project.pic_20 IS 'Project PIC slot 20 (staff.id text; chosen from assignees)';
