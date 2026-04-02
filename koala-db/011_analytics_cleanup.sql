-- ═══════════════════════════════════════════════════════════
-- 011_analytics_cleanup.sql — Veri temizlik fonksiyonlari
-- n8n veya pg_cron ile periyodik calistirilir
-- ═══════════════════════════════════════════════════════════

-- 1. Analytics events temizlik (90 gunluk retention)
-- LIMIT 1000 per batch — buyuk tablolarda lock suresi kisa tutulur
CREATE OR REPLACE FUNCTION cleanup_old_analytics(batch_limit INT DEFAULT 1000)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  deleted_count INT;
BEGIN
  DELETE FROM analytics_events
  WHERE id IN (
    SELECT id FROM analytics_events
    WHERE created_at < now() - INTERVAL '90 days'
    ORDER BY created_at ASC
    LIMIT batch_limit
  );
  GET DIAGNOSTICS deleted_count = ROW_COUNT;
  RETURN deleted_count;
END;
$$;

-- 2. Okunmus bildirimler temizlik (30 gunluk retention)
CREATE OR REPLACE FUNCTION cleanup_read_notifications(batch_limit INT DEFAULT 1000)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  deleted_count INT;
BEGIN
  DELETE FROM koala_notifications
  WHERE id IN (
    SELECT id FROM koala_notifications
    WHERE is_read = true
    AND created_at < now() - INTERVAL '30 days'
    ORDER BY created_at ASC
    LIMIT batch_limit
  );
  GET DIAGNOSTICS deleted_count = ROW_COUNT;
  RETURN deleted_count;
END;
$$;

-- 3. Expired push tokens temizlik (90 gun kullanilmayan)
-- Silmez, pasifler — belki tekrar aktif olur
CREATE OR REPLACE FUNCTION cleanup_expired_tokens(days_inactive INT DEFAULT 90)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  updated_count INT;
BEGIN
  UPDATE koala_push_tokens
  SET is_active = false, updated_at = now()
  WHERE is_active = true
  AND last_used_at < now() - (days_inactive || ' days')::INTERVAL;
  GET DIAGNOSTICS updated_count = ROW_COUNT;
  RETURN updated_count;
END;
$$;
