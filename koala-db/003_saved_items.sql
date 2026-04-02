-- ═══════════════════════════════════════════════════════════
-- 003_saved_items.sql — Kaydedilen tasarım / ürün / tasarımcı öğeleri
-- ═══════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.saved_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id TEXT NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  item_type TEXT NOT NULL CHECK (item_type IN ('design', 'designer', 'product')),
  item_id TEXT NOT NULL,
  title TEXT,
  image_url TEXT,
  subtitle TEXT,
  extra_data JSONB NOT NULL DEFAULT '{}'::jsonb,
  collection_id UUID REFERENCES public.collections(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(user_id, item_type, item_id)
);

CREATE INDEX IF NOT EXISTS idx_saved_items_user ON public.saved_items(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_saved_items_collection ON public.saved_items(collection_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_saved_items_type ON public.saved_items(item_type, created_at DESC);

ALTER TABLE public.saved_items ENABLE ROW LEVEL SECURITY;

CREATE POLICY "saved_items_manage_own"
  ON public.saved_items FOR ALL
  USING (auth.uid()::text = user_id)
  WITH CHECK (auth.uid()::text = user_id);

COMMENT ON TABLE public.saved_items IS 'Kullanıcıların kaydettiği tasarım, tasarımcı ve ürün öğeleri.';
