-- ═══════════════════════════════════════════════════════════
-- 008_review.sql — Tum tablolarin index ve RLS review'u
-- Eksik index'leri ekler, RLS tutarsizliklarini duzeltir
-- ═══════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════
-- REVIEW OZET TABLOSU
-- ═══════════════════════════════════════════════════════════
--
-- Tablo                    | Index | RLS | Policy Tipi          | Sorun
-- ─────────────────────────|───────|─────|──────────────────────|─────────────────────
-- koala_styles             |   0   |  ✅ | Public read          | ❌ Index yok (popularity, tags)
-- koala_products           |   0   |  ✅ | Public read          | ❌ Index yok (category, style_id)
-- koala_designers          |   0   |  ✅ | Public read          | ❌ Index yok (city, rating)
-- koala_inspirations       |   0   |  ✅ | Public read          | ❌ Index yok (style_id, room_type)
-- koala_tips               |   0   |  ✅ | Public read          | ❌ Index yok (category)
-- koala_user_prefs         |   0   |  ✅ | FOR ALL USING(true)  | ⚠️ Cok acik — herkes herkesinkini gorebilir
-- koala_chats              |   0   |  ✅ | FOR ALL USING(true)  | ⚠️ Cok acik — user_id kontrolu yok
-- koala_messages           |   0   |  ✅ | FOR ALL USING(true)  | ⚠️ Cok acik + index yok
-- koala_conversations      |   5   |  ✅ | Participant-based    | ✅ Iyi
-- koala_direct_messages    |   5   |  ✅ | Participant-based    | ✅ Iyi
-- koala_notifications      |   2   |  ✅ | User-based           | ✅ Iyi
-- koala_push_tokens        |   2   |  ✅ | User-based           | ✅ Iyi
-- koala_admin_logs         |   3   |  ✅ | Admin-based          | ✅ Iyi
-- ═══════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════
-- 1. EKSİK INDEX'LER (schema.sql tablolari icin)
-- ═══════════════════════════════════════════════════════════

-- koala_styles: popularity siralamasi icin
CREATE INDEX IF NOT EXISTS idx_styles_popularity
  ON koala_styles(popularity DESC);

-- koala_products: kategori ve stil filtresi icin
CREATE INDEX IF NOT EXISTS idx_products_category
  ON koala_products(category);
CREATE INDEX IF NOT EXISTS idx_products_style
  ON koala_products(style_id);
CREATE INDEX IF NOT EXISTS idx_products_rating
  ON koala_products(rating DESC);

-- koala_designers: sehir ve puan filtresi icin
CREATE INDEX IF NOT EXISTS idx_designers_city
  ON koala_designers(city);
CREATE INDEX IF NOT EXISTS idx_designers_rating
  ON koala_designers(rating DESC);

-- koala_inspirations: stil ve oda tipi filtresi icin
CREATE INDEX IF NOT EXISTS idx_inspirations_style
  ON koala_inspirations(style_id);
CREATE INDEX IF NOT EXISTS idx_inspirations_room
  ON koala_inspirations(room_type);
CREATE INDEX IF NOT EXISTS idx_inspirations_likes
  ON koala_inspirations(like_count DESC);

-- koala_tips: kategori filtresi icin
CREATE INDEX IF NOT EXISTS idx_tips_category
  ON koala_tips(category);

-- koala_user_prefs: user_id lookup (UNIQUE zaten var ama acik olsun)
-- UNIQUE constraint otomatik index olusturur, ekstra gereksiz

-- koala_chats: kullanici chatleri icin
CREATE INDEX IF NOT EXISTS idx_chats_user
  ON koala_chats(user_id, updated_at DESC);

-- koala_messages: chat mesajlari icin
CREATE INDEX IF NOT EXISTS idx_messages_chat
  ON koala_messages(chat_id, created_at DESC);

-- ═══════════════════════════════════════════════════════════
-- 2. RLS POLİCY DÜZELTMELERİ
-- schema.sql'deki "FOR ALL USING (true)" policy'leri
-- cok acik — herkes herkesinkini okuyabilir/degistirebilir
-- ═══════════════════════════════════════════════════════════

-- koala_user_prefs: eski policy'yi kaldirip kullanici bazli yap
DROP POLICY IF EXISTS "Users manage own prefs" ON koala_user_prefs;
CREATE POLICY "Users read own prefs"
  ON koala_user_prefs FOR SELECT
  USING (auth.uid()::text = user_id);
CREATE POLICY "Users insert own prefs"
  ON koala_user_prefs FOR INSERT
  WITH CHECK (auth.uid()::text = user_id);
CREATE POLICY "Users update own prefs"
  ON koala_user_prefs FOR UPDATE
  USING (auth.uid()::text = user_id);
CREATE POLICY "Users delete own prefs"
  ON koala_user_prefs FOR DELETE
  USING (auth.uid()::text = user_id);

-- koala_chats: eski policy'yi kaldirip kullanici bazli yap
DROP POLICY IF EXISTS "Users manage own chats" ON koala_chats;
CREATE POLICY "Users read own chats"
  ON koala_chats FOR SELECT
  USING (auth.uid()::text = user_id);
CREATE POLICY "Users insert own chats"
  ON koala_chats FOR INSERT
  WITH CHECK (auth.uid()::text = user_id);
CREATE POLICY "Users update own chats"
  ON koala_chats FOR UPDATE
  USING (auth.uid()::text = user_id);
CREATE POLICY "Users delete own chats"
  ON koala_chats FOR DELETE
  USING (auth.uid()::text = user_id);

-- koala_messages: eski policy'yi kaldirip kullanici bazli yap
DROP POLICY IF EXISTS "Users manage own messages" ON koala_messages;
CREATE POLICY "Users read own messages"
  ON koala_messages FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM koala_chats c
      WHERE c.id = chat_id AND c.user_id = auth.uid()::text
    )
  );
CREATE POLICY "Users insert own messages"
  ON koala_messages FOR INSERT
  WITH CHECK (auth.uid()::text = user_id);
CREATE POLICY "Users update own messages"
  ON koala_messages FOR UPDATE
  USING (auth.uid()::text = user_id);
CREATE POLICY "Users delete own messages"
  ON koala_messages FOR DELETE
  USING (auth.uid()::text = user_id);

-- ═══════════════════════════════════════════════════════════
-- 3. FK KONTROL
-- ═══════════════════════════════════════════════════════════
-- ✅ koala_products.style_id → koala_styles(id) — dogru
-- ✅ koala_inspirations.style_id → koala_styles(id) — dogru
-- ✅ koala_messages.chat_id → koala_chats(id) ON DELETE CASCADE — dogru
-- ✅ koala_direct_messages.conversation_id → koala_conversations(id) ON DELETE CASCADE — dogru
-- ⚠️ user_id alanları TEXT, Firebase UID kullandığı için FK yok — beklenen davranış
-- ⚠️ koala_conversations user_id/designer_id → users tablosu FK yok — Firebase UID
