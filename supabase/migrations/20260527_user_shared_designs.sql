-- ───────────────────────────────────────────────────────────────────────────
-- 20260527_user_shared_designs.sql
-- Kullanıcının "+" (Paylaş) FAB ile yüklediği IG-tarzı oda paylaşımları için
-- yeni bir tablo. Profile_tab_screen "Paylaştıklarım" sekmesinin kaynağı.
--
-- Apply manually:
--   psql $SUPABASE_DB_URL -f supabase/migrations/20260527_user_shared_designs.sql
-- veya Supabase Studio → SQL Editor.
-- ───────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.koala_user_shared_designs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id text NOT NULL,
  image_url text NOT NULL,
  thumb_url text,
  title text,
  description text,
  room_type text,
  tags text[] DEFAULT '{}',
  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending','approved','rejected','published')),
  moderation_reason text,
  created_at timestamptz DEFAULT now(),
  published_at timestamptz
);

CREATE INDEX IF NOT EXISTS idx_shared_user
  ON public.koala_user_shared_designs(user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_shared_status
  ON public.koala_user_shared_designs(status, published_at DESC)
  WHERE status = 'published';

-- RLS — kullanıcı sadece kendi paylaşımlarını okur/yazar, published olanlar
-- ise herkese görünür (keşif feed'i için).
ALTER TABLE public.koala_user_shared_designs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "shared_owner_all" ON public.koala_user_shared_designs;
CREATE POLICY "shared_owner_all"
  ON public.koala_user_shared_designs
  FOR ALL
  USING (auth.uid()::text = user_id)
  WITH CHECK (auth.uid()::text = user_id);

DROP POLICY IF EXISTS "shared_published_read" ON public.koala_user_shared_designs;
CREATE POLICY "shared_published_read"
  ON public.koala_user_shared_designs
  FOR SELECT
  USING (status = 'published');
