-- ═══════════════════════════════════════════════════════════
-- 017_connection_settings.sql — Performans ve guvenlik ayarlari
-- NOT: Bazilari Supabase managed instance'ta Dashboard'dan yapilir
-- ═══════════════════════════════════════════════════════════

-- 1. Statement timeout — 10 saniyeden uzun sorguları kes
-- ⚠️ Supabase'de bu ayar Dashboard > Database Settings'ten yapılır
-- ALTER DATABASE postgres SET statement_timeout = '10s';

-- 2. Idle transaction timeout — 30 saniye bekleyen transaction'ları kapat
-- ⚠️ Dashboard'dan yapılır
-- ALTER DATABASE postgres SET idle_in_transaction_session_timeout = '30s';

-- 3. Slow query log — 1 saniyeden uzun sorguları logla
-- ⚠️ Dashboard > Database Settings > log_min_duration_statement
-- ALTER DATABASE postgres SET log_min_duration_statement = 1000;

-- 4. Memory ayarları (referans — Supabase yönetir)
-- shared_buffers = 256MB (Supabase otomatik)
-- work_mem = 4MB (default yeterli, küçük sunucu için)
-- maintenance_work_mem = 64MB (VACUUM/INDEX oluşturma için)

-- ═══════════════════════════════════════════════════════════
-- ÖNERİLEN DASHBOARD AYARLARI
-- ═══════════════════════════════════════════════════════════
-- Supabase Dashboard > Project Settings > Database:
--
-- statement_timeout: 10000 (10s)
-- idle_in_transaction_session_timeout: 30000 (30s)
-- log_min_duration_statement: 1000 (1s — slow query logları)
--
-- Connection Pooling (Supavisor):
-- Pool mode: Transaction (önerilen)
-- Pool size: Free tier default yeterli
--
-- ═══════════════════════════════════════════════════════════
-- FLUTTER TARAFINDA TIMEOUT
-- ═══════════════════════════════════════════════════════════
-- http client timeout zaten 30s default.
-- Supabase Flutter SDK internal timeout kullanır.
-- Ekstra timeout lib'e gerek yok.
