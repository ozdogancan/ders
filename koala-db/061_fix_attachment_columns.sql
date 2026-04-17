-- ═══════════════════════════════════════════════════════════
-- 061_fix_attachment_columns.sql
-- ═══════════════════════════════════════════════════════════
-- SORUN:
--   Production DB'de koala_direct_messages tablosunda attachment_url ve
--   metadata kolonları yok (004_messaging.sql full çalıştırılmamış veya
--   eski schema). Foto gönderirken:
--     PostgrestException(message: Could not find the 'attachment_url'
--     column of 'koala_direct_messages' in the schema cache,
--     code: PGRST204)
--
-- ÇÖZÜM:
--   Eksik kolonları ekle + PostgREST schema cache'i reload et.
-- ═══════════════════════════════════════════════════════════

ALTER TABLE koala_direct_messages
  ADD COLUMN IF NOT EXISTS attachment_url TEXT;

ALTER TABLE koala_direct_messages
  ADD COLUMN IF NOT EXISTS metadata JSONB;

-- PostgREST schema cache reload — yeni kolonlar app'ten görünür olsun.
NOTIFY pgrst, 'reload schema';
