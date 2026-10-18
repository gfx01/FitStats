-- Rebuilding the statistics cache reads the whole history, and those reads count
-- as egress. Recent changes now rebuild it at most hourly; this flag remembers
-- that a rebuild is owed.
alter table public.fs_sync_state add column if not exists stats_dirty boolean not null default false;
