-- ============================================================================
-- Koala Pro Subscriptions — Phase 1 infrastructure
-- ============================================================================
-- Adds Pro subscription state to user_profiles, plus billing event log
-- and quota usage tracking. Supports Android Play Billing in v1
-- (iOS / Stripe deferred to v2).
-- ============================================================================

-- user_profiles bootstrap (table may not exist in fresh installs).
do $$
begin
  if not exists (select from pg_tables where tablename = 'user_profiles') then
    create table user_profiles (
      id uuid primary key,        -- matches Firebase UID (text-cast or uuid-cast as your env uses)
      created_at timestamptz default now()
    );
  end if;
end$$;

alter table user_profiles
  add column if not exists pro_until        timestamptz,
  add column if not exists pro_plan         text check (pro_plan in ('weekly','monthly','yearly')),
  add column if not exists pro_platform     text check (pro_platform in ('android','ios','web')),
  add column if not exists pro_started_at   timestamptz,
  add column if not exists pro_cancelled_at timestamptz,
  add column if not exists trial_used       boolean default false;

-- Append-only event log for audits + restore fallback.
create table if not exists billing_events (
  id uuid primary key default gen_random_uuid(),
  user_id text not null,
  platform text not null,
  product_id text,
  event_type text not null,        -- purchase | renewal | cancel | refund | grace_start | grace_end | restore
  raw jsonb,
  received_at timestamptz default now()
);
create index if not exists billing_events_user_idx on billing_events(user_id, received_at desc);

-- Per-user counters for free-tier gates.
create table if not exists billing_quota_usage (
  user_id text not null,
  period text not null,            -- 'YYYY-MM' for monthly quotas, 'YYYY-MM-DD' for daily
  feature text not null,           -- 'restyle' | 'chat' | 'save' | 'designer_dm'
  count int not null default 0,
  primary key (user_id, period, feature)
);

-- Convenience view: is user pro right now?
create or replace view v_user_pro_status as
  select id as user_id,
         (pro_until is not null and pro_until > now()) as is_pro,
         pro_until, pro_plan, pro_platform
  from user_profiles;
