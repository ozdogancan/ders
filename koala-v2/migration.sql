-- ============================================================
-- KOALA: Okunma / Favori / Son Etkileşim Migration
-- Supabase SQL Editor'da çalıştır
-- ============================================================

-- 1. questions tablosuna yeni kolonlar ekle
ALTER TABLE questions ADD COLUMN IF NOT EXISTS is_read BOOLEAN DEFAULT false;
ALTER TABLE questions ADD COLUMN IF NOT EXISTS is_favorite BOOLEAN DEFAULT false;
ALTER TABLE questions ADD COLUMN IF NOT EXISTS last_interacted_at TIMESTAMPTZ DEFAULT NULL;

-- 2. Mevcut solved soruları: eğer chat_messages'da user mesajı varsa is_read=true yap
UPDATE questions q
SET is_read = true
WHERE q.status = 'solved'
  AND EXISTS (
    SELECT 1 FROM chat_messages cm
    WHERE cm.question_id = q.id
      AND cm.role = 'user'
  );

-- 3. last_interacted_at'ı mevcut chat'lerden doldur
UPDATE questions q
SET last_interacted_at = sub.last_chat
FROM (
  SELECT question_id, MAX(created_at) as last_chat
  FROM chat_messages
  GROUP BY question_id
) sub
WHERE q.id = sub.question_id;

-- 4. Index'ler (performans için)
CREATE INDEX IF NOT EXISTS idx_questions_is_favorite ON questions(user_id, is_favorite) WHERE is_favorite = true;
CREATE INDEX IF NOT EXISTS idx_questions_last_interacted ON questions(user_id, last_interacted_at DESC NULLS LAST);
CREATE INDEX IF NOT EXISTS idx_questions_is_read ON questions(user_id, is_read);
