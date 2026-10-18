-- Per-day details derived from minute heart rate, and backfill bookkeeping.
alter table public.fs_days add column if not exists intraday_details jsonb;
alter table public.fs_sync_state add column if not exists backfill_empty_chunks int not null default 0;
