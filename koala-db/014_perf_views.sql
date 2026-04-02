-- ═══════════════════════════════════════════════════════════
-- 014_perf_views.sql — Performans view'ları
-- N+1 query yerine tek sorgu ile istatistik
-- ═══════════════════════════════════════════════════════════

-- 1. User stats materialized view
CREATE MATERIALIZED VIEW IF NOT EXISTS user_stats AS
SELECT
  u.id AS user_id,
  COALESCE((SELECT COUNT(*) FROM saved_items si WHERE si.user_id = u.id), 0) AS saved_count,
  COALESCE((SELECT COUNT(*) FROM koala_conversations c WHERE c.user_id = u.id), 0) AS conversation_count,
  COALESCE((SELECT COUNT(*) FROM koala_direct_messages m WHERE m.sender_id = u.id), 0) AS message_count,
  COALESCE((SELECT COUNT(*) FROM collections c WHERE c.user_id = u.id), 0) AS collection_count
FROM users u;

CREATE UNIQUE INDEX IF NOT EXISTS idx_user_stats_user ON user_stats(user_id);

-- Refresh fonksiyonu (n8n veya pg_cron ile her 15dk cagir)
CREATE OR REPLACE FUNCTION refresh_user_stats()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  REFRESH MATERIALIZED VIEW CONCURRENTLY user_stats;
END;
$$;

-- 2. Popular designers view (son 30 gun en cok mesaj alan)
CREATE OR REPLACE VIEW popular_designers AS
SELECT
  designer_id,
  COUNT(*) AS message_count,
  COUNT(DISTINCT user_id) AS unique_users
FROM koala_conversations
WHERE created_at > now() - INTERVAL '30 days'
AND status = 'active'
GROUP BY designer_id
ORDER BY message_count DESC
LIMIT 50;
