-- ═══════════════════════════════════════════════════════════
-- 062_likes_shares.sql
-- ═══════════════════════════════════════════════════════════
-- AMAÇ:
--   Beğen (likes) + Paylaş (shares) için temel tablolar.
--   saved_items (kaydet) + collections (koleksiyon) zaten var;
--   bu migration onlarla aynı pattern'i izliyor: item_type + item_id.
--
-- ANALYTICS:
--   analytics_events tablosu 009'da var. Client taraf 'save', 'unsave',
--   'like', 'unlike', 'share', 'collection_create', 'collection_add'
--   event'lerini oraya yazacak.
-- ═══════════════════════════════════════════════════════════

-- ─── LIKES ───────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS koala_likes (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id TEXT NOT NULL,
  item_type TEXT NOT NULL CHECK (item_type IN ('design', 'designer', 'product')),
  item_id TEXT NOT NULL,
  -- Hızlı "beğenilenleri listele" için küçük metadata (title/cover/subtitle)
  title TEXT,
  image_url TEXT,
  subtitle TEXT,
  created_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(user_id, item_type, item_id)
);

CREATE INDEX IF NOT EXISTS idx_koala_likes_user
  ON koala_likes(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_koala_likes_item
  ON koala_likes(item_type, item_id);

ALTER TABLE koala_likes ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS likes_select ON koala_likes;
CREATE POLICY likes_select ON koala_likes
  FOR SELECT USING (user_id = get_user_id());

DROP POLICY IF EXISTS likes_insert ON koala_likes;
CREATE POLICY likes_insert ON koala_likes
  FOR INSERT WITH CHECK (user_id = get_user_id());

DROP POLICY IF EXISTS likes_delete ON koala_likes;
CREATE POLICY likes_delete ON koala_likes
  FOR DELETE USING (user_id = get_user_id());

-- ─── SHARES ──────────────────────────────────────────────
-- Paylaşım event log'u. Hem analytics hem de "son paylaştıklarım"
-- listesi için kullanılabilir. Channel: 'chat' | 'link' | 'system'
--   - chat   : in-app DM içinde paylaşıldı (conversation_id)
--   - link   : clipboard'a kopyalandı
--   - system : OS native share (share_plus)
CREATE TABLE IF NOT EXISTS koala_shares (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id TEXT NOT NULL,
  item_type TEXT NOT NULL CHECK (item_type IN ('design', 'designer', 'product')),
  item_id TEXT NOT NULL,
  channel TEXT NOT NULL CHECK (channel IN ('chat', 'link', 'system')),
  -- chat channel için hedef conversation/designer ref
  target_conversation_id UUID,
  target_designer_id TEXT,
  -- Frontend'in paylaştığı public URL (analytics için)
  share_url TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_koala_shares_user
  ON koala_shares(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_koala_shares_item
  ON koala_shares(item_type, item_id);

ALTER TABLE koala_shares ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS shares_select ON koala_shares;
CREATE POLICY shares_select ON koala_shares
  FOR SELECT USING (user_id = get_user_id());

DROP POLICY IF EXISTS shares_insert ON koala_shares;
CREATE POLICY shares_insert ON koala_shares
  FOR INSERT WITH CHECK (user_id = get_user_id());

-- PostgREST schema cache reload
NOTIFY pgrst, 'reload schema';
