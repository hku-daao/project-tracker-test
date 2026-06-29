-- Manual archive marker for completed tasks.
-- Deleted projects/tasks/subtasks are archived by their existing Deleted status.

alter table public.task
  add column if not exists archived_at timestamp with time zone,
  add column if not exists archived_by uuid;

create index if not exists idx_task_archived_at
  on public.task (archived_at)
  where archived_at is not null;

