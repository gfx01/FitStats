-- Training: routines (plans of exercises with target sets, reps and weights) and the workouts
-- logged in the app set by set (lib/training.ts). The coach reads both and can save routines.
create table if not exists public.fs_routines (
  id uuid primary key,
  name text not null,
  notes text,
  exercises jsonb not null default '[]'::jsonb,
  created_by text not null default 'user' check (created_by in ('user', 'coach')),
  position int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.fs_workout_logs (
  id uuid primary key,
  date date not null,
  started_at timestamptz,
  ended_at timestamptz,
  routine_id uuid references public.fs_routines (id) on delete set null,
  name text not null,
  exercises jsonb not null default '[]'::jsonb,
  notes text,
  effort int check (effort between 1 and 10),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists fs_workout_logs_date on public.fs_workout_logs (date);

alter table public.fs_routines enable row level security;
alter table public.fs_workout_logs enable row level security;
revoke all on table public.fs_routines from anon, authenticated;
revoke all on table public.fs_workout_logs from anon, authenticated;
grant all on table public.fs_routines to service_role;
grant all on table public.fs_workout_logs to service_role;
