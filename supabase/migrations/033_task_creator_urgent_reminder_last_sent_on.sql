-- At most one creator 80% urgent reminder email per HK calendar day per task (independent of assignee urgent_reminder_last_sent_on).
ALTER TABLE public.task
  ADD COLUMN IF NOT EXISTS creator_urgent_reminder_last_sent_on date;

COMMENT ON COLUMN public.task.creator_urgent_reminder_last_sent_on IS
  'HK calendar date when the creator urgent (80% window) reminder email was last sent for this task.';
