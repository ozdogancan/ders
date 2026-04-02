-- ═══════════════════════════════════════════════════════════
-- 009_analytics_optimization.sql — Analytics events tablosu
-- Tablo tanimini formalize et + retention + index
-- ═══════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════
-- 1. TABLO TANIMI (mevcut yoksa olustur)
-- Flutter Analytics servisi su kolonlari kullaniyor:
--   user_id, event_name, event_data, session_id, platform, app_version
-- ═══════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS analytics_events (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id TEXT,                         -- Firebase UID (null olabilir — anonymous)
  event_name TEXT NOT NULL,
  event_data JSONB DEFAULT '{}',
  session_id TEXT,
  platform TEXT DEFAULT 'web',          -- web, ios, android
  app_version TEXT DEFAULT '1.0.0',
  created_at TIMESTAMPTZ DEFAULT now()
);

-- ═══════════════════════════════════════════════════════════
-- 2. INDEX'LER
-- ═══════════════════════════════════════════════════════════

-- Zamana gore sorgulama (dashboard, retention analizi)
CREATE INDEX IF NOT EXISTS idx_analytics_created_at
  ON analytics_events(created_at DESC);

-- Event ismine gore filtreleme
CREATE INDEX IF NOT EXISTS idx_analytics_event_name
  ON analytics_events(event_name, created_at DESC);

-- Kullaniciya gore event gecmisi
CREATE INDEX IF NOT EXISTS idx_analytics_user
  ON analytics_events(user_id, created_at DESC)
  WHERE user_id IS NOT NULL;

-- Session bazli gruplama
CREATE INDEX IF NOT EXISTS idx_analytics_session
  ON analytics_events(session_id)
  WHERE session_id IS NOT NULL;

-- Platform filtresi (ios vs web vs android karsilastirma)
CREATE INDEX IF NOT EXISTS idx_analytics_platform
  ON analytics_events(platform, created_at DESC);

-- ═══════════════════════════════════════════════════════════
-- 3. RLS
-- ═══════════════════════════════════════════════════════════

ALTER TABLE analytics_events ENABLE ROW LEVEL SECURITY;

-- Herkes event yazabilir (anonim dahil)
CREATE POLICY "Anyone can insert analytics"
  ON analytics_events FOR INSERT
  WITH CHECK (true);

-- Sadece kendi event'lerini okuyabilir (veya service_role ile hepsi)
CREATE POLICY "Users read own analytics"
  ON analytics_events FOR SELECT
  USING (auth.uid()::text = user_id);

-- ═══════════════════════════════════════════════════════════
-- 4. RETENTION — 90 gunluk veri tutma
-- 30 gun cok kisa olabilir (aylik raporlar icin), 90 gun daha guvenli
-- Bu fonksiyon cron job ile calistirilir (pg_cron veya n8n)
-- ═══════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION cleanup_old_analytics()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  DELETE FROM analytics_events
  WHERE created_at < now() - INTERVAL '90 days';

  -- Silinen satir sayisini logla
  RAISE NOTICE 'Analytics cleanup: % rows deleted', (SELECT count(*) FROM analytics_events WHERE created_at < now() - INTERVAL '90 days');
END;
$$;

-- ═══════════════════════════════════════════════════════════
-- 5. CRON JOB (Supabase pg_cron varsa)
-- Her gece 03:00'te eski kayitlari temizle
-- ═══════════════════════════════════════════════════════════
-- NOT: pg_cron Supabase Pro planinda kullanilabilir
-- Yoksa n8n/Cloud Function ile ayni isi yapabilirsin

-- Asagidaki satiri Supabase SQL Editor'de calistir (pg_cron aktifse):
-- SELECT cron.schedule(
--   'cleanup-analytics',
--   '0 3 * * *',
--   $$ SELECT cleanup_old_analytics(); $$
-- );

-- ═══════════════════════════════════════════════════════════
-- 6. PARTITION DEGERLENDIRMESI
-- ═══════════════════════════════════════════════════════════
-- Partition (aylik/haftalik) su durumlarda gerekli:
--   - Gunluk 100K+ event olusuyor
--   - Tablo 10M+ satira ulasti
--   - Zaman bazli sorgular yavasliyor
--
-- Koala su an erken asamada — gunluk event hacmi dusuk.
-- Index'ler + retention fonksiyonu yeterli.
-- Tablo buyudugunde (1M+ satir) partition eklenmesi dusunulur:
--
-- CREATE TABLE analytics_events_partitioned (
--   LIKE analytics_events INCLUDING ALL
-- ) PARTITION BY RANGE (created_at);
--
-- CREATE TABLE analytics_events_2026_03
--   PARTITION OF analytics_events_partitioned
--   FOR VALUES FROM ('2026-03-01') TO ('2026-04-01');
