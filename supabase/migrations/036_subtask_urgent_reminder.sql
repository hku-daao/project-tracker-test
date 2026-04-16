-- Creator urgent (80%) sub-task emails: daily HK dedup + flag reset after due (HK).

ALTER TABLE public.subtask
  ADD COLUMN IF NOT EXISTS urgent_reminder_sent boolean NOT NULL DEFAULT false;

ALTER TABLE public.subtask
  ADD COLUMN IF NOT EXISTS creator_urgent_reminder_last_sent_on date;

COMMENT ON COLUMN public.subtask.urgent_reminder_sent IS
  'Set true after a successful creator 80% urgent email; reset false when HK calendar is past due_date.';

COMMENT ON COLUMN public.subtask.creator_urgent_reminder_last_sent_on IS
  'HK calendar date of last creator 80% urgent email (at most one per HK day while in window before due).';
