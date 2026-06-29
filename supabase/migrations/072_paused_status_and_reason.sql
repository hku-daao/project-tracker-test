-- Move Paused out of status into a separate pause_status column.

alter table public.project
  add column if not exists pause_status text not null default 'Not Paused';

alter table public.task
  add column if not exists pause_status text not null default 'Not Paused';

alter table public.subtask
  add column if not exists pause_status text not null default 'Not Paused';

update public.project
set pause_status = 'Paused',
    status = 'Not started'
where status = 'Paused';

update public.task
set pause_status = 'Paused',
    status = 'Incomplete'
where status = 'Paused';

update public.subtask
set pause_status = 'Paused',
    status = 'Incomplete'
where status = 'Paused';

alter table public.project
  drop constraint if exists project_status_check;

alter table public.project
  add constraint project_status_check
  check (status in ('Not started', 'In progress', 'Completed', 'Deleted'));

alter table public.project
  drop constraint if exists project_pause_status_check;

alter table public.project
  add constraint project_pause_status_check
  check (pause_status in ('Paused', 'Not Paused'));

alter table public.task
  drop constraint if exists task_status_check;

alter table public.task
  add constraint task_status_check
  check (status in ('Incomplete', 'Completed', 'Deleted'));

alter table public.task
  drop constraint if exists task_pause_status_check;

alter table public.task
  add constraint task_pause_status_check
  check (pause_status in ('Paused', 'Not Paused'));

alter table public.subtask
  drop constraint if exists subtask_status_check;

alter table public.subtask
  add constraint subtask_status_check
  check (status in ('Incomplete', 'Completed', 'Deleted'));

alter table public.subtask
  drop constraint if exists subtask_pause_status_check;

alter table public.subtask
  add constraint subtask_pause_status_check
  check (pause_status in ('Paused', 'Not Paused'));

