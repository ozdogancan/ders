-- ═══════════════════════════════════════════════════════════
-- 043_seen_cards.sql — Tekrar önleme tablosu
-- "Hiçbir kart iki kez gösterilmez" kuralı bu tabloda garanti edilir
-- 90 gün sonra lockout kalkar (zevk değişebilir)
-- ═══════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS koala_seen_cards (
  user_id TEXT NOT NULL,
  card_id UUID NOT NULL REFERENCES koala_cards(id) ON DELETE CASCADE,

  -- ─── Görülme Anı ───
  first_seen_at TIMESTAMPTZ DEFAULT now(),
  last_seen_at TIMESTAMPTZ DEFAULT now(),
  impression_count INT DEFAULT 1,

  -- ─── "Şimdi değil" hariç tutma (aşağı swipe) ───
  hidden_until TIMESTAMPTZ,  -- NULL = kalıcı olarak görüldü, değer = bu tarihe kadar gizle

  -- ─── Son swipe sonucu (hızlı lookup için denormalize) ───
  last_direction TEXT CHECK (last_direction IN ('right', 'left', 'up', 'down', NULL)),

  PRIMARY KEY (user_id, card_id)
);

-- ─── Index'ler ───

-- Feed query'sinde NOT EXISTS subquery'si için kritik
CREATE INDEX IF NOT EXISTS idx_seen_user_recent
  ON koala_seen_cards (user_id, last_seen_at DESC);

-- 90 gün lockout logic'i için
CREATE INDEX IF NOT EXISTS idx_seen_hidden
  ON koala_seen_cards (user_id, hidden_until)
  WHERE hidden_until IS NOT NULL;

-- ─── 90 gün lockout temizlik fonksiyonu (cron ile çağrılır) ───
CREATE OR REPLACE FUNCTION cleanup_old_seen_cards()
RETURNS INT
LANGUAGE plpgsql
AS $$
DECLARE
  v_deleted INT;
BEGIN
  DELETE FROM koala_seen_cards
  WHERE last_seen_at < now() - interval '90 days'
    AND (hidden_until IS NULL OR hidden_until < now());

  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  RAISE NOTICE 'Cleaned up % old seen_cards entries', v_deleted;
  RETURN v_deleted;
END;
$$;

-- ─── RLS ───
ALTER TABLE koala_seen_cards ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "seen_own_all" ON koala_seen_cards;
CREATE POLICY "seen_own_all" ON koala_seen_cards FOR ALL
  USING (user_id = get_user_id())
  WITH CHECK (user_id = get_user_id());

COMMENT ON TABLE koala_seen_cards IS
  'Kart tekrarını önlemek için. 90 gün lockout, aşağı swipe ile 30 gün "şimdi değil".';
