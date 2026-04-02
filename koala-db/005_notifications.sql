-- ═══════════════════════════════════════════════════════════
-- 005_notifications.sql — Bildirim sistemi
-- Uygulama ici bildirimler (push degil, in-app)
-- ═══════════════════════════════════════════════════════════

-- Notifications tablosu
CREATE TABLE IF NOT EXISTS koala_notifications (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id TEXT NOT NULL,                -- bildirim alicisi (Firebase UID)
  type TEXT NOT NULL,                   -- bildirim tipi (asagidaki enum)
  title TEXT NOT NULL,                  -- baslik
  body TEXT,                            -- aciklama metni
  image_url TEXT,                       -- opsiyonel gorsel (avatar, urun, vb.)
  action_type TEXT,                     -- tiklaninca ne olacak
  action_data JSONB,                    -- tiklaninca gidilecek yer parametreleri
  is_read BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- ═══════════════════════════════════════════════════════════
-- Bildirim tipleri (type kolonu):
--   new_message        → tasarimcidan yeni mesaj
--   designer_match     → AI tasarimci eslestirmesi
--   product_recommend  → AI urun onerisi
--   style_result       → stil analizi tamamlandi
--   budget_ready       → butce plani hazir
--   collection_update  → koleksiyona yeni oge eklendi
--   system             → sistem bildirimi (guncelleme, vb.)
--   promo              → kampanya / indirim
--
-- action_type kolonu:
--   open_conversation  → action_data: {"conversation_id": "..."}
--   open_designer      → action_data: {"designer_id": "..."}
--   open_product       → action_data: {"product_id": "...", "url": "..."}
--   open_collection    → action_data: {"collection_id": "..."}
--   open_chat          → action_data: {"chat_id": "..."}
--   open_url           → action_data: {"url": "..."}
-- ═══════════════════════════════════════════════════════════

-- Indexler
CREATE INDEX IF NOT EXISTS idx_notifications_user ON koala_notifications(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_notifications_unread ON koala_notifications(user_id, is_read) WHERE is_read = false;

-- RLS
ALTER TABLE koala_notifications ENABLE ROW LEVEL SECURITY;

-- Kullanici sadece kendi bildirimlerini gorebilir
CREATE POLICY "Users see own notifications"
  ON koala_notifications FOR SELECT
  USING (auth.uid()::text = user_id);

-- Sistem/backend bildirim olusturabilir (service_role ile)
-- Client tarafindan da olusturulabilir (ornegin test icin)
CREATE POLICY "Insert notifications"
  ON koala_notifications FOR INSERT
  WITH CHECK (true);

-- Kullanici kendi bildirimlerini okundu isaret edebilir
CREATE POLICY "Users update own notifications"
  ON koala_notifications FOR UPDATE
  USING (auth.uid()::text = user_id);

-- Kullanici kendi bildirimlerini silebilir
CREATE POLICY "Users delete own notifications"
  ON koala_notifications FOR DELETE
  USING (auth.uid()::text = user_id);

-- Realtime icin publication'a ekle
ALTER PUBLICATION supabase_realtime ADD TABLE koala_notifications;
