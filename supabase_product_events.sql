-- ═══════════════════════════════════════════════════════════
-- product_events tablosu — ürün gösterim, tıklama, kaydetme analitikleri
-- Koala Supabase DB'de çalıştır
-- ═══════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS product_events (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL,
  product_id TEXT NOT NULL,
  product_name TEXT NOT NULL DEFAULT '',
  shop_name TEXT DEFAULT '',
  price TEXT DEFAULT '',
  url TEXT DEFAULT '',
  event_type TEXT NOT NULL CHECK (event_type IN ('impression', 'click', 'save')),
  source TEXT DEFAULT '', -- 'google_search', 'evlumba', etc.
  conversation_id TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexler: hızlı sorgu için
CREATE INDEX idx_product_events_user ON product_events(user_id);
CREATE INDEX idx_product_events_type ON product_events(event_type);
CREATE INDEX idx_product_events_created ON product_events(created_at DESC);
CREATE INDEX idx_product_events_product ON product_events(product_id);
CREATE INDEX idx_product_events_shop ON product_events(shop_name);

-- RLS: Kullanıcı sadece kendi eventlerini görebilir, herkes insert yapabilir
ALTER TABLE product_events ENABLE ROW LEVEL SECURITY;

-- Authenticated kullanıcılar kendi user_id'leriyle insert yapabilir
CREATE POLICY "Users can insert own events"
  ON product_events FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = user_id);

-- Kullanıcılar sadece kendi eventlerini okuyabilir
CREATE POLICY "Users can read own events"
  ON product_events FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id);

-- ═══════════════════════════════════════════════════════════
-- Faydalı sorgular (admin için):
-- ═══════════════════════════════════════════════════════════

-- En çok tıklanan ürünler:
-- SELECT product_name, shop_name, COUNT(*) as clicks
-- FROM product_events WHERE event_type = 'click'
-- GROUP BY product_name, shop_name ORDER BY clicks DESC LIMIT 20;

-- En çok gösterilen mağazalar:
-- SELECT shop_name, COUNT(*) as impressions
-- FROM product_events WHERE event_type = 'impression'
-- GROUP BY shop_name ORDER BY impressions DESC;

-- Tıklama/gösterim oranı (CTR):
-- SELECT product_name,
--   SUM(CASE WHEN event_type = 'impression' THEN 1 ELSE 0 END) as impressions,
--   SUM(CASE WHEN event_type = 'click' THEN 1 ELSE 0 END) as clicks,
--   ROUND(SUM(CASE WHEN event_type = 'click' THEN 1 ELSE 0 END)::NUMERIC /
--     NULLIF(SUM(CASE WHEN event_type = 'impression' THEN 1 ELSE 0 END), 0) * 100, 1) as ctr
-- FROM product_events GROUP BY product_name HAVING COUNT(*) > 5
-- ORDER BY ctr DESC;
