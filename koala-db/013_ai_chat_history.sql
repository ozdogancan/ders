-- ═══════════════════════════════════════════════════════════
-- 013_ai_chat_history.sql — AI chat geçmişi (Supabase'e taşıma)
-- SharedPreferences → Supabase migration desteği
-- ═══════════════════════════════════════════════════════════

-- AI chat oturumları
CREATE TABLE IF NOT EXISTS ai_chat_sessions (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id TEXT NOT NULL,
  title TEXT DEFAULT 'Yeni Sohbet',
  intent TEXT DEFAULT 'general', -- styleExplore, roomRenovation, colorAdvice, designerMatch, budgetPlan, general
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- AI chat mesajları
CREATE TABLE IF NOT EXISTS ai_chat_messages (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  session_id UUID NOT NULL REFERENCES ai_chat_sessions(id) ON DELETE CASCADE,
  role TEXT NOT NULL CHECK (role IN ('user', 'assistant', 'system')),
  content TEXT,
  cards JSONB,           -- AI yanıtındaki kart verisi (style_analysis, product_grid vb.)
  image_url TEXT,        -- kullanıcı resim yüklediyse
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Index'ler
CREATE INDEX IF NOT EXISTS idx_ai_sessions_user
  ON ai_chat_sessions(user_id, updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_ai_messages_session
  ON ai_chat_messages(session_id, created_at ASC);

-- RLS
ALTER TABLE ai_chat_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE ai_chat_messages ENABLE ROW LEVEL SECURITY;

-- Kullanıcı sadece kendi session'larını görür
CREATE POLICY "Users manage own AI sessions"
  ON ai_chat_sessions FOR ALL
  USING (auth.uid()::text = user_id)
  WITH CHECK (auth.uid()::text = user_id);

-- Kullanıcı sadece kendi session'larının mesajlarını görür
CREATE POLICY "Users manage own AI messages"
  ON ai_chat_messages FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM ai_chat_sessions s
      WHERE s.id = session_id AND s.user_id = auth.uid()::text
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM ai_chat_sessions s
      WHERE s.id = session_id AND s.user_id = auth.uid()::text
    )
  );
