-- Wake-up times set by hand (Settings → Wake-up times): seven entries, Monday first, each the
-- minutes from midnight to be up that morning or null for a morning without one. The sleep plan
-- (lib/planner.ts), the bedtime reminder and the coach use them; null = none set.
alter table public.fs_user_settings add column if not exists wake_times jsonb
  check (wake_times is null or (jsonb_typeof(wake_times) = 'array' and jsonb_array_length(wake_times) = 7));
