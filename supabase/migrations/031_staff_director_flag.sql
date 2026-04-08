-- App permission: task creator or staff.director may set task/comment to Deleted in UI.
ALTER TABLE public.staff
  ADD COLUMN IF NOT EXISTS director boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.staff.director IS
  'When true, user may set task status or comment status to Deleted (with task creator).';
