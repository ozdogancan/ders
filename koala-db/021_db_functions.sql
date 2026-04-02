-- ═══════════════════════════════════════════════════════════
-- 021_db_functions.sql — Cron fonksiyonları (n8n RPC ile çağırır)
-- 5 fonksiyon: cleanup, popular, engagement, digest, health
-- ═══════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════
-- 1. fn_daily_cleanup() — Eski verileri temizle
-- ═══════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION fn_daily_cleanup()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_analytics INT := 0;
  v_notifications INT := 0;
  v_tokens INT := 0;
  v_queue INT := 0;
BEGIN
  -- 90 günlük analytics
  DELETE FROM analytics_events WHERE created_at < now() - interval '90 days';
  GET DIAGNOSTICS v_analytics = ROW_COUNT;

  -- 30 günlük okunmuş bildirimler
  DELETE FROM koala_notifications WHERE is_read = true AND created_at < now() - interval '30 days';
  GET DIAGNOSTICS v_notifications = ROW_COUNT;

  -- 90 gündür kullanılmayan token'ları pasifle
  UPDATE koala_push_tokens SET is_active = false, updated_at = now()
  WHERE last_used_at < now() - interval '90 days' AND is_active = true;
  GET DIAGNOSTICS v_tokens = ROW_COUNT;

  -- 7 günlük gönderilmiş/başarısız kuyruk
  DELETE FROM outbound_queue WHERE status IN ('sent', 'failed') AND processed_at < now() - interval '7 days';
  GET DIAGNOSTICS v_queue = ROW_COUNT;

  RETURN jsonb_build_object(
    'analytics_deleted', v_analytics,
    'notifications_deleted', v_notifications,
    'tokens_deactivated', v_tokens,
    'queue_cleaned', v_queue,
    'completed_at', now()
  );
END;
$$;

-- ═══════════════════════════════════════════════════════════
-- 2. fn_compute_popular() — Haftalık popüler içerik hesapla
-- ═══════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION fn_compute_popular()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Eski weekly verileri temizle
  DELETE FROM popular_content WHERE period = 'weekly';

  -- En çok kaydedilen tasarımlar
  INSERT INTO popular_content (type, item_id, score, period)
  SELECT 'design', item_id, COUNT(*) AS score, 'weekly'
  FROM saved_items
  WHERE item_type = 'design' AND created_at > now() - interval '7 days'
  GROUP BY item_id
  ORDER BY score DESC
  LIMIT 20
  ON CONFLICT (type, item_id, period) DO UPDATE SET score = EXCLUDED.score, computed_at = now();

  -- En çok mesaj alan tasarımcılar
  INSERT INTO popular_content (type, item_id, score, period)
  SELECT 'designer', designer_id, COUNT(*) AS score, 'weekly'
  FROM koala_conversations
  WHERE created_at > now() - interval '7 days' AND status = 'active'
  GROUP BY designer_id
  ORDER BY score DESC
  LIMIT 10
  ON CONFLICT (type, item_id, period) DO UPDATE SET score = EXCLUDED.score, computed_at = now();

  -- En çok kaydedilen ürünler
  INSERT INTO popular_content (type, item_id, score, period)
  SELECT 'product', item_id, COUNT(*) AS score, 'weekly'
  FROM saved_items
  WHERE item_type = 'product' AND created_at > now() - interval '7 days'
  GROUP BY item_id
  ORDER BY score DESC
  LIMIT 20
  ON CONFLICT (type, item_id, period) DO UPDATE SET score = EXCLUDED.score, computed_at = now();

  RETURN jsonb_build_object('status', 'ok', 'computed_at', now());
END;
$$;

-- ═══════════════════════════════════════════════════════════
-- 3. fn_engagement_push() — Kaydetme teşvik push'u kuyruğa ekle
-- ═══════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION fn_engagement_push()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_user RECORD;
  v_count INT := 0;
BEGIN
  FOR v_user IN
    SELECT u.id
    FROM users u
    WHERE u.last_login_at >= now() - interval '24 hours'
    AND u.id NOT IN (
      SELECT DISTINCT user_id FROM saved_items
      WHERE created_at >= now() - interval '24 hours'
    )
    -- Son 24 saatte aynı tip push gitmemişse
    AND u.id NOT IN (
      SELECT user_id FROM outbound_queue
      WHERE channel = 'fcm_push'
      AND payload->>'type' = 'engagement_save'
      AND created_at > now() - interval '24 hours'
    )
    LIMIT 15
  LOOP
    INSERT INTO outbound_queue (channel, user_id, title, body, payload, send_after)
    VALUES (
      'fcm_push', v_user.id,
      'Bugün beğendiğin tasarımları kaydetmeyi unutma! 💾',
      'Koala''da keşfettiğin tasarımları koleksiyonlarına ekle',
      '{"type": "engagement_save"}'::jsonb,
      -- Bugün 19:00'da gönder
      date_trunc('day', now()) + interval '19 hours'
    );
    v_count := v_count + 1;
  END LOOP;

  RETURN jsonb_build_object('queued', v_count);
END;
$$;

-- ═══════════════════════════════════════════════════════════
-- 4. fn_weekly_digest() — Haftalık özet email kuyruğuna ekle
-- ═══════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION fn_weekly_digest()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_user RECORD;
  v_msg_count INT;
  v_save_count INT;
  v_count INT := 0;
BEGIN
  FOR v_user IN
    SELECT id, email, display_name, last_login_at
    FROM users
    WHERE email IS NOT NULL AND email != ''
    AND last_login_at > now() - interval '30 days'
    LIMIT 20
  LOOP
    -- Son 7 gün aktivite
    SELECT COUNT(*) INTO v_msg_count
    FROM koala_direct_messages
    WHERE sender_id = v_user.id AND created_at > now() - interval '7 days';

    SELECT COUNT(*) INTO v_save_count
    FROM saved_items
    WHERE user_id = v_user.id AND created_at > now() - interval '7 days';

    IF v_msg_count > 0 OR v_save_count > 0 THEN
      -- Aktif kullanıcı → özet email
      INSERT INTO outbound_queue (channel, user_id, title, body, payload)
      VALUES (
        'email', v_user.id,
        'Haftalık Koala Özet 🐨',
        format('Bu hafta: %s mesaj, %s kayıt', v_msg_count, v_save_count),
        jsonb_build_object(
          'template', 'weekly_digest',
          'email', v_user.email,
          'display_name', COALESCE(v_user.display_name, 'Merhaba'),
          'messages', v_msg_count,
          'saves', v_save_count
        )
      );
    ELSIF v_user.last_login_at < now() - interval '7 days' THEN
      -- 7+ gün inaktif → win-back
      INSERT INTO outbound_queue (channel, user_id, title, body, payload)
      VALUES (
        'email', v_user.id,
        'Seni özledik! 🐨',
        'Koala''da seni bekleyen yeni tasarımlar var',
        jsonb_build_object(
          'template', 'winback',
          'email', v_user.email,
          'display_name', COALESCE(v_user.display_name, 'Merhaba')
        )
      );
    END IF;

    v_count := v_count + 1;
  END LOOP;

  RETURN jsonb_build_object('emails_queued', v_count);
END;
$$;

-- ═══════════════════════════════════════════════════════════
-- 5. fn_health_report() — Sistem sağlık raporu
-- ═══════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION fn_health_report()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN jsonb_build_object(
    'users', (SELECT COUNT(*) FROM users),
    'conversations', (SELECT COUNT(*) FROM koala_conversations),
    'messages', (SELECT COUNT(*) FROM koala_direct_messages),
    'saved_items', (SELECT COUNT(*) FROM saved_items),
    'notifications', (SELECT COUNT(*) FROM koala_notifications),
    'analytics', (SELECT COUNT(*) FROM analytics_events),
    'queue_pending', (SELECT COUNT(*) FROM outbound_queue WHERE status = 'pending'),
    'queue_failed', (SELECT COUNT(*) FROM outbound_queue WHERE status = 'failed'),
    'checked_at', now()
  );
END;
$$;
