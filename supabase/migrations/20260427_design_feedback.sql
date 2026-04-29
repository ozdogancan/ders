-- 20260427_design_feedback.sql
-- Kullanıcıların restyle çıktılarına verdiği 👍/👎 feedback'ini toplar.
-- Analiz: hangi tarz/oda kombinasyonları beğeniliyor, hangileri redediliyor.

create table if not exists public.design_feedback (
  id            uuid primary key default gen_random_uuid(),
  user_id       text not null,                      -- Firebase UID
  design_id     text not null,                      -- result_stage._itemId (sha1 first 24)
  rating        text not null check (rating in ('like', 'dislike')),
  room          text,
  theme         text,
  palette       text,
  layout        text,
  after_url     text,
  extra_data    jsonb,
  created_at    timestamptz not null default now(),
  unique (user_id, design_id)
);

create index if not exists design_feedback_design_idx
  on public.design_feedback (design_id);

create index if not exists design_feedback_theme_room_idx
  on public.design_feedback (theme, room, rating);

create index if not exists design_feedback_user_idx
  on public.design_feedback (user_id, created_at desc);

alter table public.design_feedback enable row level security;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'design_feedback'
      and policyname = 'design_feedback_service_all'
  ) then
    create policy design_feedback_service_all on public.design_feedback
      for all to service_role using (true) with check (true);
  end if;
end $$;
