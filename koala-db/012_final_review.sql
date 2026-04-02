-- ═══════════════════════════════════════════════════════════
-- 012_final_review.sql — Son DB review ve index optimizasyonu
-- ═══════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════
-- TABLO ENVANTERI — Tum Koala tablolari
-- ═══════════════════════════════════════════════════════════
--
-- Tablo                    | Index Sayisi | RLS | FK | ON DELETE  | Kaynak
-- ─────────────────────────|──────────────|─────|────|───────────|────────
-- koala_styles             | 1            | ✅  | -  | -         | schema.sql + 008
-- koala_products           | 3            | ✅  | ✅ | -         | schema.sql + 008
-- koala_designers          | 2            | ✅  | -  | -         | schema.sql + 008
-- koala_inspirations       | 3            | ✅  | ✅ | -         | schema.sql + 008
-- koala_tips               | 1            | ✅  | -  | -         | schema.sql + 008
-- koala_user_prefs         | 1 (UNIQUE)   | ✅  | -  | -         | schema.sql + 008
-- koala_chats              | 1            | ✅  | -  | -         | schema.sql + 008
-- koala_messages           | 1            | ✅  | ✅ | CASCADE   | schema.sql + 008
-- koala_conversations      | 3            | ✅  | -  | -         | 004
-- koala_direct_messages    | 2            | ✅  | ✅ | CASCADE   | 004
-- koala_notifications      | 2            | ✅  | -  | -         | 005
-- koala_push_tokens        | 2            | ✅  | -  | -         | 006
-- koala_admin_logs         | 3            | ✅  | -  | -         | 007
-- analytics_events         | 5            | ✅  | -  | -         | 009
-- storage: message-images  | -            | ✅  | -  | -         | 010
-- ═══════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════
-- EKSİK COMPOSITE INDEX'LER
-- ═══════════════════════════════════════════════════════════

-- koala_direct_messages: read_at null filtresi (markAsRead sorgusu)
CREATE INDEX IF NOT EXISTS idx_dm_unread
  ON koala_direct_messages(conversation_id, sender_id)
  WHERE read_at IS NULL;

-- koala_notifications: user + unread filtresi (badge sorgusu)
-- Zaten 005'te var: idx_notifications_unread — OK

-- analytics_events: event_name + platform combo (admin analytics screen)
CREATE INDEX IF NOT EXISTS idx_analytics_name_platform
  ON analytics_events(event_name, platform, created_at DESC);

-- ═══════════════════════════════════════════════════════════
-- FK ON DELETE DAVRANIŞLARI — REVIEW
-- ═══════════════════════════════════════════════════════════
-- ✅ koala_messages.chat_id → koala_chats(id) ON DELETE CASCADE
--    → Chat silinince mesajlar da silinir — DOGRU
--
-- ✅ koala_direct_messages.conversation_id → koala_conversations(id) ON DELETE CASCADE
--    → Conversation silinince DM'ler de silinir — DOGRU
--
-- ✅ koala_products.style_id → koala_styles(id) — default NO ACTION
--    → Stil silinirse urun orphan olur — OK (stil silme nadir)
--
-- ✅ koala_inspirations.style_id → koala_styles(id) — default NO ACTION
--    → Ayni mantik — OK
--
-- ⚠️ user_id alanlari TEXT (Firebase UID) — FK yok
--    → Beklenen davranis. Firebase Auth master, Supabase slave.
--    → Kullanici silme: Firebase'den silince Supabase'de orphan kalir
--    → Cozum: cleanup_orphan_users() fonksiyonu yazilabilir (gelecek)

-- ═══════════════════════════════════════════════════════════
-- KULLANIMAYAN INDEX KONTROLU
-- ═══════════════════════════════════════════════════════════
-- Asagidaki sorgu ile production'da kontrol et:
-- SELECT schemaname, relname, indexrelname, idx_scan
-- FROM pg_stat_user_indexes
-- WHERE idx_scan = 0 AND schemaname = 'public'
-- ORDER BY pg_relation_size(indexrelid) DESC;
--
-- idx_scan = 0 olan index'ler kullanilmiyor demek.
-- Ama yeni index'ler icin en az 2 hafta bekle.

-- ═══════════════════════════════════════════════════════════
-- VACUUM ANALYZE ONERISI
-- ═══════════════════════════════════════════════════════════
-- Supabase auto-vacuum yapar ama buyuk delete batch'lerinden sonra
-- manuel VACUUM faydali olabilir:
--
-- VACUUM ANALYZE analytics_events;
-- VACUUM ANALYZE koala_notifications;
-- VACUUM ANALYZE koala_direct_messages;
--
-- NOT: Supabase free tier'da VACUUM FULL yapilamaz, sadece regular VACUUM.
