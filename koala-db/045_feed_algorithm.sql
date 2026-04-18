-- ═══════════════════════════════════════════════════════════
-- 045_feed_algorithm.sql — 4-halka feed algoritması
-- EXPLOIT %50 + EXPLORE %25 + FRESH %15 + RARE %10
-- Cold-start / warming / mature aşamalarına göre karışım değişir
-- ═══════════════════════════════════════════════════════════

-- ─── Ana fonksiyon: get_swipe_feed ───
-- Input: user_id, limit (default 30)
-- Output: JSONB array of card objects, ordered by algorithm score
CREATE OR REPLACE FUNCTION get_swipe_feed(
  p_user_id TEXT,
  p_limit INT DEFAULT 30
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_taste_vector vector(1408);
  v_stage TEXT;
  v_total_swipes INT;

  -- Halka sayıları (öğrenme aşamasına göre dinamik)
  v_exploit_count INT;
  v_explore_count INT;
  v_fresh_count INT;
  v_rare_count INT;

  v_result JSONB;
BEGIN
  -- ─── 1) Kullanıcı taste profilini al ───
  SELECT embedding, learning_stage, total_swipes
  INTO v_taste_vector, v_stage, v_total_swipes
  FROM koala_user_taste
  WHERE user_id = p_user_id;

  -- Yeni kullanıcı: taste_vector yok → cold_start
  IF v_stage IS NULL THEN
    v_stage := 'cold_start';
    v_total_swipes := 0;
  END IF;

  -- ─── 2) Öğrenme aşamasına göre halka oranları ───
  CASE v_stage
    WHEN 'cold_start' THEN
      -- %20 exploit (geniş popüler), %40 explore (random), %25 fresh, %15 rare
      v_exploit_count := (p_limit * 0.20)::INT;
      v_explore_count := (p_limit * 0.40)::INT;
      v_fresh_count   := (p_limit * 0.25)::INT;
      v_rare_count    := p_limit - v_exploit_count - v_explore_count - v_fresh_count;
    WHEN 'warming' THEN
      -- %40 exploit, %30 explore, %20 fresh, %10 rare
      v_exploit_count := (p_limit * 0.40)::INT;
      v_explore_count := (p_limit * 0.30)::INT;
      v_fresh_count   := (p_limit * 0.20)::INT;
      v_rare_count    := p_limit - v_exploit_count - v_explore_count - v_fresh_count;
    ELSE -- mature
      -- %50 exploit, %25 explore, %15 fresh, %10 rare
      v_exploit_count := (p_limit * 0.50)::INT;
      v_explore_count := (p_limit * 0.25)::INT;
      v_fresh_count   := (p_limit * 0.15)::INT;
      v_rare_count    := p_limit - v_exploit_count - v_explore_count - v_fresh_count;
  END CASE;

  -- ─── 3) 4-halka union query ───
  WITH
  -- Base: yayında, görülmemiş (90 gün), hidden_until geçmiş, opt-out değil
  eligible_cards AS (
    SELECT c.*
    FROM koala_cards c
    WHERE c.is_published = true
      AND c.designer_opted_out = false
      AND c.quality_score >= 0.5
      AND NOT EXISTS (
        SELECT 1 FROM koala_seen_cards s
        WHERE s.user_id = p_user_id
          AND s.card_id = c.id
          AND s.last_seen_at > now() - interval '90 days'
          AND (s.hidden_until IS NULL OR s.hidden_until > now())
      )
  ),

  -- ── EXPLOIT: taste vector'e en yakın kartlar ──
  exploit_ring AS (
    SELECT id, 'exploit'::TEXT AS ring,
      CASE
        WHEN v_taste_vector IS NOT NULL THEN
          1 - (embedding <=> v_taste_vector)  -- cosine similarity (1 = en yakın)
        ELSE quality_score::NUMERIC  -- cold start: quality ile sırala
      END AS score
    FROM eligible_cards
    WHERE embedding IS NOT NULL OR v_taste_vector IS NULL
    ORDER BY
      CASE
        WHEN v_taste_vector IS NOT NULL THEN embedding <=> v_taste_vector
        ELSE -quality_score
      END
    LIMIT v_exploit_count
  ),

  -- ── EXPLORE: tarz komşuları (orta mesafe) — ilk 3 ringten hariç ──
  explore_ring AS (
    SELECT id, 'explore'::TEXT AS ring,
      random() AS score  -- rastgele sıralama = çeşitlilik
    FROM eligible_cards
    WHERE id NOT IN (SELECT id FROM exploit_ring)
    ORDER BY random()
    LIMIT v_explore_count
  ),

  -- ── FRESH: son 48 saatte eklenen ──
  fresh_ring AS (
    SELECT id, 'fresh'::TEXT AS ring,
      extract(epoch FROM (now() - source_created_at))::NUMERIC AS score  -- düşük = taze
    FROM eligible_cards
    WHERE source_created_at > now() - interval '48 hours'
      AND id NOT IN (SELECT id FROM exploit_ring)
      AND id NOT IN (SELECT id FROM explore_ring)
    ORDER BY source_created_at DESC
    LIMIT v_fresh_count
  ),

  -- ── RARE: düşük impression ama yüksek engagement_score ──
  rare_ring AS (
    SELECT id, 'rare'::TEXT AS ring,
      engagement_score AS score
    FROM eligible_cards
    WHERE total_impressions < 100
      AND engagement_score > 0.3
      AND id NOT IN (SELECT id FROM exploit_ring)
      AND id NOT IN (SELECT id FROM explore_ring)
      AND id NOT IN (SELECT id FROM fresh_ring)
    ORDER BY engagement_score DESC
    LIMIT v_rare_count
  ),

  -- ── FALLBACK: yukarıdakiler toplam p_limit'i dolduramazsa random ──
  fallback_ring AS (
    SELECT id, 'fallback'::TEXT AS ring,
      random() AS score
    FROM eligible_cards
    WHERE id NOT IN (SELECT id FROM exploit_ring)
      AND id NOT IN (SELECT id FROM explore_ring)
      AND id NOT IN (SELECT id FROM fresh_ring)
      AND id NOT IN (SELECT id FROM rare_ring)
    ORDER BY random()
    LIMIT GREATEST(0, p_limit
      - (SELECT count(*) FROM exploit_ring)
      - (SELECT count(*) FROM explore_ring)
      - (SELECT count(*) FROM fresh_ring)
      - (SELECT count(*) FROM rare_ring))
  ),

  -- ── Tüm ringler'i birleştir ──
  all_rings AS (
    SELECT * FROM exploit_ring
    UNION ALL SELECT * FROM explore_ring
    UNION ALL SELECT * FROM fresh_ring
    UNION ALL SELECT * FROM rare_ring
    UNION ALL SELECT * FROM fallback_ring
  ),

  -- ── Reels-hissi interleave: her ring içinde sırala, ring'ler arası serpiştir ──
  -- Window function burada hesaplanır, aggregate içinde değil (PG kısıtı)
  interleaved AS (
    SELECT
      r.id,
      r.ring,
      (row_number() OVER (PARTITION BY r.ring ORDER BY r.score DESC)) * 100
      + CASE r.ring
          WHEN 'exploit'  THEN 0
          WHEN 'fresh'    THEN 25
          WHEN 'explore'  THEN 50
          WHEN 'rare'     THEN 75
          WHEN 'fallback' THEN 90
        END AS sort_key
    FROM all_rings r
  )

  -- ─── 4) Shuffle & return ───
  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'id', c.id,
      'source', c.source,
      'cdn_url', c.cdn_url,
      'original_url', c.original_url,
      'thumbnail_url', c.thumbnail_url,
      'image_width', c.image_width,
      'image_height', c.image_height,
      'title', c.title,
      'description', c.description,
      'room_type', c.room_type,
      'style', c.style,
      'dominant_colors', c.dominant_colors,
      'mood', c.mood,
      'budget_tier', c.budget_tier,
      'designer_id', c.designer_id,
      'designer_name', c.designer_name,
      'designer_city', c.designer_city,
      'designer_rating', c.designer_rating,
      'ring', i.ring
    )
    ORDER BY i.sort_key
  ), '[]'::jsonb)
  INTO v_result
  FROM interleaved i
  JOIN koala_cards c ON c.id = i.id;

  -- ─── 5) Impression kayıtları ───
  -- Feed dönüyorsa kartlar "görüldü" sayılır (upsert)
  INSERT INTO koala_seen_cards (user_id, card_id, first_seen_at, last_seen_at, impression_count)
  SELECT
    p_user_id,
    (elem->>'id')::uuid,
    now(),
    now(),
    1
  FROM jsonb_array_elements(v_result) AS elem
  ON CONFLICT (user_id, card_id) DO UPDATE
    SET last_seen_at = now(),
        impression_count = koala_seen_cards.impression_count + 1;

  -- Kart bazında total_impressions sayaç
  UPDATE koala_cards
  SET total_impressions = total_impressions + 1
  WHERE id IN (
    SELECT (elem->>'id')::uuid
    FROM jsonb_array_elements(v_result) AS elem
  );

  RETURN v_result;
END;
$$;

COMMENT ON FUNCTION get_swipe_feed IS
  '4-halka feed algoritması: exploit/explore/fresh/rare. Öğrenme aşamasına göre karışım değişir. Impression kayıtları otomatik.';
