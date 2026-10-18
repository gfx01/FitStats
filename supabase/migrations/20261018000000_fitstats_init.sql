-- FitStats: personal Fitbit (Google Health API) statistics backend.
--
-- Every table is private: RLS is enabled with no policies and the anon /
-- authenticated roles have no grants. Only the `fitstats` Edge Function
-- (service role) reads or writes them; the iOS app talks to that function
-- with an app key, never to PostgREST directly.

create extension if not exists pg_net;
create extension if not exists pg_cron;

-- Google connection (single owner).
create table public.fs_account (
  id smallint primary key default 1 check (id = 1),
  google_sub text,
  google_email text,
  health_user_id text,
  refresh_token text,
  access_token text,
  access_token_expires_at timestamptz,
  granted_scopes text,
  connected_at timestamptz,
  token_status text not null default 'disconnected', -- disconnected | ok | expired | error
  token_error text,
  time_zone text,
  profile jsonb,
  google_settings jsonb,
  devices jsonb,
  meta_fetched_at timestamptz,
  updated_at timestamptz not null default now()
);

-- Preferences edited from the app.
create table public.fs_user_settings (
  id smallint primary key default 1 check (id = 1),
  sex text not null default 'unspecified' check (sex in ('male', 'female', 'unspecified')),
  max_hr_override int check (max_hr_override between 120 and 230),
  sleep_need_min int not null default 480 check (sleep_need_min between 300 and 720),
  step_goal int not null default 10000 check (step_goal between 1000 and 50000),
  backfill_days int not null default 730 check (backfill_days between 7 and 3650),
  updated_at timestamptz not null default now()
);

-- SHA-256 hashes of app keys minted after a successful Google sign-in.
create table public.fs_app_keys (
  key_hash text primary key,
  created_at timestamptz not null default now(),
  last_used_at timestamptz
);

-- Short-lived OAuth state (CSRF + PKCE verifier).
create table public.fs_oauth_states (
  state text primary key,
  code_verifier text not null,
  app_redirect text not null,
  created_at timestamptz not null default now()
);

create table public.fs_secrets (
  name text primary key,
  value text not null
);

create table public.fs_sync_state (
  id smallint primary key default 1 check (id = 1),
  backfill_oldest date,
  backfill_target date,
  backfill_done boolean not null default false,
  last_recent_sync_at timestamptz,
  last_run_started_at timestamptz,
  last_run_finished_at timestamptz,
  last_run_status text,
  last_run_log jsonb,
  lock_until timestamptz,
  updated_at timestamptz not null default now()
);

-- One row per local calendar day.
create table public.fs_days (
  date date primary key,
  -- activity
  steps int,
  distance_m double precision,
  floors int,
  calories_total double precision,
  calories_active double precision,
  azm_fat_burn int,
  azm_cardio int,
  azm_peak int,
  active_light_min int,
  active_moderate_min int,
  active_vigorous_min int,
  sedentary_min double precision,
  hr_min double precision,
  hr_avg double precision,
  hr_max double precision,
  zone_light_min double precision,
  zone_moderate_min double precision,
  zone_vigorous_min double precision,
  zone_peak_min double precision,
  -- vitals
  rhr int,
  hrv_rmssd double precision,
  hrv_deep_rmssd double precision,
  hrv_entropy double precision,
  non_rem_hr int,
  spo2_avg double precision,
  spo2_lower double precision,
  spo2_upper double precision,
  resp_rate double precision,
  skin_temp_c double precision,
  skin_temp_baseline_c double precision,
  skin_temp_stddev_c double precision,
  vo2max double precision,
  vo2max_level text,
  vo2max_estimated boolean,
  weight_kg double precision,
  body_fat_pct double precision,
  hr_zones jsonb,
  -- main sleep that ended on this date
  sleep_start timestamptz,
  sleep_end timestamptz,
  sleep_asleep_min int,
  sleep_in_bed_min int,
  sleep_awake_min int,
  sleep_deep_min int,
  sleep_light_min int,
  sleep_rem_min int,
  sleep_latency_min int,
  sleep_awakenings int,
  sleep_efficiency double precision,
  sleep_bedtime_min int,  -- minutes from local midnight of this date (negative = before midnight)
  sleep_waketime_min int, -- minutes from local midnight of this date
  sleep_has_stages boolean,
  nap_min int,
  -- derived from minute heart rate
  trimp double precision,
  strain double precision,
  stress double precision,
  stress_minutes int,
  -- scores
  recovery double precision,
  sleep_score double precision,
  score_details jsonb,
  updated_at timestamptz not null default now()
);

create table public.fs_sleep (
  id text primary key,
  date date not null,
  start_time timestamptz not null,
  end_time timestamptz not null,
  start_offset_s int,
  end_offset_s int,
  is_main boolean,
  is_nap boolean,
  sleep_type text,
  minutes_asleep int,
  minutes_awake int,
  minutes_in_period int,
  minutes_to_fall_asleep int,
  minutes_after_wakeup int,
  deep_min int,
  light_min int,
  rem_min int,
  awake_min int,
  awake_count int,
  stages jsonb, -- [[stage, startEpochSec, endEpochSec], ...]
  updated_at timestamptz not null default now()
);
create index fs_sleep_date_idx on public.fs_sleep (date);

create table public.fs_exercise (
  id text primary key,
  date date not null,
  start_time timestamptz not null,
  end_time timestamptz not null,
  utc_offset_s int,
  exercise_type text,
  name text,
  duration_s int,
  active_duration_s int,
  calories double precision,
  steps int,
  distance_m double precision,
  avg_hr int,
  azm int,
  zone_light_s int,
  zone_moderate_s int,
  zone_vigorous_s int,
  zone_peak_s int,
  elevation_gain_m double precision,
  avg_speed_mps double precision,
  run_vo2max double precision,
  updated_at timestamptz not null default now()
);
create index fs_exercise_date_idx on public.fs_exercise (date);

-- Minute-level heart rate and steps (1440 slots per local day, null = no data).
create table public.fs_intraday (
  date date primary key,
  hr smallint[],
  steps smallint[],
  updated_at timestamptz not null default now()
);

-- Raw samples: overnight HRV, SpO2, breathing rate per sleep stage.
create table public.fs_samples (
  metric text not null,
  t timestamptz not null,
  date date not null,
  value double precision not null,
  primary key (metric, t)
);
create index fs_samples_metric_date_idx on public.fs_samples (metric, date);

create table public.fs_cache (
  key text primary key,
  value jsonb not null,
  updated_at timestamptz not null default now()
);

insert into public.fs_account default values;
insert into public.fs_user_settings default values;
insert into public.fs_sync_state default values;
insert into public.fs_secrets (name, value)
values ('cron_secret', encode(extensions.gen_random_bytes(32), 'hex'));

do $$
declare t text;
begin
  foreach t in array array[
    'fs_account', 'fs_user_settings', 'fs_app_keys', 'fs_oauth_states', 'fs_secrets',
    'fs_sync_state', 'fs_days', 'fs_sleep', 'fs_exercise', 'fs_intraday', 'fs_samples', 'fs_cache'
  ] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on table public.%I from anon, authenticated', t);
    execute format('grant all on table public.%I to service_role', t);
  end loop;
end $$;

-- Sync lock so overlapping cron / manual runs never double-fetch.
create function public.fs_try_lock(p_seconds int default 170)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  acquired boolean;
begin
  update fs_sync_state
     set lock_until = now() + make_interval(secs => p_seconds),
         last_run_started_at = now()
   where id = 1
     and (lock_until is null or lock_until < now())
  returning true into acquired;
  return coalesce(acquired, false);
end;
$$;

create function public.fs_unlock()
returns void
language sql
security definer
set search_path = public
as $$
  update fs_sync_state set lock_until = null where id = 1;
$$;

revoke execute on function public.fs_try_lock(int) from public, anon, authenticated;
revoke execute on function public.fs_unlock() from public, anon, authenticated;
grant execute on function public.fs_try_lock(int) to service_role;
grant execute on function public.fs_unlock() to service_role;
