-- ═══════════════════════════════════════════════════════════
-- 001_users.sql — Koala uygulama kullanıcıları
-- Firebase auth UID bazlı profil / rol / kredi tablosu
-- ═══════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.users (
  id TEXT PRIMARY KEY,
  email TEXT DEFAULT '',
  display_name TEXT DEFAULT '',
  photo_url TEXT DEFAULT '',
  phone TEXT DEFAULT '',
  provider TEXT DEFAULT 'google',
  role TEXT NOT NULL DEFAULT 'user' CHECK (role IN ('user', 'admin', 'designer')),
  credits INT NOT NULL DEFAULT 10 CHECK (credits >= 0),
  style_preference TEXT,
  color_preferences TEXT[] NOT NULL DEFAULT '{}',
  preferred_room TEXT,
  budget_range TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_login_at TIMESTAMPTZ,
  last_active_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_users_created_at ON public.users(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_users_last_login_at ON public.users(last_login_at DESC);
CREATE INDEX IF NOT EXISTS idx_users_role ON public.users(role);
CREATE INDEX IF NOT EXISTS idx_users_email ON public.users(email);

ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;

CREATE POLICY "users_read_own_profile"
  ON public.users FOR SELECT
  USING (auth.uid()::text = id);

CREATE POLICY "users_insert_own_profile"
  ON public.users FOR INSERT
  WITH CHECK (auth.uid()::text = id);

CREATE POLICY "users_update_own_profile"
  ON public.users FOR UPDATE
  USING (auth.uid()::text = id)
  WITH CHECK (auth.uid()::text = id);

COMMENT ON TABLE public.users IS 'Koala uygulama kullanıcıları. Firebase UID ile eşleşir.';
