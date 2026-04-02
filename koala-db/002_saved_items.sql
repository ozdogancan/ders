-- ═══════════════════════════════════════════════════════════
-- 002_saved_items.sql — Kaydedilen öğeler
-- SavedItemsService tarafından kullanılır
-- ═══════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.saved_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id TEXT NOT NULL,
  item_type TEXT NOT NULL CHECK (item_type IN ('design', 'designer', 'product')),
  item_id TEXT NOT NULL,
  title TEXT,
  image_url TEXT,
  subtitle TEXT,
  extra_data JSONB,
  collection_id UUID,                     -- FK 003_collections'tan sonra eklenecek
  created_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(user_id, item_type, item_id)
);

-- Index'ler
CREATE INDEX IF NOT EXISTS idx_saved_user_type ON saved_items(user_id, item_type, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_saved_collection ON saved_items(collection_id) WHERE collection_id IS NOT NULL;

-- RLS
ALTER TABLE saved_items ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users manage own saved items" ON saved_items FOR ALL
  USING (auth.uid()::text = user_id)
  WITH CHECK (auth.uid()::text = user_id);
