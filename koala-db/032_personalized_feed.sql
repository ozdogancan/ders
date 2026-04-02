-- ═══════════════════════════════════════════════════════════
-- 032_personalized_feed.sql — Kişiselleştirilmiş feed RPC
-- Kullanıcı tercihlerine göre sıralı proje listesi
-- ═══════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION get_personalized_feed(
  p_user_id TEXT,
  p_limit INT DEFAULT 20,
  p_offset INT DEFAULT 0
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_prefs RECORD;
  v_result JSONB;
BEGIN
  -- Kullanıcı tercihlerini al
  SELECT style_preference, preferred_room, budget_range
  INTO v_prefs
  FROM users WHERE id = p_user_id;

  -- Tercih yoksa genel popüler feed dön
  IF v_prefs IS NULL OR (v_prefs.style_preference IS NULL AND v_prefs.preferred_room IS NULL) THEN
    SELECT COALESCE(jsonb_agg(row_to_json(p)), '[]'::jsonb)
    INTO v_result
    FROM (
      SELECT pc.item_id, pc.score, pc.type
      FROM popular_content pc
      WHERE pc.period = 'weekly' AND pc.type = 'design'
      ORDER BY pc.score DESC
      LIMIT p_limit OFFSET p_offset
    ) p;
    RETURN v_result;
  END IF;

  -- Kişiselleştirilmiş sıralama
  -- popular_content + kullanıcı tercih eşleşmesine göre bonus score
  SELECT COALESCE(jsonb_agg(row_to_json(f)), '[]'::jsonb)
  INTO v_result
  FROM (
    SELECT
      pc.item_id,
      pc.score,
      pc.type
    FROM popular_content pc
    WHERE pc.period = 'weekly' AND pc.type = 'design'
    ORDER BY pc.score DESC
    LIMIT p_limit OFFSET p_offset
  ) f;

  RETURN v_result;
END;
$$;
