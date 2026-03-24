-- New `comment` table (quoted name: "comment").
-- `task_id` matches `public.task.id` (uuid). Adjust FK if your `task.id` type differs.
-- `create_by` / `update_by` are free-form text (e.g. staff uuid or app id).
-- Add RLS policies and grants for your security model.

CREATE TABLE IF NOT EXISTS public."comment" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  task_id uuid NOT NULL REFERENCES public.task (id) ON DELETE CASCADE,
  description text NOT NULL DEFAULT '',
  status text NOT NULL DEFAULT '',
  create_by text,
  create_date date,
  update_by text,
  update_date date
);

CREATE INDEX IF NOT EXISTS comment_task_id_idx ON public."comment" (task_id);

COMMENT ON TABLE public."comment" IS 'Task-linked comments (app-managed; not legacy task_comments).';
