-- Which session a day's sleep columns came from, and time awake after falling
-- asleep (lib/transform.ts sleepDayPatch).

-- sleep_main_id: fs_sleep.id of the main sleep (not a nap > flagged main >
-- longest asleep); every other session of the day counts toward nap_min.
-- sleep_waso_min: minutes awake after sleep onset and before the final
-- awakening. sleep_awakenings now counts those same awake segments.
alter table public.fs_days
  add column if not exists sleep_main_id text,
  add column if not exists sleep_waso_min int;
