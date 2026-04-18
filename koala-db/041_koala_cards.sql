-- ═══════════════════════════════════════════════════════════
-- 041_koala_cards.sql — Swipe feed'in ana içerik tablosu
-- Evlumba projelerinden enrichment ile üretilir
-- Her satır = 1 swipe edilebilir kart (1 görsel)
-- ═══════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS koala_cards (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- ─── Kaynak İzleme ───
  source TEXT NOT NULL DEFAULT 'evlumba',
    -- 'evlumba' | 'curated' | 'ai_generated' (ileride)
  source_project_id TEXT,        -- evlumba designer_projects.id
  source_image_id TEXT,          -- evlumba designer_project_images.id
  source_created_at TIMESTAMPTZ, -- orijinal proje oluşturma tarihi (FRESH halka için)

  -- ─── Tasarımcı Attribution ───
  designer_id TEXT,              -- evlumba profiles.id
  designer_name TEXT,
  designer_city TEXT,
  designer_rating NUMERIC(3,2),
  designer_specialty TEXT,

  -- ─── Görsel ───
  original_url TEXT NOT NULL,    -- Evlumba Supabase storage URL
  cdn_url TEXT,                  -- Vercel image optimization endpoint URL
  thumbnail_url TEXT,            -- düşük çözünürlüklü önizleme (400px)
  image_width INT,
  image_height INT,

  -- ─── İçerik Metadata ───
  title TEXT,
  description TEXT,
  room_type TEXT,
    -- 'salon' | 'yatak_odasi' | 'mutfak' | 'banyo' | 'cocuk_odasi'
    -- | 'ofis' | 'antre' | 'balkon' | 'diger'

  -- ─── AI Auto-tagging (Gemini Vision ile doldurulur) ───
  style TEXT,
    -- 'modern' | 'minimalist' | 'scandinavian' | 'industrial'
    -- | 'bohemian' | 'classic' | 'luxury' | 'japandi' | 'rustic' | 'eclectic'
  dominant_colors TEXT[] DEFAULT '{}',  -- ['#FFFFFF', '#A0826D', ...]
  mood TEXT,                             -- 'cozy' | 'airy' | 'dramatic' | 'serene' | 'vibrant'
  budget_tier TEXT,                      -- 'low' | 'mid' | 'high' | 'luxury'
  furniture_detected TEXT[] DEFAULT '{}',-- ['sofa', 'coffee_table', 'lamp', ...]

  -- ─── Kalite & Yayın Kontrolü ───
  quality_score NUMERIC(3,2) DEFAULT 0.5,  -- 0.0-1.0, Gemini Vision verir
  is_published BOOLEAN DEFAULT false,      -- feed'e dahil mi
  designer_opted_out BOOLEAN DEFAULT false,-- tasarımcı "gösterilmesin" dedi mi

  -- ─── Engagement Metrikleri (swipe'lardan agrege) ───
  total_impressions BIGINT DEFAULT 0,
  total_likes BIGINT DEFAULT 0,
  total_dislikes BIGINT DEFAULT 0,
  total_super_likes BIGINT DEFAULT 0,
  engagement_score NUMERIC(5,4) DEFAULT 0, -- likes/impressions hesaplanır
  last_engagement_recalc TIMESTAMPTZ,

  -- ─── Embedding (Vertex AI Multimodal, 1408 boyut) ───
  embedding vector(1408),

  -- ─── Zaman Damgaları ───
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),

  -- ─── Unique kısıt: aynı Evlumba görseli iki kez enrichment'a alınmasın ───
  UNIQUE (source, source_project_id, source_image_id)
);

-- ─── Index'ler ───

-- Feed query'si için en kritik index: publish + quality + room filtresi
CREATE INDEX IF NOT EXISTS idx_koala_cards_feed
  ON koala_cards (is_published, quality_score DESC)
  WHERE is_published = true AND designer_opted_out = false;

-- Room-bazlı arama (gerektiğinde)
CREATE INDEX IF NOT EXISTS idx_koala_cards_room
  ON koala_cards (room_type, is_published)
  WHERE is_published = true;

-- Stil-bazlı arama
CREATE INDEX IF NOT EXISTS idx_koala_cards_style
  ON koala_cards (style, is_published)
  WHERE is_published = true;

-- FRESH halka: son 48 saatte eklenen
CREATE INDEX IF NOT EXISTS idx_koala_cards_created
  ON koala_cards (source_created_at DESC)
  WHERE is_published = true;

-- Tasarımcı sayfası (deep-link için)
CREATE INDEX IF NOT EXISTS idx_koala_cards_designer
  ON koala_cards (designer_id)
  WHERE is_published = true;

-- Vector similarity (HNSW, cosine distance)
-- HNSW daha hızlı ama index oluşturma yavaş; ivfflat başlangıçta yeterli
-- 150 kart için herhangi bir index gerekmez, 10K+ için açarız:
-- CREATE INDEX ON koala_cards USING hnsw (embedding vector_cosine_ops);

-- ─── updated_at trigger ───
CREATE OR REPLACE FUNCTION update_koala_cards_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_koala_cards_updated_at ON koala_cards;
CREATE TRIGGER trg_koala_cards_updated_at
  BEFORE UPDATE ON koala_cards
  FOR EACH ROW EXECUTE FUNCTION update_koala_cards_updated_at();

-- ─── RLS: public read (yayında olanlar), service_role write ───
ALTER TABLE koala_cards ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "cards_public_read" ON koala_cards;
CREATE POLICY "cards_public_read" ON koala_cards FOR SELECT
  USING (is_published = true AND designer_opted_out = false);

-- Sync worker (service_role) bütün insert/update/delete yapabilir.
-- Client (anon) yazma yetkisi YOK — sadece API üzerinden.

COMMENT ON TABLE koala_cards IS
  'Swipe feed''in ana içerik tablosu. Evlumba projelerinden enrichment pipeline ile doldurulur.';
