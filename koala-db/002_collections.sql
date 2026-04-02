-- ═══════════════════════════════════════════════════════════
-- 002_collections.sql — Kullanıcı koleksiyonları
-- ═══════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.collections (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id TEXT NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  description TEXT,
  cover_image_url TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_collections_user ON public.collections(user_id, updated_at DESC);

ALTER TABLE public.collections ENABLE ROW LEVEL SECURITY;

CREATE POLICY "collections_manage_own"
  ON public.collections FOR ALL
  USING (auth.uid()::text = user_id)
  WITH CHECK (auth.uid()::text = user_id);

COMMENT ON TABLE public.collections IS 'Kullanıcıların kaydettiği içerikleri gruplayan koleksiyonlar.';
