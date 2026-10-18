-- Workouts: heart-rate coverage, minute steps and where each workout came from; VO2 max
-- from samples on days without Google's daily value (lib/sync.ts, lib/transform.ts).

-- hr_minutes: minutes of the workout window with heart rate. steps_minute: minute steps
-- over the same window (Google's own step count is sometimes far too low).
-- recording_method / source_platform / source_device: DataPoint.dataSource
-- (PASSIVELY_MEASURED = auto-detected, ACTIVELY_MEASURED = tracked, MANUAL = logged).
alter table public.fs_exercise
  add column if not exists hr_minutes int,
  add column if not exists steps_minute int,
  add column if not exists recording_method text,
  add column if not exists source_platform text,
  add column if not exists source_device text;

-- vo2max_source: 'daily' (daily-vo2-max), 'sample' (vo2-max) or 'run' (run-vo2-max).
-- vo2max_method: the sample's measurementMethod (GOOGLE_DEMOGRAPHIC = estimated from the profile).
alter table public.fs_days
  add column if not exists vo2max_source text,
  add column if not exists vo2max_method text;
