-- Workflow: PIC submits → submission = 'Submitted'; creator Accept/Return → 'Accepted'/'Returned'.
-- Optional hyperlink stored in attachment.content (one row per task).

ALTER TABLE public.task
  ADD COLUMN IF NOT EXISTS submission text;

COMMENT ON COLUMN public.task.submission IS 'PIC/creator workflow: Submitted, Accepted, Returned (or null).';

CREATE TABLE IF NOT EXISTS public.attachment (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  task_id uuid NOT NULL REFERENCES public.task (id) ON DELETE CASCADE,
  content text,
  created_at timestamptz DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS attachment_task_id_uidx ON public.attachment (task_id);

COMMENT ON TABLE public.attachment IS 'Task attachments; submission link URL in content.';
COMMENT ON COLUMN public.attachment.content IS 'Hyperlink URL for PIC submission (optional if comment provided).';

ALTER TABLE public.attachment ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "anon_select_attachment" ON public.attachment;
CREATE POLICY "anon_select_attachment" ON public.attachment
  FOR SELECT TO anon USING (true);

DROP POLICY IF EXISTS "anon_insert_attachment" ON public.attachment;
CREATE POLICY "anon_insert_attachment" ON public.attachment
  FOR INSERT TO anon WITH CHECK (true);

DROP POLICY IF EXISTS "anon_update_attachment" ON public.attachment;
CREATE POLICY "anon_update_attachment" ON public.attachment
  FOR UPDATE TO anon USING (true);

DROP POLICY IF EXISTS "anon_delete_attachment" ON public.attachment;
CREATE POLICY "anon_delete_attachment" ON public.attachment
  FOR DELETE TO anon USING (true);
