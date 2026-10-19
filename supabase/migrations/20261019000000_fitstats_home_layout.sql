-- The Home screen layout from the app (cards, sizes, settings and the time-of-day layouts),
-- so it survives deleting and reinstalling the app. One row. edited_at is the time of the
-- app's last edit (seconds since 1970); the more recent edit wins.
create table if not exists public.fs_home_layout (
  id int primary key default 1 check (id = 1),
  layout jsonb not null,
  edited_at double precision not null default 0,
  updated_at timestamptz not null default now()
);

alter table public.fs_home_layout enable row level security;
revoke all on table public.fs_home_layout from anon, authenticated;
grant all on table public.fs_home_layout to service_role;
