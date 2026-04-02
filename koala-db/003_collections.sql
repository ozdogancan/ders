-- ═══════════════════════════════════════════════════════════
-- 003_collections.sql — Koleksiyonlar
-- CollectionsService tarafından kullanılır
-- ═══════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.collections (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id TEXT NOT NULL,
  name TEXT NOT NULL,
  description TEXT,
  cover_image_url TEXT,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- FK: saved_items.collection_id → collections.id
ALTER TABLE saved_items
  ADD CONSTRAINT fk_saved_items_collection
  FOREIGN KEY (collection_id) REFERENCES collections(id) ON DELETE SET NULL;

-- Index'ler
CREATE INDEX IF NOT EXISTS idx_collections_user ON collections(user_id, updated_at DESC);

-- RLS
ALTER TABLE collections ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users manage own collections" ON collections FOR ALL
  USING (auth.uid()::text = user_id)
  WITH CHECK (auth.uid()::text = user_id);
