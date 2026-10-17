-- Hesabaty: per-user financial state and read-only Play entitlement.
-- Run once in the Supabase SQL Editor for the Hesabaty project.
-- Never place privileged keys or a Google service account in the public app.

begin;

create table if not exists public.user_snapshots (
  user_id uuid primary key references auth.users(id) on delete cascade,
  snapshot jsonb not null default '{}'::jsonb,
  revision bigint not null default 1 check (revision >= 1),
  updated_at timestamptz not null default now(),
  constraint valid_snapshot check (jsonb_typeof(snapshot) = 'object')
);
alter table public.user_snapshots enable row level security;
revoke all on table public.user_snapshots from anon;
grant select, insert, update on table public.user_snapshots to authenticated;

drop policy if exists "user_snapshots_select_own" on public.user_snapshots;
drop policy if exists "user_snapshots_insert_own" on public.user_snapshots;
drop policy if exists "user_snapshots_update_own" on public.user_snapshots;
create policy "user_snapshots_select_own" on public.user_snapshots
  for select to authenticated using ((select auth.uid()) = user_id);
create policy "user_snapshots_insert_own" on public.user_snapshots
  for insert to authenticated with check ((select auth.uid()) = user_id);
create policy "user_snapshots_update_own" on public.user_snapshots
  for update to authenticated using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create table if not exists public.user_entitlements (
  user_id uuid primary key references auth.users(id) on delete cascade,
  product_id text not null,
  status text not null check (status in ('active','grace_period','on_hold','canceled','expired')),
  source text not null default 'google_play' check (source = 'google_play'),
  expires_at timestamptz,
  updated_at timestamptz not null default now()
);
alter table public.user_entitlements enable row level security;
revoke all on table public.user_entitlements from anon, authenticated;
grant select on table public.user_entitlements to authenticated;
drop policy if exists "user_entitlements_read_own" on public.user_entitlements;
create policy "user_entitlements_read_own" on public.user_entitlements
  for select to authenticated using ((select auth.uid()) = user_id);

comment on table public.user_entitlements is
  'Server-verified Google Play subscriptions only. Clients cannot grant themselves Premium.';

commit;
