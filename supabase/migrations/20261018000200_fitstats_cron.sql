-- Sync every 15 minutes. The function returns 202 immediately and works in the
-- background; it skips quickly when nothing is stale.
select cron.schedule(
  'fitstats-sync',
  '*/15 * * * *',
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

-- Keep pg_net's response log small.
select cron.schedule(
  'fitstats-net-cleanup',
  '17 3 * * *',
  $$ delete from net._http_response where created < now() - interval '2 days'; $$
);
