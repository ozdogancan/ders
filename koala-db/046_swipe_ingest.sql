-- ═══════════════════════════════════════════════════════════
-- 046_swipe_ingest.sql — Swipe sinyal alım fonksiyonu
-- Client: POST /api/swipe → bu RPC → her şey atomik
-- 1) Swipe kaydı yarat
-- 2) Kart engagement sayaçlarını güncelle
-- 3) User taste vector'ü EWMA ile güncelle
-- 4) Aşağı swipe ise 30 gün gizle
-- ═══════════════════════════════════════════════════════════

-- ─── Yardımcı: vector EWMA (pgvector'da scalar*vector operatörü yok) ───
-- EWMA: new = alpha * new + (1-alpha) * old
-- Arrays'e dönüştürüp element-wise çarp, vector'e geri döndür
CREATE OR REPLACE FUNCTION ewma_vector(
  p_old vector,
  p_new vector,
  p_alpha REAL
)
RETURNS vector
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_old_arr REAL[];
  v_new_arr REAL[];
  v_result REAL[];
  v_dim INT;
  i INT;
BEGIN
  IF p_old IS NULL THEN RETURN p_new; END IF;
  IF p_new IS NULL THEN RETURN p_old; END IF;

  v_old_arr := p_old::REAL[];
  v_new_arr := p_new::REAL[];
  v_dim := array_length(v_old_arr, 1);

  v_result := ARRAY[]::REAL[];
  FOR i IN 1..v_dim LOOP
    v_result := array_append(v_result,
      p_alpha * v_new_arr[i] + (1 - p_alpha) * v_old_arr[i]
    );
  END LOOP;

  RETURN v_result::vector;
END;
$$;

-- ─── Yardımcı: vector - (alpha * vector) negatif sinyal için ───
-- old - alpha * card
CREATE OR REPLACE FUNCTION subtract_scaled_vector(
  p_base vector,
  p_subtract vector,
  p_alpha REAL
)
RETURNS vector
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_base_arr REAL[];
  v_sub_arr REAL[];
  v_result REAL[];
  v_dim INT;
  i INT;
BEGIN
  IF p_base IS NULL THEN RETURN NULL; END IF;
  IF p_subtract IS NULL THEN RETURN p_base; END IF;

  v_base_arr := p_base::REAL[];
  v_sub_arr := p_subtract::REAL[];
  v_dim := array_length(v_base_arr, 1);

  v_result := ARRAY[]::REAL[];
  FOR i IN 1..v_dim LOOP
    v_result := array_append(v_result,
      v_base_arr[i] - p_alpha * v_sub_arr[i]
    );
  END LOOP;

  RETURN v_result::vector;
END;
$$;

CREATE OR REPLACE FUNCTION ingest_swipe(
  p_user_id TEXT,
  p_card_id UUID,
  p_direction TEXT,
  p_context TEXT DEFAULT 'feed',
  p_swipe_velocity NUMERIC DEFAULT NULL,
  p_dwell_time_ms INT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_card RECORD;
  v_existing_embedding vector(1408);
  v_card_embedding vector(1408);
  v_weight NUMERIC;
  v_velocity_multiplier NUMERIC := 1.0;
  v_style_affinity JSONB;
  v_color_affinity JSONB;
  v_mood_affinity JSONB;
  v_budget_affinity JSONB;
  v_room_affinity JSONB;
  v_learning_alpha NUMERIC;
  v_total_swipes INT;
  v_result JSONB;
BEGIN
  -- ─── Doğrulama ───
  IF p_direction NOT IN ('right', 'left', 'up', 'down') THEN
    RAISE EXCEPTION 'Invalid direction: %', p_direction;
  END IF;

  -- Kartı çek
  SELECT id, embedding, style, dominant_colors, mood, budget_tier, room_type
  INTO v_card
  FROM koala_cards
  WHERE id = p_card_id AND is_published = true;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Card not found or not published: %', p_card_id;
  END IF;

  v_card_embedding := v_card.embedding;

  -- ─── 1) Swipe kaydı ───
  INSERT INTO koala_swipes (
    user_id, card_id, direction, context,
    swipe_velocity, dwell_time_ms
  ) VALUES (
    p_user_id, p_card_id, p_direction, p_context,
    p_swipe_velocity, p_dwell_time_ms
  );

  -- ─── 2) Kart engagement sayaçları ───
  UPDATE koala_cards
  SET
    total_likes = total_likes + CASE WHEN p_direction = 'right' THEN 1 ELSE 0 END,
    total_dislikes = total_dislikes + CASE WHEN p_direction = 'left' THEN 1 ELSE 0 END,
    total_super_likes = total_super_likes + CASE WHEN p_direction = 'up' THEN 1 ELSE 0 END,
    engagement_score = CASE
      WHEN total_impressions > 0 THEN
        ((total_likes + CASE WHEN p_direction = 'right' THEN 1 ELSE 0 END)
         + 3 * (total_super_likes + CASE WHEN p_direction = 'up' THEN 1 ELSE 0 END))::NUMERIC
        / GREATEST(total_impressions, 1)
      ELSE 0
    END,
    last_engagement_recalc = now()
  WHERE id = p_card_id;

  -- ─── 3) Aşağı swipe özel: 30 gün gizle, taste etkilemez ───
  IF p_direction = 'down' THEN
    UPDATE koala_seen_cards
    SET hidden_until = now() + interval '30 days',
        last_direction = p_direction
    WHERE user_id = p_user_id AND card_id = p_card_id;

    RETURN jsonb_build_object('status', 'hidden_30d');
  END IF;

  -- ─── 4) Sinyal ağırlığı ───
  -- right = +0.3, left = -0.2, up = +1.0
  v_weight := CASE p_direction
    WHEN 'right' THEN 0.3
    WHEN 'left'  THEN -0.2
    WHEN 'up'    THEN 1.0
  END;

  -- Velocity multiplier: hızlı swipe = daha güçlü sinyal
  IF p_swipe_velocity IS NOT NULL AND p_swipe_velocity > 0 THEN
    v_velocity_multiplier := LEAST(1.5, GREATEST(0.7, p_swipe_velocity / 1000.0));
  END IF;

  v_weight := v_weight * v_velocity_multiplier;

  -- Dwell time bonus: kullanıcı kartta 3sn+ kaldıysa sinyal güçlenir
  IF p_dwell_time_ms IS NOT NULL AND p_dwell_time_ms > 3000 THEN
    v_weight := v_weight * 1.2;
  END IF;

  -- ─── 5) Taste vector upsert (EWMA) ───
  -- EWMA formula: new_vec = alpha * card_vec + (1-alpha) * old_vec
  -- Cold start'ta alpha büyük (hızlı öğren), mature'da küçük (kararlı)

  SELECT embedding, total_swipes
  INTO v_existing_embedding, v_total_swipes
  FROM koala_user_taste
  WHERE user_id = p_user_id;

  -- Alpha: ilk 20 swipe'da 0.3, sonra 0.1 (yavaş-güvenli öğrenme)
  v_learning_alpha := CASE
    WHEN v_total_swipes IS NULL OR v_total_swipes < 20 THEN 0.3
    WHEN v_total_swipes < 100 THEN 0.15
    ELSE 0.08
  END;

  -- Negatif sinyal (sola swipe) için alpha yarıya indirilir
  -- (hızlı nefret lerken echo chamber yaratma riski)
  IF p_direction = 'left' THEN
    v_learning_alpha := v_learning_alpha * 0.5;
  END IF;

  -- ─── 6) Insert or update user_taste ───
  INSERT INTO koala_user_taste (
    user_id, embedding,
    total_swipes, total_likes, total_dislikes, total_super_likes,
    style_affinity, color_affinity, mood_affinity,
    budget_affinity, room_affinity
  ) VALUES (
    p_user_id,
    CASE
      WHEN v_card_embedding IS NOT NULL AND v_weight > 0
      THEN v_card_embedding
      ELSE NULL
    END,
    1,
    CASE WHEN p_direction = 'right' THEN 1 ELSE 0 END,
    CASE WHEN p_direction = 'left' THEN 1 ELSE 0 END,
    CASE WHEN p_direction = 'up' THEN 1 ELSE 0 END,
    jsonb_build_object(COALESCE(v_card.style, 'unknown'), v_weight),
    CASE
      WHEN array_length(v_card.dominant_colors, 1) > 0 THEN
        (SELECT jsonb_object_agg(c, v_weight) FROM unnest(v_card.dominant_colors) c)
      ELSE '{}'::jsonb
    END,
    jsonb_build_object(COALESCE(v_card.mood, 'unknown'), v_weight),
    jsonb_build_object(COALESCE(v_card.budget_tier, 'unknown'), v_weight),
    jsonb_build_object(COALESCE(v_card.room_type, 'unknown'), v_weight)
  )
  ON CONFLICT (user_id) DO UPDATE SET
    -- EWMA vector update (sadece pozitif sinyalde embedding'e dokun)
    embedding = CASE
      WHEN v_card_embedding IS NOT NULL AND v_weight > 0 THEN
        ewma_vector(koala_user_taste.embedding, v_card_embedding, v_learning_alpha::REAL)
      WHEN v_card_embedding IS NOT NULL AND v_weight < 0 AND koala_user_taste.embedding IS NOT NULL THEN
        -- Negatif sinyal: vektörden biraz uzaklaş (ama hafif)
        subtract_scaled_vector(koala_user_taste.embedding, v_card_embedding, (v_learning_alpha * 0.5)::REAL)
      ELSE koala_user_taste.embedding
    END,

    total_swipes = koala_user_taste.total_swipes + 1,
    total_likes = koala_user_taste.total_likes
      + CASE WHEN p_direction = 'right' THEN 1 ELSE 0 END,
    total_dislikes = koala_user_taste.total_dislikes
      + CASE WHEN p_direction = 'left' THEN 1 ELSE 0 END,
    total_super_likes = koala_user_taste.total_super_likes
      + CASE WHEN p_direction = 'up' THEN 1 ELSE 0 END,

    -- Affinity EWMA update (her kategori için)
    style_affinity = update_affinity_ewma(
      koala_user_taste.style_affinity,
      COALESCE(v_card.style, 'unknown'),
      v_weight,
      v_learning_alpha
    ),
    color_affinity = (
      SELECT update_affinity_ewma_multi(
        koala_user_taste.color_affinity,
        v_card.dominant_colors,
        v_weight,
        v_learning_alpha
      )
    ),
    mood_affinity = update_affinity_ewma(
      koala_user_taste.mood_affinity,
      COALESCE(v_card.mood, 'unknown'),
      v_weight,
      v_learning_alpha
    ),
    budget_affinity = update_affinity_ewma(
      koala_user_taste.budget_affinity,
      COALESCE(v_card.budget_tier, 'unknown'),
      v_weight,
      v_learning_alpha
    ),
    room_affinity = update_affinity_ewma(
      koala_user_taste.room_affinity,
      COALESCE(v_card.room_type, 'unknown'),
      v_weight,
      v_learning_alpha
    ),

    updated_at = now();

  -- ─── 7) seen_cards'da last_direction güncelle ───
  INSERT INTO koala_seen_cards (user_id, card_id, first_seen_at, last_seen_at, last_direction)
  VALUES (p_user_id, p_card_id, now(), now(), p_direction)
  ON CONFLICT (user_id, card_id) DO UPDATE
    SET last_seen_at = now(),
        last_direction = p_direction;

  v_result := jsonb_build_object(
    'status', 'ok',
    'direction', p_direction,
    'weight', v_weight,
    'is_super_like', p_direction = 'up'
  );

  RETURN v_result;
END;
$$;

-- ─── Yardımcı: tek değerli affinity EWMA ───
CREATE OR REPLACE FUNCTION update_affinity_ewma(
  p_affinity JSONB,
  p_key TEXT,
  p_weight NUMERIC,
  p_alpha NUMERIC
)
RETURNS JSONB
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_current NUMERIC;
  v_new NUMERIC;
BEGIN
  IF p_key IS NULL OR p_key = 'unknown' THEN
    RETURN p_affinity;
  END IF;

  v_current := COALESCE((p_affinity->>p_key)::NUMERIC, 0);
  v_new := p_alpha * p_weight + (1 - p_alpha) * v_current;

  RETURN p_affinity || jsonb_build_object(p_key, v_new);
END;
$$;

-- ─── Yardımcı: çoklu değer (color array) EWMA ───
CREATE OR REPLACE FUNCTION update_affinity_ewma_multi(
  p_affinity JSONB,
  p_keys TEXT[],
  p_weight NUMERIC,
  p_alpha NUMERIC
)
RETURNS JSONB
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_result JSONB := COALESCE(p_affinity, '{}'::jsonb);
  v_key TEXT;
BEGIN
  IF p_keys IS NULL OR array_length(p_keys, 1) IS NULL THEN
    RETURN v_result;
  END IF;

  FOREACH v_key IN ARRAY p_keys LOOP
    v_result := update_affinity_ewma(v_result, v_key, p_weight, p_alpha);
  END LOOP;

  RETURN v_result;
END;
$$;

COMMENT ON FUNCTION ingest_swipe IS
  'Atomik swipe sinyali alımı: swipe kaydı + kart sayaç + user taste EWMA update.';
