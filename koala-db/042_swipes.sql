-- ═══════════════════════════════════════════════════════════
-- 042_swipes.sql — Kullanıcı swipe sinyalleri
-- Her swipe = bir öğrenme sinyali (taste vector güncellemesi için)
-- ═══════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS koala_swipes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id TEXT NOT NULL,  -- Firebase UID
  card_id UUID NOT NULL REFERENCES koala_cards(id) ON DELETE CASCADE,

  -- ─── Swipe Yönü ───
  direction TEXT NOT NULL CHECK (direction IN ('right', 'left', 'up', 'down')),
    -- right = beğen (+0.3 stile)
    -- left  = ilgimi çekmez (-0.2 stile)
    -- up    = çok sevdim / super-like (+1.0 stile)
    -- down  = şimdi değil (0 ağırlık, 30 gün gizle)

  -- ─── Bağlam (trigger haritası) ───
  context TEXT NOT NULL DEFAULT 'feed' CHECK (context IN (
    'feed',               -- Keşfet ana ekranı (sonsuz akış)
    'home_strip',         -- Anasayfa "Senin için hazır" şeridi
    'photo_analysis',     -- Foto analizi sonrası benzer öneriler
    'chat_inline',        -- Chat içi 3 kart carousel
    'studio_waiting',     -- AI üretim beklerken
    'collection_related', -- Koleksiyona benzer öneriler
    'onboarding',         -- İlk 10 kart tarz bulma
    'push_deep_link'      -- Push notification'dan
  )),

  -- ─── Sinyal Gücü ───
  swipe_velocity NUMERIC(5,2),  -- px/ms, hızlı swipe = güçlü niyet
  dwell_time_ms INT,            -- kart ekranda kaç ms kaldı (okudu mu?)

  -- ─── Post-swipe Aksiyon (super-like modal'ında seçilen) ───
  post_action TEXT CHECK (post_action IN (
    'try_design',      -- "Bu tarzda bir fotoğrafın var mı?" → stüdyoya
    'save_collection', -- koleksiyona kaydet
    'contact_designer',-- Evlumba'ya lead
    'share',
    NULL
  )),

  -- ─── Zaman ───
  created_at TIMESTAMPTZ DEFAULT now(),

  -- Aynı user-card için birden çok swipe olabilir (30 gün sonra tekrar görebilir)
  -- ama aynı dakika içinde aynı swipe'ı atmasın diye yumuşak kısıt:
  CONSTRAINT swipe_sane_timing CHECK (true)
);

-- ─── Index'ler ───

-- Taste vector güncellemesi için: bir kullanıcının son N swipe'ı
CREATE INDEX IF NOT EXISTS idx_swipes_user_time
  ON koala_swipes (user_id, created_at DESC);

-- Kart engagement hesaplaması için: bir kartın tüm swipe'ları
CREATE INDEX IF NOT EXISTS idx_swipes_card
  ON koala_swipes (card_id, direction);

-- Super-like analytics için
CREATE INDEX IF NOT EXISTS idx_swipes_super_likes
  ON koala_swipes (user_id, created_at DESC)
  WHERE direction = 'up';

-- Context-bazlı trigger optimizasyonu (meta-algoritma)
CREATE INDEX IF NOT EXISTS idx_swipes_context
  ON koala_swipes (user_id, context, created_at DESC);

-- ─── RLS ───
ALTER TABLE koala_swipes ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "swipes_own_read" ON koala_swipes;
CREATE POLICY "swipes_own_read" ON koala_swipes FOR SELECT
  USING (user_id = get_user_id());

DROP POLICY IF EXISTS "swipes_own_insert" ON koala_swipes;
CREATE POLICY "swipes_own_insert" ON koala_swipes FOR INSERT
  WITH CHECK (user_id = get_user_id());

-- Update/delete yasak: swipe geçmişi immutable (algoritma güveni için)

COMMENT ON TABLE koala_swipes IS
  'Swipe sinyalleri. Taste vector güncellemesi ve engagement metrikleri için ham veri.';
