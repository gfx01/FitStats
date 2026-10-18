-- Sync every 5 minutes (was 15). A run whose recent days come back exactly as
-- last time writes and recomputes nothing (recent_fingerprint), so the shorter
-- interval stays cheap. Scheduling an existing job name replaces its schedule.
alter table public.fs_sync_state add column if not exists recent_fingerprint text;

select cron.schedule(
  'fitstats-sync',
  '*/5 * * * *',
  $$
  select net.http_post(
    url := 'https://zkxnbcrayjwkeyxlungk.supabase.co/functions/v1/fitstats?r=cron',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-cron-secret', (select value from public.fs_secrets where name = 'cron_secret')
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 10000
  );
  $$
);
