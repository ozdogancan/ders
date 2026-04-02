-- ═══════════════════════════════════════════════════════════
-- 004_messaging.sql — Kullanici <-> Tasarimci mesajlasma
-- Koala direct messaging (AI chat degil!)
-- ═══════════════════════════════════════════════════════════

-- 1. Conversations (sohbet odalari)
CREATE TABLE IF NOT EXISTS koala_conversations (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id TEXT NOT NULL,               -- Firebase UID (ev sahibi)
  designer_id TEXT NOT NULL,           -- Firebase UID (tasarimci)
  title TEXT,                          -- opsiyonel baslik
  last_message TEXT,                   -- son mesaj onizleme
  last_message_at TIMESTAMPTZ DEFAULT now(),
  unread_count_user INT DEFAULT 0,     -- kullanicinin okumadigi
  unread_count_designer INT DEFAULT 0, -- tasarimcinin okumadigi
  status TEXT DEFAULT 'active',        -- active, archived, blocked
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(user_id, designer_id)
);

-- 2. Messages (mesajlar)
CREATE TABLE IF NOT EXISTS koala_direct_messages (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  conversation_id UUID NOT NULL REFERENCES koala_conversations(id) ON DELETE CASCADE,
  sender_id TEXT NOT NULL,             -- kim gonderdi (user veya designer UID)
  content TEXT,                        -- mesaj metni
  message_type TEXT DEFAULT 'text',    -- text, image, file, system
  attachment_url TEXT,                 -- gorsel/dosya URL
  metadata JSONB,                      -- ekstra veri (dosya boyutu, vb.)
  read_at TIMESTAMPTZ,                -- okunma zamani (null = okunmadi)
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Indexler (performans)
CREATE INDEX IF NOT EXISTS idx_conversations_user ON koala_conversations(user_id);
CREATE INDEX IF NOT EXISTS idx_conversations_designer ON koala_conversations(designer_id);
CREATE INDEX IF NOT EXISTS idx_conversations_last_msg ON koala_conversations(last_message_at DESC);
CREATE INDEX IF NOT EXISTS idx_messages_conversation ON koala_direct_messages(conversation_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_messages_sender ON koala_direct_messages(sender_id);

-- RLS
ALTER TABLE koala_conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE koala_direct_messages ENABLE ROW LEVEL SECURITY;

-- Policies: kullanici veya tasarimci kendi sohbetlerini gorebilir
CREATE POLICY "Users see own conversations"
  ON koala_conversations FOR SELECT
  USING (auth.uid()::text = user_id OR auth.uid()::text = designer_id);

CREATE POLICY "Users insert own conversations"
  ON koala_conversations FOR INSERT
  WITH CHECK (auth.uid()::text = user_id);

CREATE POLICY "Participants update conversation"
  ON koala_conversations FOR UPDATE
  USING (auth.uid()::text = user_id OR auth.uid()::text = designer_id);

-- Mesaj policies
CREATE POLICY "Participants see messages"
  ON koala_direct_messages FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM koala_conversations c
      WHERE c.id = conversation_id
      AND (auth.uid()::text = c.user_id OR auth.uid()::text = c.designer_id)
    )
  );

CREATE POLICY "Participants send messages"
  ON koala_direct_messages FOR INSERT
  WITH CHECK (auth.uid()::text = sender_id);

CREATE POLICY "Sender or recipient can update messages"
  ON koala_direct_messages FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM koala_conversations c
      WHERE c.id = conversation_id
      AND (auth.uid()::text = c.user_id OR auth.uid()::text = c.designer_id)
    )
  );

-- Realtime icin publication'a ekle
ALTER PUBLICATION supabase_realtime ADD TABLE koala_direct_messages;
ALTER PUBLICATION supabase_realtime ADD TABLE koala_conversations;
