-- ═══════════════════════════════════════════════════════════
-- 007_admin.sql — Admin log tablosu
-- Admin panel islemleri icin audit trail
-- NOT: users tablosunda zaten role kolonu var ('user','admin')
-- ═══════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS koala_admin_logs (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  admin_user_id TEXT NOT NULL,          -- islemi yapan admin (Firebase UID)
  action TEXT NOT NULL,                 -- ne yapildi (ornek asagida)
  target_type TEXT,                     -- hedef tablo/kaynak tipi
  target_id TEXT,                       -- hedef kayit ID'si
  metadata JSONB,                       -- ekstra detay (onceki deger, yeni deger, vb.)
  created_at TIMESTAMPTZ DEFAULT now()
);

-- ═══════════════════════════════════════════════════════════
-- Ornek action degerleri:
--   user_ban, user_unban, user_role_change
--   designer_approve, designer_reject, designer_suspend
--   product_remove, product_feature
--   content_delete, content_flag_resolve
--   notification_broadcast
--   system_config_change
--
-- Ornek metadata:
--   {"previous_role": "user", "new_role": "admin"}
--   {"reason": "Uygunsuz icerik", "reported_by": "user123"}
-- ═══════════════════════════════════════════════════════════

-- Indexler
CREATE INDEX IF NOT EXISTS idx_admin_logs_admin
  ON koala_admin_logs(admin_user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_admin_logs_target
  ON koala_admin_logs(target_type, target_id);
CREATE INDEX IF NOT EXISTS idx_admin_logs_action
  ON koala_admin_logs(action);

-- RLS
ALTER TABLE koala_admin_logs ENABLE ROW LEVEL SECURITY;

-- Sadece admin role'une sahip kullanicilar okuyabilir/yazabilir
-- NOT: Bu, users tablosunda role='admin' kontrolu yapar
-- Eger users tablosu Supabase'de degilse (Firestore'da ise),
-- basit bir policy kullanilir ve backend service_role ile yazar
CREATE POLICY "Admins read logs"
  ON koala_admin_logs FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM koala_user_prefs p
      WHERE p.user_id = auth.uid()::text
    )
    -- Gercek admin kontrolu: users tablosu Supabase'e tasininca
    -- asagidaki ile degistir:
    -- EXISTS (SELECT 1 FROM users u WHERE u.id = auth.uid()::text AND u.role = 'admin')
  );

CREATE POLICY "Admins insert logs"
  ON koala_admin_logs FOR INSERT
  WITH CHECK (auth.uid()::text = admin_user_id);
