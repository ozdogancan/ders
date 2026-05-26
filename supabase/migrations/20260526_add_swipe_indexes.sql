-- ═══════════════════════════════════════════════════════════════════════════
-- Swipe feed performance indexes.
--
-- Why:
--   SwipeFeedService (lib/services/swipe_feed_service.dart) drives the
--   Tarzını Keşfet card deck. It pulls candidates via:
--     1) Evlumba: designer_projects WHERE is_published ORDER BY created_at
--        DESC LIMIT 10 (with optional project_type ilike).
--     2) Koala:   koala_cards WHERE source='gemini-seed' AND is_published
--        LIMIT 300 (seed pool, fetched once per session).
--   These two paths fire on every screen-open and every refill (< 8 cards
--   left). On a 1 vCPU / 1 GB instance, plain seq scans on the seed pool
--   become noticeable as the table grows past a few thousand rows.
--
-- Apply on the KOALA DB (xgefjepaqnghaotqybpi) — the designer_projects
-- index targets Evlumba and lives in a separate Supabase project; copy
-- the second block to the Evlumba SQL editor manually.
--
-- Safe to re-run: all CREATE INDEX statements use IF NOT EXISTS.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── KOALA DB (xgefjepaqnghaotqybpi) ────────────────────────────────────────
-- Seed pool fetch: source + is_published equality + range over created_at.
CREATE INDEX IF NOT EXISTS idx_koala_cards_seed_pool
  ON public.koala_cards (source, is_published, created_at DESC)
  WHERE is_published = true;

-- Quality-aware ordering (future: order seed pool by quality_score desc).
CREATE INDEX IF NOT EXISTS idx_koala_cards_quality
  ON public.koala_cards (quality_score DESC NULLS LAST)
  WHERE is_published = true;

-- Designer feeds within Koala (designer_id, source) — used by admin tools.
CREATE INDEX IF NOT EXISTS idx_koala_cards_designer_source
  ON public.koala_cards (designer_id, source);

-- ── EVLUMBA DB (vgtgcjnrsladdharzkwn) — RUN SEPARATELY ────────────────────
-- Apply via Evlumba project's SQL editor. The Koala migration runner will
-- NOT touch the Evlumba project; this block is documentation + paste-ready.
--
-- CREATE INDEX IF NOT EXISTS idx_designer_projects_feed
--   ON public.designer_projects (is_published, project_type, created_at DESC)
--   WHERE is_published = true;
--
-- CREATE INDEX IF NOT EXISTS idx_designer_projects_published_created
--   ON public.designer_projects (is_published, created_at DESC)
--   WHERE is_published = true;
