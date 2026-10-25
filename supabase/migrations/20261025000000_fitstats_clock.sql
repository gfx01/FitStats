-- The phone's clock (true = 24 hours, false = 12), sent by the app with each coach request, so
-- the coach writes times the way the phone shows them, also in the weekly summary the server
-- writes on its own (lib/coach.ts maybeWeeklySummary). Null until the app has sent it.
alter table public.fs_user_settings add column if not exists clock_24h boolean;
