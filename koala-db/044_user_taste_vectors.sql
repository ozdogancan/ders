-- ═══════════════════════════════════════════════════════════
-- 044_user_taste_vectors.sql — Kullanıcı kalıcı tarz profili
-- Her swipe bu vektörü evrimleştirir (EWMA — Exponential Moving Average)
-- AI prompt enjeksiyonu için tek kaynak
-- ═══════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS koala_user_taste (
  user_id TEXT PRIMARY KEY,  -- Firebase UID

  -- ─── Vektör Tarz Temsili ───
  -- Beğenilen kartların embedding'lerinin ağırlıklı ortalaması
  -- Feed'de "exploit" halkası bu vektöre göre cosine similarity ile seçer
  embedding vector(1408),

  -- ─── Kategorik Tarz Afiniteleri (explain + fallback için) ───
  -- {"modern": 0.34, "scandinavian": 0.28, "japandi": 0.18, ...}
  style_affinity JSONB DEFAULT '{}'::jsonb,

  -- {"#A0826D": 0.4, "#FFFFFF": 0.3, ...} — hex kodları
  color_affinity JSONB DEFAULT '{}'::jsonb,

  -- {"cozy": 0.5, "airy": 0.3, ...}
  mood_affinity JSONB DEFAULT '{}'::jsonb,

  -- {"low": 0.1, "mid": 0.6, "high": 0.3, "luxury": 0.0}
  budget_affinity JSONB DEFAULT '{}'::jsonb,

  -- {"salon": 0.45, "yatak_odasi": 0.3, ...}
  room_affinity JSONB DEFAULT '{}'::jsonb,

  -- ─── Sayaçlar ───
  total_swipes INT DEFAULT 0,
  total_likes INT DEFAULT 0,
  total_dislikes INT DEFAULT 0,
  total_super_likes INT DEFAULT 0,
  total_skips INT DEFAULT 0,  -- aşağı swipe

  -- ─── Öğrenme Aşaması ───
  -- 'cold_start' (<20 swipe): broad explore ağırlıklı
  -- 'warming' (20-100): kısmi algoritma
  -- 'mature' (100+): tam algoritma
  learning_stage TEXT DEFAULT 'cold_start' CHECK (
    learning_stage IN ('cold_start', 'warming', 'mature')
  ),

  -- ─── Trigger Suppression (meta-algoritma) ───
  -- Hangi context'te kullanıcı art arda kaç kez ignore etti
  -- {"photo_analysis": 3, "chat_inline": 1}
  -- >= 3 olursa o trigger o kullanıcı için "susar"
  trigger_ignore_counts JSONB DEFAULT '{}'::jsonb,

  -- ─── Push Frekans Kontrolü ───
  push_frequency_days INT DEFAULT 3,  -- varsayılan 3 günde bir
  last_push_sent_at TIMESTAMPTZ,

  -- ─── Stil DNA görünürlüğü ───
  -- 50+ swipe sonrası profil ekranında açılır
  style_dna_unlocked BOOLEAN GENERATED ALWAYS AS (total_swipes >= 50) STORED,

  -- ─── Zaman ───
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- ─── Index'ler ───

-- Benzer zevkli kullanıcıları bulmak (collaborative filtering ileride)
-- CREATE INDEX ON koala_user_taste USING hnsw (embedding vector_cosine_ops);

-- ─── updated_at trigger ───
CREATE OR REPLACE FUNCTION update_user_taste_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_user_taste_updated_at ON koala_user_taste;
CREATE TRIGGER trg_user_taste_updated_at
  BEFORE UPDATE ON koala_user_taste
  FOR EACH ROW EXECUTE FUNCTION update_user_taste_updated_at();

-- ─── learning_stage otomatik güncelleme trigger'ı ───
CREATE OR REPLACE FUNCTION update_learning_stage()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.total_swipes >= 100 THEN
    NEW.learning_stage = 'mature';
  ELSIF NEW.total_swipes >= 20 THEN
    NEW.learning_stage = 'warming';
  ELSE
    NEW.learning_stage = 'cold_start';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_update_learning_stage ON koala_user_taste;
CREATE TRIGGER trg_update_learning_stage
  BEFORE INSERT OR UPDATE OF total_swipes ON koala_user_taste
  FOR EACH ROW EXECUTE FUNCTION update_learning_stage();

-- ─── RLS ───
ALTER TABLE koala_user_taste ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "taste_own_read" ON koala_user_taste;
CREATE POLICY "taste_own_read" ON koala_user_taste FOR SELECT
  USING (user_id = get_user_id());

DROP POLICY IF EXISTS "taste_own_insert" ON koala_user_taste;
CREATE POLICY "taste_own_insert" ON koala_user_taste FOR INSERT
  WITH CHECK (user_id = get_user_id());

DROP POLICY IF EXISTS "taste_own_update" ON koala_user_taste;
CREATE POLICY "taste_own_update" ON koala_user_taste FOR UPDATE
  USING (user_id = get_user_id())
  WITH CHECK (user_id = get_user_id());

COMMENT ON TABLE koala_user_taste IS
  'Kullanıcı kalıcı tarz profili. EWMA ile her swipe günceller. AI prompt enjeksiyonunun kaynağı.';
