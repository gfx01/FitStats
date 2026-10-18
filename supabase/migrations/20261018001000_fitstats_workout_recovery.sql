-- Heart-rate recovery after each workout, from the minute heart rate (lib/scores.ts
-- heartRateRecovery, computed in lib/sync.ts next to the workout load).

-- end_hr: mean of the last 2 minutes of the workout's minute window (spikes removed).
-- hrr_1min / hrr_2min: end_hr minus the heart rate 1 and 2 minutes after the window.
-- All three are null unless the window is 10+ minutes with heart rate in 70 % of them,
-- end_hr is at least halfway up the heart-rate reserve, both minutes after have heart
-- rate and no other workout starts within 3 minutes after the end.
alter table public.fs_exercise
  add column if not exists end_hr int,
  add column if not exists hrr_1min int,
  add column if not exists hrr_2min int;
