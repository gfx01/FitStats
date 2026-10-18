-- Coach (Claude) chat history and model choice. Same lockdown as the other
-- fs_ tables: only the fitstats Edge Function (service role) can read them.

create table public.fs_coach_threads (
  id uuid primary key,
  title text not null default 'Chat',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.fs_coach_messages (
  id uuid primary key,
  thread_id uuid not null references public.fs_coach_threads (id) on delete cascade,
  role text not null check (role in ('user', 'assistant')),
  content text not null,
  model text,
  usage jsonb,
  created_at timestamptz not null default now()
);
create index fs_coach_messages_thread_idx on public.fs_coach_messages (thread_id, created_at);

-- null = server default (see lib/coach.ts)
alter table public.fs_user_settings add column coach_model text;

do $$
declare t text;
begin
  foreach t in array array['fs_coach_threads', 'fs_coach_messages'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on table public.%I from anon, authenticated', t);
    execute format('grant all on table public.%I to service_role', t);
  end loop;
end $$;
