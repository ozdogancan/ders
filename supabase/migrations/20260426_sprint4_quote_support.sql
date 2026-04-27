-- ============================================================================
-- Sprint 4 — QuoteCard support on LEGACY chat tables
-- Koala Firebase Auth + koala_conversations / koala_direct_messages kullanıyor.
-- Yeni conversations/messages (auth.users FK'li) kullanılmıyor — bu migration
-- legacy tablolara quote desteği ekler. Non-breaking, sadece nullable kolonlar.
-- ============================================================================

-- 1) koala_direct_messages — structured quote payload için kolonlar
alter table public.koala_direct_messages
  add column if not exists is_quote boolean not null default false,
  add column if not exists quote_json jsonb;

create index if not exists idx_koala_messages_quotes
  on public.koala_direct_messages(conversation_id)
  where is_quote = true;

-- 2) koala_conversations — kabul edilen teklif referansı + commission
alter table public.koala_conversations
  add column if not exists accepted_quote_id uuid,
  add column if not exists quote_accepted_at timestamptz,
  add column if not exists quote_total_amount numeric(12,2),
  add column if not exists quote_currency text default 'TRY';

-- 3) pros ↔ legacy chat bridge — pros.id (UUID) ile koala_conversations.designer_id
-- (Firebase UID text) eşleşmiyor. Bridge: pros.designer_id text nullable.
-- Demo pro'lar için NULL (WhatsApp fallback). Gerçek pro onboarding'de
-- Firebase UID atanır → sohbet aktifleşir.
alter table public.pros
  add column if not exists designer_id text;

create index if not exists idx_pros_designer_id on public.pros(designer_id)
  where designer_id is not null;

-- 4) Test kolaylığı: demo pro #1 (Elif) için placeholder designer_id.
-- Gerçek kullanımda bu, Firebase Auth'tan gelen uid olmalı.
-- Test için: Firebase console'dan bir test user oluştur, uid'i buraya yaz.
update public.pros
set designer_id = null  -- 'FIREBASE_UID_FOR_ELIF_DEMO'  ← gerçek test UID ile değiştir
where id = '00000000-0000-0000-0000-000000000001'
  and designer_id is null;
