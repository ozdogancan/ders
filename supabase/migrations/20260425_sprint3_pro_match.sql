-- ============================================================================
-- Sprint 3 — Pro Marketplace v1
-- Text-based pro matching (no CLIP yet) + WhatsApp contact MVP
-- ============================================================================

-- 1) Contact kolonları — chat Sprint 4'te gelecek, şimdilik WhatsApp deep-link
alter table public.pros
  add column if not exists contact_whatsapp text,
  add column if not exists contact_email text,
  add column if not exists profile_image_url text,
  add column if not exists years_experience int;

-- 2) match_pros_by_style — CLIP embed'siz, text array overlap + city + rating
--    Ordering: en fazla stil örtüşmesi → en yüksek rating → en fazla tecrübe
create or replace function public.match_pros_by_style(
  p_styles text[],
  p_city text default null,
  p_limit int default 10
)
returns table (
  id uuid,
  name text,
  city text,
  bio text,
  rating real,
  top_styles text[],
  avg_price_per_sqm numeric,
  contact_whatsapp text,
  contact_email text,
  profile_image_url text,
  years_experience int,
  overlap_count int
)
language sql stable
as $$
  select
    p.id, p.name, p.city, p.bio, p.rating, p.top_styles,
    p.avg_price_per_sqm, p.contact_whatsapp, p.contact_email,
    p.profile_image_url, p.years_experience,
    cardinality(p.top_styles & p_styles) as overlap_count
  from public.pros p
  where p.approved = true
    and (p_city is null or p.city = p_city)
    and cardinality(p.top_styles & p_styles) > 0
  order by overlap_count desc, p.rating desc nulls last, p.years_experience desc nulls last
  limit p_limit;
$$;

-- ============================================================================
-- SEED — 5 demo pro + portfolio (Unsplash placeholder).
-- NOT: Bunlar placeholder! Gerçek Evlumba pro'larıyla değiştirin.
-- user_id kolonu auth.users'a FK olduğu için seed'de bypass ediyoruz.
-- RLS nedeniyle bu insert'ler service_role ile çalışmalı (Supabase SQL editor).
-- ============================================================================

-- Seed için geçici auth user'lar (seed data için dummy, production'da kaldırılabilir)
-- NOT: auth.users'a direkt insert güvenli değil; bunun yerine her pro için
-- user_id'yi nullable yapıp seed'ini kolaylaştırabiliriz. Şimdilik
-- gen_random_uuid() ile fake user_id atıyoruz — schema FK cascade olduğu için
-- auth.users'a gerçek row gerekiyor. Workaround: FK'yi drop et seed için,
-- production'da gerçek user_id'lerle düzelt.

-- ⚠️  GEÇİCİ: seed için user_id FK'sini kaldır (gerçek pro onboarding'i
-- geldiğinde auth.users ile düzgün bağlanacak)
alter table public.pros drop constraint if exists pros_user_id_fkey;
alter table public.pros alter column user_id drop not null;

-- 5 demo pro
insert into public.pros (
  id, name, city, bio, rating, top_styles, avg_price_per_sqm,
  contact_whatsapp, contact_email, profile_image_url, years_experience, approved
) values
(
  '00000000-0000-0000-0000-000000000001',
  'Elif Yıldız',
  'İstanbul',
  '10 yıldır İstanbul''da iç mimarlık. Skandinav ve Japandi uzmanı, sıcak ve sade mekanlar.',
  4.9,
  array['Scandinavian','Japandi','Minimalist'],
  2800,
  '905321234567',
  'elif@example.com',
  'https://images.unsplash.com/photo-1494790108755-2616b612b7a0?w=400',
  10,
  true
),
(
  '00000000-0000-0000-0000-000000000002',
  'Mert Kara',
  'İstanbul',
  'Modern ve endüstriyel projelerde uzman. Loft dönüşümleri ve açık plan tasarımı.',
  4.7,
  array['Modern','Industrial'],
  2400,
  '905331234567',
  'mert@example.com',
  'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=400',
  7,
  true
),
(
  '00000000-0000-0000-0000-000000000003',
  'Zeynep Ak',
  'Ankara',
  'Bohem ve Akdeniz esintili renkli mekanlar. Sıra dışı dokular, el yapımı detaylar.',
  4.8,
  array['Bohemian','Modern','Scandinavian'],
  2100,
  '905351234567',
  'zeynep@example.com',
  'https://images.unsplash.com/photo-1580489944761-15a19d654956?w=400',
  6,
  true
),
(
  '00000000-0000-0000-0000-000000000004',
  'Can Tekin',
  'İzmir',
  'Ege''nin ışığına göre tasarım. Akdeniz, rustik ve mid-century fusion.',
  4.6,
  array['Bohemian','Industrial'],
  1900,
  '905361234567',
  'can@example.com',
  'https://images.unsplash.com/photo-1500648767791-00dcc994a43e?w=400',
  8,
  true
),
(
  '00000000-0000-0000-0000-000000000005',
  'Seda Demir',
  'İstanbul',
  'Minimalist ve Japandi. Küçük yaşam alanlarında maksimum huzur.',
  5.0,
  array['Minimalist','Japandi','Scandinavian'],
  3200,
  '905371234567',
  'seda@example.com',
  'https://images.unsplash.com/photo-1438761681033-6461ffad8d80?w=400',
  12,
  true
)
on conflict (id) do update set
  name = excluded.name,
  city = excluded.city,
  bio = excluded.bio,
  rating = excluded.rating,
  top_styles = excluded.top_styles,
  avg_price_per_sqm = excluded.avg_price_per_sqm,
  contact_whatsapp = excluded.contact_whatsapp,
  contact_email = excluded.contact_email,
  profile_image_url = excluded.profile_image_url,
  years_experience = excluded.years_experience,
  approved = excluded.approved;

-- Her pro için 3-4 portfolio görseli
insert into public.pro_portfolio (id, pro_id, image_url, style_label) values
-- Elif (Scandinavian/Japandi)
(gen_random_uuid(), '00000000-0000-0000-0000-000000000001', 'https://images.unsplash.com/photo-1616486338812-3dadae4b4ace?w=800', 'Scandinavian'),
(gen_random_uuid(), '00000000-0000-0000-0000-000000000001', 'https://images.unsplash.com/photo-1540518614846-7eded433c457?w=800', 'Japandi'),
(gen_random_uuid(), '00000000-0000-0000-0000-000000000001', 'https://images.unsplash.com/photo-1586023492125-27b2c045efd7?w=800', 'Minimalist'),
(gen_random_uuid(), '00000000-0000-0000-0000-000000000001', 'https://images.unsplash.com/photo-1560448204-e02f11c3d0e2?w=800', 'Scandinavian'),
-- Mert (Modern/Industrial)
(gen_random_uuid(), '00000000-0000-0000-0000-000000000002', 'https://images.unsplash.com/photo-1600121848594-d8644e57abab?w=800', 'Modern'),
(gen_random_uuid(), '00000000-0000-0000-0000-000000000002', 'https://images.unsplash.com/photo-1600607687939-ce8a6c25118c?w=800', 'Industrial'),
(gen_random_uuid(), '00000000-0000-0000-0000-000000000002', 'https://images.unsplash.com/photo-1505693416388-ac5ce068fe85?w=800', 'Modern'),
-- Zeynep (Bohemian)
(gen_random_uuid(), '00000000-0000-0000-0000-000000000003', 'https://images.unsplash.com/photo-1600210491892-03d54c0aaf87?w=800', 'Bohemian'),
(gen_random_uuid(), '00000000-0000-0000-0000-000000000003', 'https://images.unsplash.com/photo-1616627561950-9f746e330187?w=800', 'Bohemian'),
(gen_random_uuid(), '00000000-0000-0000-0000-000000000003', 'https://images.unsplash.com/photo-1584622781564-1d987f7333c1?w=800', 'Bohemian'),
-- Can (Bohemian/Industrial)
(gen_random_uuid(), '00000000-0000-0000-0000-000000000004', 'https://images.unsplash.com/photo-1600585154526-990dced4db0d?w=800', 'Bohemian'),
(gen_random_uuid(), '00000000-0000-0000-0000-000000000004', 'https://images.unsplash.com/photo-1595526114035-0d45ed16cfbf?w=800', 'Industrial'),
(gen_random_uuid(), '00000000-0000-0000-0000-000000000004', 'https://images.unsplash.com/photo-1551298370-9d3d53740c72?w=800', 'Industrial'),
-- Seda (Minimalist/Japandi)
(gen_random_uuid(), '00000000-0000-0000-0000-000000000005', 'https://images.unsplash.com/photo-1586023492125-27b2c045efd7?w=800', 'Minimalist'),
(gen_random_uuid(), '00000000-0000-0000-0000-000000000005', 'https://images.unsplash.com/photo-1556909114-f6e7ad7d3136?w=800', 'Minimalist'),
(gen_random_uuid(), '00000000-0000-0000-0000-000000000005', 'https://images.unsplash.com/photo-1540518614846-7eded433c457?w=800', 'Japandi'),
(gen_random_uuid(), '00000000-0000-0000-0000-000000000005', 'https://images.unsplash.com/photo-1522771739844-6a9f6d5f14af?w=800', 'Minimalist')
on conflict (id) do nothing;
