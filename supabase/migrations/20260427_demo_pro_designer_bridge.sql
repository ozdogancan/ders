-- ============================================================================
-- Sprint 4 demo bridge — Elif (demo pro #1) -> Firebase test UID
--
-- Amaç: "Sohbet Başlat" akışını uçtan uca demo-edebilmek. Koala'nın Flutter
-- client'ı pros.designer_id null ise WhatsApp'a fallback yapıyor. Bu script
-- Elif'e demo amaçlı gerçek bir Firebase UID atar.
--
-- KULLANIM (Supabase SQL editor):
--   1. Firebase Console'da Koala projesine bir test user ekle (email+pass)
--   2. O user'ın uid'ini kopyala
--   3. Aşağıdaki :'DEMO_PRO_UID' psql variable'ını değiştir VEYA
--      string değerini doğrudan replace et.
--   4. Run.
--
-- BU PRODUCTION MIGRATION DEĞİL. supabase/migrations/ altında tutulmasının
-- tek nedeni aynı şema klasöründe iz bırakmak. CI otomasyonuna dahil etme.
-- ============================================================================

-- Elif (demo pro #1)
update public.pros
set designer_id = 'REPLACE_WITH_FIREBASE_TEST_UID'
where id = '00000000-0000-0000-0000-000000000001';

-- Koala user-satırını da ensure et — /api/conversations/ensure idempotent upsert
-- yapıyor ama demo user direkt seed-quote ile mesaj alırken users row olmalı.
insert into public.users (id, display_name)
values ('REPLACE_WITH_FIREBASE_TEST_UID', 'Elif (Demo)')
on conflict (id) do nothing;

-- Doğrulama
select id, name, designer_id
from public.pros
where id = '00000000-0000-0000-0000-000000000001';
