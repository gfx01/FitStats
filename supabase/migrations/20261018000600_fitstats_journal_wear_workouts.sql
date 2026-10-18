-- Wear time and the hour-by-hour shape of steps per day, load and zones per
-- workout, and the daily journal.

-- wear_min: minutes with heart-rate data; low_wear: worn much less than usual,
-- so day totals are left out of averages; steps_by_hour: cumulative minute
-- steps at the end of each local hour (24 values).
alter table public.fs_days
  add column if not exists wear_min int,
  add column if not exists low_wear boolean,
  add column if not exists steps_by_hour int[];

-- From the minute heart rate during the workout (lib/scores.ts).
alter table public.fs_exercise
  add column if not exists trimp double precision,
  add column if not exists strain double precision,
  add column if not exists hr_max int,
  add column if not exists hrr_zone_min int[];

-- One row per day the journal was filled in. tags = '{}' means "nothing to
-- note", which still counts as a logged day when comparing tags.
create table if not exists public.fs_journal (
  date date primary key,
  tags text[] not null default '{}',
  note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.fs_journal enable row level security;
revoke all on table public.fs_journal from anon, authenticated;
grant all on table public.fs_journal to service_role;
