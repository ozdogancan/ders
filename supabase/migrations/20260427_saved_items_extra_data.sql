-- 20260427_saved_items_extra_data.sql
-- saved_items tablosu Supabase dashboard üzerinden manuel açıldı; bu migration
-- onu kod tabanına idempotent şekilde sahiplendiriyor + eksik `extra_data`
-- kolonunu ekliyor (prod'da PGRST204 hatasının kaynağı).

-- ─── Tablo (yoksa oluştur) ──────────────────────────────────────────
create table if not exists public.saved_items (
  id            uuid primary key default gen_random_uuid(),
  user_id       text not null,                 -- Firebase UID
  item_type     text not null,                 -- design | designer | product | palette
  item_id       text not null,
  title         text,
  image_url     text,
  subtitle      text,
  extra_data    jsonb,
  collection_id uuid,
  created_at    timestamptz not null default now(),
  unique (user_id, item_type, item_id)
);

-- ─── Eksik kolonu ekle (üretimdeki tablo için) ──────────────────────
alter table public.saved_items
  add column if not exists extra_data jsonb;

alter table public.saved_items
  add column if not exists collection_id uuid;

-- ─── Indexler ───────────────────────────────────────────────────────
create index if not exists saved_items_user_type_idx
  on public.saved_items (user_id, item_type, created_at desc);

create index if not exists saved_items_user_collection_idx
  on public.saved_items (user_id, collection_id)
  where collection_id is not null;

-- ─── RLS ────────────────────────────────────────────────────────────
alter table public.saved_items enable row level security;

-- Service role full access (Flutter zaten anon key + Firebase UID filter ile çağırıyor;
-- yine de defansif RLS).
do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'saved_items'
      and policyname = 'saved_items_service_all'
  ) then
    create policy saved_items_service_all on public.saved_items
      for all to service_role using (true) with check (true);
  end if;
end $$;
