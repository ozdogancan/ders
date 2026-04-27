-- ============================================================================
-- Koala — Full Şema Migration
-- Flutter + Next.js iç mekan tasarım uygulaması
-- Supabase Postgres + pgvector + RLS + Storage
-- ============================================================================

-- Extensions
create extension if not exists "uuid-ossp";
create extension if not exists "vector";

-- ============================================================================
-- TABLOLAR
-- ============================================================================

-- 1) users — son kullanıcı profili (auth.users'a bağlı)
create table if not exists public.users (
  id uuid primary key references auth.users(id) on delete cascade,
  email text unique,
  phone text,
  plan_tier text not null default 'free' check (plan_tier in ('free','pro','studio')),
  render_credits_remaining int not null default 3,
  created_at timestamptz not null default now()
);

-- 2) spaces — kullanıcının çektiği oda fotoğrafları ve AI analiz sonuçları
create table if not exists public.spaces (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references public.users(id) on delete cascade,
  image_url text not null,
  room_type text,                 -- 'living','bedroom','kitchen','bathroom','office'
  palette_json jsonb,             -- dominant renkler
  style_primary text,             -- 'modern','scandinavian','industrial' vb.
  style_confidence real check (style_confidence between 0 and 1),
  created_at timestamptz not null default now()
);
create index if not exists idx_spaces_user on public.spaces(user_id);
create index if not exists idx_spaces_room on public.spaces(room_type);

-- 3) user_taste — swipe ile öğrenilen zevk profili (oda tipi bazlı)
create table if not exists public.user_taste (
  user_id uuid not null references public.users(id) on delete cascade,
  room_type text not null,
  style_votes_json jsonb not null default '{}'::jsonb, -- {modern:12, scandi:3, ...}
  inferred_style text,
  confidence real check (confidence between 0 and 1),
  last_updated timestamptz not null default now(),
  primary key (user_id, room_type)
);

-- 4) restyle_jobs — AI restyle işleri
create table if not exists public.restyle_jobs (
  id uuid primary key default uuid_generate_v4(),
  space_id uuid not null references public.spaces(id) on delete cascade,
  target_style text not null,
  result_url text,
  status text not null default 'queued' check (status in ('queued','running','done','failed')),
  model_used text,
  cost_usd numeric(8,4) default 0,
  created_at timestamptz not null default now()
);
create index if not exists idx_restyle_space on public.restyle_jobs(space_id);
create index if not exists idx_restyle_status on public.restyle_jobs(status);

-- 5) pros — profesyoneller (mimar/iç mimar/usta)
create table if not exists public.pros (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid unique not null references public.users(id) on delete cascade,
  name text not null,
  city text,
  bio text,
  rating real default 0 check (rating between 0 and 5),
  portfolio_embed vector(512),
  top_styles text[] default '{}',
  avg_price_per_sqm numeric(10,2),
  approved boolean not null default false
);
create index if not exists idx_pros_city on public.pros(city);
create index if not exists idx_pros_approved on public.pros(approved);
create index if not exists idx_pros_embed on public.pros using ivfflat (portfolio_embed vector_cosine_ops) with (lists = 50);

-- 6) pro_portfolio — profesyonel portföy görselleri
create table if not exists public.pro_portfolio (
  id uuid primary key default uuid_generate_v4(),
  pro_id uuid not null references public.pros(id) on delete cascade,
  image_url text not null,
  style_label text,
  embed vector(512)
);
create index if not exists idx_portfolio_pro on public.pro_portfolio(pro_id);

-- 7) conversations — kullanıcı ↔ pro sohbet
create table if not exists public.conversations (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references public.users(id) on delete cascade,
  pro_id uuid not null references public.pros(id) on delete cascade,
  space_id uuid references public.spaces(id) on delete set null,
  created_at timestamptz not null default now(),
  unique (user_id, pro_id, space_id)
);
create index if not exists idx_conv_user on public.conversations(user_id);
create index if not exists idx_conv_pro on public.conversations(pro_id);

-- 8) messages — sohbet mesajları, teklif (quote) desteği
create table if not exists public.messages (
  id uuid primary key default uuid_generate_v4(),
  conv_id uuid not null references public.conversations(id) on delete cascade,
  sender_id uuid not null references public.users(id) on delete cascade,
  content text,
  attachment_url text,
  is_quote boolean not null default false,
  quote_json jsonb,                    -- {items:[...], total, valid_until}
  created_at timestamptz not null default now()
);
create index if not exists idx_msg_conv on public.messages(conv_id, created_at);

-- 9) subscriptions — abonelikler
create table if not exists public.subscriptions (
  user_id uuid primary key references public.users(id) on delete cascade,
  tier text not null check (tier in ('free','pro','studio')),
  renews_at timestamptz,
  provider text,                       -- 'stripe','iyzico','apple','google'
  ext_id text
);

-- 10) transactions — ödeme ve komisyon kayıtları
create table if not exists public.transactions (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references public.users(id) on delete cascade,
  pro_id uuid not null references public.pros(id) on delete cascade,
  amount numeric(12,2) not null,
  commission numeric(12,2) not null default 0,
  status text not null default 'pending' check (status in ('pending','paid','refunded','failed')),
  quote_id uuid references public.messages(id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists idx_tx_user on public.transactions(user_id);
create index if not exists idx_tx_pro on public.transactions(pro_id);

-- ============================================================================
-- RLS — Row Level Security
-- ============================================================================

alter table public.users enable row level security;
alter table public.spaces enable row level security;
alter table public.user_taste enable row level security;
alter table public.restyle_jobs enable row level security;
alter table public.pros enable row level security;
alter table public.pro_portfolio enable row level security;
alter table public.conversations enable row level security;
alter table public.messages enable row level security;
alter table public.subscriptions enable row level security;
alter table public.transactions enable row level security;

-- users: sadece kendi satırı
create policy users_self on public.users for all using (auth.uid() = id) with check (auth.uid() = id);

-- spaces: sahibi
create policy spaces_owner on public.spaces for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- user_taste: sahibi
create policy taste_owner on public.user_taste for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- restyle_jobs: space sahibi
create policy restyle_owner on public.restyle_jobs for all
  using (exists (select 1 from public.spaces s where s.id = space_id and s.user_id = auth.uid()))
  with check (exists (select 1 from public.spaces s where s.id = space_id and s.user_id = auth.uid()));

-- pros: onaylılar herkese görünür
create policy pros_public_read on public.pros for select using (approved = true or auth.uid() = user_id);
-- pros: yalnız kendi profilini update/insert
create policy pros_self_write on public.pros for insert with check (auth.uid() = user_id);
create policy pros_self_update on public.pros for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- pro_portfolio: herkes görür, pro kendi satırını yazar
create policy portfolio_read on public.pro_portfolio for select using (true);
create policy portfolio_write on public.pro_portfolio for all
  using (exists (select 1 from public.pros p where p.id = pro_id and p.user_id = auth.uid()))
  with check (exists (select 1 from public.pros p where p.id = pro_id and p.user_id = auth.uid()));

-- conversations: katılımcılar
create policy conv_participants on public.conversations for all
  using (
    auth.uid() = user_id
    or exists (select 1 from public.pros p where p.id = pro_id and p.user_id = auth.uid())
  )
  with check (
    auth.uid() = user_id
    or exists (select 1 from public.pros p where p.id = pro_id and p.user_id = auth.uid())
  );

-- messages: yalnız conversation katılımcıları
create policy messages_participants on public.messages for all
  using (
    exists (
      select 1 from public.conversations c
      where c.id = conv_id
        and (c.user_id = auth.uid()
             or exists (select 1 from public.pros p where p.id = c.pro_id and p.user_id = auth.uid()))
    )
  )
  with check (sender_id = auth.uid());

-- subscriptions: sahibi
create policy subs_owner on public.subscriptions for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- transactions: taraflar okur, yazma service_role'a bırakılır
create policy tx_read on public.transactions for select
  using (
    auth.uid() = user_id
    or exists (select 1 from public.pros p where p.id = pro_id and p.user_id = auth.uid())
  );

-- ============================================================================
-- RPC FONKSİYONLARI
-- ============================================================================

-- match_pros: kullanıcı embed + şehir filtresi → cosine similarity top N
create or replace function public.match_pros(
  user_embed vector(512),
  user_city text,
  match_limit int default 10
)
returns table (
  id uuid,
  name text,
  city text,
  rating real,
  top_styles text[],
  avg_price_per_sqm numeric,
  similarity real
)
language sql stable
as $$
  select
    p.id, p.name, p.city, p.rating, p.top_styles, p.avg_price_per_sqm,
    1 - (p.portfolio_embed <=> user_embed) as similarity
  from public.pros p
  where p.approved = true
    and p.portfolio_embed is not null
    and (user_city is null or p.city = user_city)
  order by p.portfolio_embed <=> user_embed
  limit match_limit;
$$;

-- classify_user_taste: oy sayısına göre öneri kararı
create or replace function public.classify_user_taste(
  p_user_id uuid,
  p_room_type text
)
returns jsonb
language plpgsql stable
as $$
declare
  v_votes jsonb;
  v_top text;
  v_top_count int := 0;
  v_total int := 0;
  v_conf real;
  v_rec text;
  r record;
begin
  select style_votes_json into v_votes
  from public.user_taste
  where user_id = p_user_id and room_type = p_room_type;

  if v_votes is null then
    return jsonb_build_object('inferred_style', null, 'confidence', 0, 'recommendation', 'swipe');
  end if;

  for r in select key, (value)::text::int as cnt from jsonb_each_text(v_votes) loop
    v_total := v_total + r.cnt;
    if r.cnt > v_top_count then
      v_top_count := r.cnt;
      v_top := r.key;
    end if;
  end loop;

  if v_total = 0 then
    v_conf := 0;
  else
    v_conf := v_top_count::real / v_total::real;
  end if;

  if v_total >= 8 and v_conf >= 0.55 then
    v_rec := 'use';
  else
    v_rec := 'swipe';
  end if;

  return jsonb_build_object(
    'inferred_style', v_top,
    'confidence', v_conf,
    'recommendation', v_rec
  );
end;
$$;

-- ============================================================================
-- STORAGE BUCKETS
-- ============================================================================

insert into storage.buckets (id, name, public) values
  ('spaces', 'spaces', true),
  ('restyles', 'restyles', true),
  ('portfolio', 'portfolio', true)
on conflict (id) do nothing;

-- public read
create policy "public_read_spaces"    on storage.objects for select using (bucket_id = 'spaces');
create policy "public_read_restyles"  on storage.objects for select using (bucket_id = 'restyles');
create policy "public_read_portfolio" on storage.objects for select using (bucket_id = 'portfolio');

-- auth write (kullanıcı kendi klasörüne)
create policy "auth_write_spaces" on storage.objects for insert
  with check (bucket_id = 'spaces' and auth.role() = 'authenticated' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "auth_write_restyles" on storage.objects for insert
  with check (bucket_id = 'restyles' and auth.role() = 'authenticated' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "auth_write_portfolio" on storage.objects for insert
  with check (bucket_id = 'portfolio' and auth.role() = 'authenticated' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "auth_update_own_objects" on storage.objects for update
  using (auth.uid()::text = (storage.foldername(name))[1])
  with check (auth.uid()::text = (storage.foldername(name))[1]);

create policy "auth_delete_own_objects" on storage.objects for delete
  using (auth.uid()::text = (storage.foldername(name))[1]);
