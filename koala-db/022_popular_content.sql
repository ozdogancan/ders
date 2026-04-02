-- ═══════════════════════════════════════════════════════════
-- 022_popular_content.sql — Onceden hesaplanmis populer icerik
-- fn_compute_popular() tarafindan guncellenir
-- ═══════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.popular_content (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  type TEXT NOT NULL CHECK (type IN ('design', 'designer', 'product')),
  item_id TEXT NOT NULL,
  score INT NOT NULL DEFAULT 0,
  period TEXT NOT NULL DEFAULT 'weekly' CHECK (period IN ('daily', 'weekly', 'monthly')),
  computed_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX idx_popular_unique ON popular_content(type, item_id, period);
CREATE INDEX idx_popular_ranking ON popular_content(type, period, score DESC);

ALTER TABLE public.popular_content ENABLE ROW LEVEL SECURITY;

-- Herkes okuyabilir (public veri)
CREATE POLICY "popular_read_all" ON public.popular_content FOR SELECT USING (true);

COMMENT ON TABLE public.popular_content IS 'Onceden hesaplanmis populer icerik. fn_compute_popular() tarafindan guncellenir.';
