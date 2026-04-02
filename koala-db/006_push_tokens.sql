-- ═══════════════════════════════════════════════════════════
-- 006_push_tokens.sql — FCM Push Token yonetimi
-- Ayni kullanici birden fazla cihazda olabilir
-- ═══════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS koala_push_tokens (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id TEXT NOT NULL,                -- Firebase UID
  device_token TEXT NOT NULL,           -- FCM token
  platform TEXT NOT NULL DEFAULT 'web', -- ios, android, web
  device_info TEXT,                     -- opsiyonel cihaz bilgisi (model, OS version)
  is_active BOOLEAN DEFAULT true,
  last_used_at TIMESTAMPTZ DEFAULT now(),
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(user_id, device_token)
);

-- Indexler
CREATE INDEX IF NOT EXISTS idx_push_tokens_user_active
  ON koala_push_tokens(user_id, is_active) WHERE is_active = true;
CREATE INDEX IF NOT EXISTS idx_push_tokens_token
  ON koala_push_tokens(device_token);

-- RLS
ALTER TABLE koala_push_tokens ENABLE ROW LEVEL SECURITY;

-- Kullanici kendi token'larini yonetir
CREATE POLICY "Users manage own push tokens"
  ON koala_push_tokens FOR ALL
  USING (auth.uid()::text = user_id)
  WITH CHECK (auth.uid()::text = user_id);

-- Backend/service_role tum token'lara erisebilir (push gondermek icin)
-- Bu policy service_role key ile otomatik bypass olur, ekstra policy gereksiz
