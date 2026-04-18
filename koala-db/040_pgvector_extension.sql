-- ═══════════════════════════════════════════════════════════
-- 040_pgvector_extension.sql — pgvector kurulumu
-- Vertex AI Multimodal Embedding vektörleri için (1408 boyut)
-- ═══════════════════════════════════════════════════════════

-- pgvector extension'ı etkinleştir (Supabase'de hazır gelir, sadece aktifleştirme)
CREATE EXTENSION IF NOT EXISTS vector;

-- Versiyon kontrol: en az 0.5.0 olmalı (HNSW index için)
DO $$
DECLARE
  v_version TEXT;
BEGIN
  SELECT extversion INTO v_version FROM pg_extension WHERE extname = 'vector';
  RAISE NOTICE 'pgvector version: %', v_version;
END $$;
