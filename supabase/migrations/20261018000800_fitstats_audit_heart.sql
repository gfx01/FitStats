-- Heart rate: stress stillness, recovery and baseline, and the max heart rate in use
-- (lib/sync.ts, lib/scores.ts computeStress).

-- sedentary: seconds of each local minute Fitbit counted as sedentary (sedentary-period
-- rolled up in 60 s windows). Stress counts a minute only when it has 45 s or more,
-- on days that have this data.
alter table public.fs_intraday
  add column if not exists sedentary smallint[];

-- hr_peak_sustained: highest minute-average heart rate with a neighbouring minute at most
-- 15 bpm below it (isolated spikes don't count); the year's highest can raise the max heart rate.
-- stress_still_hrr: median heart-rate reserve of the day's qualifying (still, awake)
-- minutes; the median of the previous 30 days' values is the stress baseline.
alter table public.fs_days
  add column if not exists hr_peak_sustained int,
  add column if not exists stress_still_hrr real;

-- The max heart rate the stored history was computed with and where it came from
-- ('override', 'observed' or 'age'). Null makes the next sync recompute strain, stress,
-- workout loads and scores for the whole backfill window, which also brings the new
-- stress formula and the sustained peaks to the history already imported.
alter table public.fs_sync_state
  add column if not exists max_hr_used int,
  add column if not exists max_hr_source text;
