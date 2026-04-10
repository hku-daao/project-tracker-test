-- At most one "due today" email to task creator per HK calendar day per task (independent of assignee due-today emails).
ALTER TABLE public.task
  ADD COLUMN IF NOT EXISTS creator_due_today_reminder_sent_on date;

COMMENT ON COLUMN public.task.creator_due_today_reminder_sent_on IS
  'HK calendar date when the creator due-today reminder email was last sent for this task.';
