# Koala Swipe Sistemi — Kurulum

Bu klasördeki `040_` ile başlayan migration'lar akıllı swipe altyapısını kurar.

## Çalıştırma Sırası

Supabase SQL Editor'de sırayla (her biri "Run"):

```
040_pgvector_extension.sql      → pgvector'u aç
041_koala_cards.sql             → kart tablosu + embedding kolonu
042_swipes.sql                  → swipe sinyal tablosu
043_seen_cards.sql              → tekrar önleme tablosu
044_user_taste_vectors.sql      → kullanıcı tarz profili
045_feed_algorithm.sql          → get_swipe_feed() RPC
046_swipe_ingest.sql            → ingest_swipe() RPC + yardımcılar
```

**Toplam süre:** ~2 dakika. Her biri idempotent (tekrar çalıştırılabilir).

## Doğrulama

Her migration sonrası çalıştır:

```sql
-- Tablolar kuruldu mu?
SELECT table_name FROM information_schema.tables
WHERE table_schema = 'public' AND table_name LIKE 'koala_%'
ORDER BY table_name;

-- Beklenen:
--   koala_cards
--   koala_seen_cards
--   koala_swipes
--   koala_user_taste
--   (zaten vardı: koala_conversations, koala_direct_messages,
--                  koala_notifications, koala_push_tokens)

-- Fonksiyonlar kuruldu mu?
SELECT routine_name FROM information_schema.routines
WHERE routine_schema = 'public'
  AND routine_name IN (
    'get_swipe_feed', 'ingest_swipe',
    'update_affinity_ewma', 'update_affinity_ewma_multi',
    'cleanup_old_seen_cards'
  );

-- pgvector aktif mi?
SELECT extversion FROM pg_extension WHERE extname = 'vector';
-- Beklenen: 0.5.0+ veya 0.7.x
```

## Smoke Test (migration'lar çalıştıktan sonra)

```sql
-- 1) Feed boş dönecek (henüz kart yok) — hata olmaması yeterli
SELECT get_swipe_feed('test-user-123', 10);
-- Beklenen: []

-- 2) Fake bir kart ekle, yayına al
INSERT INTO koala_cards (
  source, source_project_id, source_image_id,
  original_url, title, room_type, style,
  quality_score, is_published
) VALUES (
  'manual', 'test-1', 'img-1',
  'https://picsum.photos/1080/1350',
  'Test Modern Salon', 'salon', 'modern',
  0.9, true
);

-- 3) Feed'i tekrar çağır, 1 kart dönmeli
SELECT get_swipe_feed('test-user-123', 10);
-- Beklenen: 1 kart JSON

-- 4) Swipe ingest
SELECT ingest_swipe(
  'test-user-123',
  (SELECT id FROM koala_cards WHERE source_project_id = 'test-1'),
  'right',
  'feed'
);
-- Beklenen: {"status": "ok", "direction": "right", "weight": 0.3, ...}

-- 5) User taste oluştu mu?
SELECT user_id, total_swipes, total_likes, style_affinity, learning_stage
FROM koala_user_taste WHERE user_id = 'test-user-123';
-- Beklenen: total_likes=1, style_affinity={"modern": 0.09}, stage='cold_start'

-- 6) Tekrar feed çağır: aynı kart dönmemeli (seen_cards ile filtrelendi)
SELECT get_swipe_feed('test-user-123', 10);
-- Beklenen: [] (tek kartı görmüştü)

-- 7) Cleanup test verisi
DELETE FROM koala_cards WHERE source = 'manual';
DELETE FROM koala_user_taste WHERE user_id = 'test-user-123';
```

## RLS Notları

- `koala_cards`: **public read** (yayında olanlar), yazım yok (service_role bypass)
- `koala_swipes`: **own read/insert** (x-user-id header ile)
- `koala_seen_cards`: **own all**
- `koala_user_taste`: **own read/insert/update**

Flutter client'tan `x-user-id` header'ı ile çağrılır (mevcut `get_user_id()` helper'ı kullanır — `030_fix_rls.sql` içinde tanımlı).

Backend sync worker (Vercel Function) ise `SUPABASE_SERVICE_ROLE_KEY` ile RLS'i bypass ederek kart insert eder.

## Sonraki Adımlar

1. **Enrichment pipeline** (Vercel Function): Evlumba → Gemini Vision + Vertex AI → `koala_cards` INSERT
2. **API endpoint'leri**: `/api/feed`, `/api/swipe` (ingest), `/api/card/:id` (detay)
3. **Flutter UI**: `SwipeScreen`, `SwipeCard`, gesture handler
4. **Trigger noktaları**: Home strip, photo analysis, chat inline

Her biri kendi sprint'inde.
