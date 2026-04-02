-- One-shot urgent reminder (80% window) per task; set true after emails are sent.
ALTER TABLE public.task
  ADD COLUMN IF NOT EXISTS urgent_reminder_sent boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.task.urgent_reminder_sent IS
  'When true, the 80% urgent reminder email has been sent for this task.';
