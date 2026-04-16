-- ═══════════════════════════════════════════════════════════════════════════
-- 050_security_hardening.sql — Supabase DB Linter uyarılarını kapatan
-- kapsamlı güvenlik sertleştirmesi.
--
-- Kapsam:
--   A. rls_policy_always_true  → (true) policy'leri get_user_id() bazlı yap
--   B. security_definer_view   → v_swipe_metrics → security_invoker
--   C. rls_disabled_in_public  → scans tablosu için RLS aç (deny-by-default)
--   D. function_search_path_mutable → tüm fonksiyonlara SET search_path
--   E. public_bucket_allows_listing → storage.objects listeleme policy'sini sık
--
-- NOT:
--   - service_role (Next.js API) RLS bypass eder, mevcut akışlar etkilenmez.
--   - Trigger fonksiyonları SECURITY DEFINER olduğu için RLS'i aşar.
--   - Koala Firebase Auth + x-user-id header kullandığı için auth.uid() yerine
--     get_user_id() fonksiyonu kullanılıyor (030_fix_rls.sql'den).
-- ═══════════════════════════════════════════════════════════════════════════


-- ═══════════════════════════════════════════════════════════════════════════
-- A.  rls_policy_always_true fix'leri
-- ═══════════════════════════════════════════════════════════════════════════

-- ─── A1. koala_conversations ────────────────────────────────────────────────
DROP POLICY IF EXISTS "koala_conv_insert" ON koala_conversations;
DROP POLICY IF EXISTS "koala_conv_update" ON koala_conversations;
DROP POLICY IF EXISTS "koala_conv_select" ON koala_conversations;
DROP POLICY IF EXISTS "conv_select" ON koala_conversations;
DROP POLICY IF EXISTS "conv_insert" ON koala_conversations;
DROP POLICY IF EXISTS "conv_update" ON koala_conversations;

CREATE POLICY "conv_select" ON koala_conversations FOR SELECT
  TO anon, authenticated
  USING (user_id = get_user_id() OR designer_id = get_user_id());

CREATE POLICY "conv_insert" ON koala_conversations FOR INSERT
  TO anon, authenticated
  WITH CHECK (user_id = get_user_id() OR designer_id = get_user_id());

CREATE POLICY "conv_update" ON koala_conversations FOR UPDATE
  TO anon, authenticated
  USING (user_id = get_user_id() OR designer_id = get_user_id())
  WITH CHECK (user_id = get_user_id() OR designer_id = get_user_id());

-- ─── A2. koala_direct_messages ─────────────────────────────────────────────
DROP POLICY IF EXISTS "koala_dm_insert" ON koala_direct_messages;
DROP POLICY IF EXISTS "koala_dm_select" ON koala_direct_messages;
DROP POLICY IF EXISTS "koala_dm_update" ON koala_direct_messages;
DROP POLICY IF EXISTS "msg_select" ON koala_direct_messages;
DROP POLICY IF EXISTS "msg_insert" ON koala_direct_messages;
DROP POLICY IF EXISTS "msg_update" ON koala_direct_messages;

CREATE POLICY "msg_select" ON koala_direct_messages FOR SELECT
  TO anon, authenticated
  USING (
    EXISTS (
      SELECT 1 FROM koala_conversations c
      WHERE c.id = conversation_id
        AND (c.user_id = get_user_id() OR c.designer_id = get_user_id())
    )
  );

CREATE POLICY "msg_insert" ON koala_direct_messages FOR INSERT
  TO anon, authenticated
  WITH CHECK (
    sender_id = get_user_id()
    AND EXISTS (
      SELECT 1 FROM koala_conversations c
      WHERE c.id = conversation_id
        AND (c.user_id = get_user_id() OR c.designer_id = get_user_id())
    )
  );

CREATE POLICY "msg_update" ON koala_direct_messages FOR UPDATE
  TO anon, authenticated
  USING (
    EXISTS (
      SELECT 1 FROM koala_conversations c
      WHERE c.id = conversation_id
        AND (c.user_id = get_user_id() OR c.designer_id = get_user_id())
    )
  );

-- ─── A3. users ─────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "users_insert" ON users;
DROP POLICY IF EXISTS "users_update" ON users;
DROP POLICY IF EXISTS "users_select" ON users;
DROP POLICY IF EXISTS "user_select" ON users;
DROP POLICY IF EXISTS "user_insert" ON users;
DROP POLICY IF EXISTS "user_update" ON users;

CREATE POLICY "user_select" ON users FOR SELECT
  TO anon, authenticated
  USING (
    id = get_user_id()
    OR EXISTS (SELECT 1 FROM users u WHERE u.id = get_user_id() AND u.role = 'admin')
  );

CREATE POLICY "user_insert" ON users FOR INSERT
  TO anon, authenticated
  WITH CHECK (id = get_user_id());

CREATE POLICY "user_update" ON users FOR UPDATE
  TO anon, authenticated
  USING (id = get_user_id())
  WITH CHECK (id = get_user_id());

-- ─── A4. koala_push_tokens ─────────────────────────────────────────────────
DROP POLICY IF EXISTS "push_insert" ON koala_push_tokens;
DROP POLICY IF EXISTS "push_update" ON koala_push_tokens;
DROP POLICY IF EXISTS "push_delete" ON koala_push_tokens;
DROP POLICY IF EXISTS "push_select" ON koala_push_tokens;
DROP POLICY IF EXISTS "token_all" ON koala_push_tokens;

CREATE POLICY "push_select" ON koala_push_tokens FOR SELECT
  TO anon, authenticated
  USING (user_id = get_user_id());

CREATE POLICY "push_insert" ON koala_push_tokens FOR INSERT
  TO anon, authenticated
  WITH CHECK (user_id = get_user_id());

CREATE POLICY "push_update" ON koala_push_tokens FOR UPDATE
  TO anon, authenticated
  USING (user_id = get_user_id())
  WITH CHECK (user_id = get_user_id());

CREATE POLICY "push_delete" ON koala_push_tokens FOR DELETE
  TO anon, authenticated
  USING (user_id = get_user_id());

-- ─── A5. koala_notifications ───────────────────────────────────────────────
-- INSERT: trigger SECURITY DEFINER olduğu için RLS'i bypass eder; client
-- anon'dan doğrudan notif yazmaya izin YOK (service_role/trigger only).
DROP POLICY IF EXISTS "notif_insert" ON koala_notifications;
DROP POLICY IF EXISTS "notif_update" ON koala_notifications;
DROP POLICY IF EXISTS "notif_select" ON koala_notifications;
DROP POLICY IF EXISTS "notif_delete" ON koala_notifications;

CREATE POLICY "notif_select" ON koala_notifications FOR SELECT
  TO anon, authenticated
  USING (user_id = get_user_id());

CREATE POLICY "notif_insert" ON koala_notifications FOR INSERT
  TO anon, authenticated
  WITH CHECK (user_id = get_user_id());   -- trigger/service_role bypass

CREATE POLICY "notif_update" ON koala_notifications FOR UPDATE
  TO anon, authenticated
  USING (user_id = get_user_id())
  WITH CHECK (user_id = get_user_id());

CREATE POLICY "notif_delete" ON koala_notifications FOR DELETE
  TO anon, authenticated
  USING (user_id = get_user_id());

-- ─── A6. saved_items ───────────────────────────────────────────────────────
DROP POLICY IF EXISTS "saved_items_insert" ON saved_items;
DROP POLICY IF EXISTS "saved_items_delete" ON saved_items;
DROP POLICY IF EXISTS "saved_items_update" ON saved_items;
DROP POLICY IF EXISTS "saved_items_select" ON saved_items;
DROP POLICY IF EXISTS "saved_select" ON saved_items;
DROP POLICY IF EXISTS "saved_insert" ON saved_items;
DROP POLICY IF EXISTS "saved_update" ON saved_items;
DROP POLICY IF EXISTS "saved_delete" ON saved_items;

CREATE POLICY "saved_select" ON saved_items FOR SELECT
  TO anon, authenticated USING (user_id = get_user_id());
CREATE POLICY "saved_insert" ON saved_items FOR INSERT
  TO anon, authenticated WITH CHECK (user_id = get_user_id());
CREATE POLICY "saved_update" ON saved_items FOR UPDATE
  TO anon, authenticated USING (user_id = get_user_id()) WITH CHECK (user_id = get_user_id());
CREATE POLICY "saved_delete" ON saved_items FOR DELETE
  TO anon, authenticated USING (user_id = get_user_id());

-- ─── A7. collections ───────────────────────────────────────────────────────
DROP POLICY IF EXISTS "collections_insert" ON collections;
DROP POLICY IF EXISTS "collections_update" ON collections;
DROP POLICY IF EXISTS "collections_delete" ON collections;
DROP POLICY IF EXISTS "collections_select" ON collections;
DROP POLICY IF EXISTS "coll_select" ON collections;
DROP POLICY IF EXISTS "coll_insert" ON collections;
DROP POLICY IF EXISTS "coll_update" ON collections;
DROP POLICY IF EXISTS "coll_delete" ON collections;

CREATE POLICY "coll_select" ON collections FOR SELECT
  TO anon, authenticated USING (user_id = get_user_id());
CREATE POLICY "coll_insert" ON collections FOR INSERT
  TO anon, authenticated WITH CHECK (user_id = get_user_id());
CREATE POLICY "coll_update" ON collections FOR UPDATE
  TO anon, authenticated USING (user_id = get_user_id()) WITH CHECK (user_id = get_user_id());
CREATE POLICY "coll_delete" ON collections FOR DELETE
  TO anon, authenticated USING (user_id = get_user_id());

-- ─── A8. ai_chat_sessions + ai_chat_messages ───────────────────────────────
DROP POLICY IF EXISTS "ai_sess_insert" ON ai_chat_sessions;
DROP POLICY IF EXISTS "ai_sess_update" ON ai_chat_sessions;
DROP POLICY IF EXISTS "ai_sess_delete" ON ai_chat_sessions;
DROP POLICY IF EXISTS "ai_sess_select" ON ai_chat_sessions;
DROP POLICY IF EXISTS "Users manage own AI sessions" ON ai_chat_sessions;

CREATE POLICY "ai_sess_select" ON ai_chat_sessions FOR SELECT
  TO anon, authenticated USING (user_id = get_user_id());
CREATE POLICY "ai_sess_insert" ON ai_chat_sessions FOR INSERT
  TO anon, authenticated WITH CHECK (user_id = get_user_id());
CREATE POLICY "ai_sess_update" ON ai_chat_sessions FOR UPDATE
  TO anon, authenticated USING (user_id = get_user_id()) WITH CHECK (user_id = get_user_id());
CREATE POLICY "ai_sess_delete" ON ai_chat_sessions FOR DELETE
  TO anon, authenticated USING (user_id = get_user_id());

DROP POLICY IF EXISTS "ai_msg_insert" ON ai_chat_messages;
DROP POLICY IF EXISTS "ai_msg_select" ON ai_chat_messages;
DROP POLICY IF EXISTS "ai_msg_update" ON ai_chat_messages;
DROP POLICY IF EXISTS "ai_msg_delete" ON ai_chat_messages;
DROP POLICY IF EXISTS "Users manage own AI messages" ON ai_chat_messages;

CREATE POLICY "ai_msg_select" ON ai_chat_messages FOR SELECT
  TO anon, authenticated
  USING (EXISTS (SELECT 1 FROM ai_chat_sessions s WHERE s.id = session_id AND s.user_id = get_user_id()));

CREATE POLICY "ai_msg_insert" ON ai_chat_messages FOR INSERT
  TO anon, authenticated
  WITH CHECK (EXISTS (SELECT 1 FROM ai_chat_sessions s WHERE s.id = session_id AND s.user_id = get_user_id()));

CREATE POLICY "ai_msg_update" ON ai_chat_messages FOR UPDATE
  TO anon, authenticated
  USING (EXISTS (SELECT 1 FROM ai_chat_sessions s WHERE s.id = session_id AND s.user_id = get_user_id()));

CREATE POLICY "ai_msg_delete" ON ai_chat_messages FOR DELETE
  TO anon, authenticated
  USING (EXISTS (SELECT 1 FROM ai_chat_sessions s WHERE s.id = session_id AND s.user_id = get_user_id()));

-- ─── A9. analytics_events ──────────────────────────────────────────────────
-- Event'ler anonim olabilir (user_id NULL). Insert şartı: kullanıcı varsa
-- kendi UID'siyle yazmalı; anon ise user_id NULL olmalı.
DROP POLICY IF EXISTS "Anyone can insert analytics" ON analytics_events;
DROP POLICY IF EXISTS "analytics_insert" ON analytics_events;
DROP POLICY IF EXISTS "Users read own analytics" ON analytics_events;
DROP POLICY IF EXISTS "analytics_select" ON analytics_events;

CREATE POLICY "analytics_insert" ON analytics_events FOR INSERT
  TO anon, authenticated
  WITH CHECK (
    (get_user_id() IS NULL AND user_id IS NULL)  -- anonim event
    OR user_id = get_user_id()                    -- kimlikli event
  );

CREATE POLICY "analytics_select" ON analytics_events FOR SELECT
  TO anon, authenticated
  USING (user_id = get_user_id());

-- ─── A10. koala_chats (AI chat geçmişi) ────────────────────────────────────
DROP POLICY IF EXISTS "Users manage own chats" ON koala_chats;
DROP POLICY IF EXISTS "Users read own chats" ON koala_chats;
DROP POLICY IF EXISTS "Users insert own chats" ON koala_chats;
DROP POLICY IF EXISTS "Users update own chats" ON koala_chats;
DROP POLICY IF EXISTS "Users delete own chats" ON koala_chats;
DROP POLICY IF EXISTS "koala_chats_select" ON koala_chats;
DROP POLICY IF EXISTS "koala_chats_insert" ON koala_chats;
DROP POLICY IF EXISTS "koala_chats_update" ON koala_chats;
DROP POLICY IF EXISTS "koala_chats_delete" ON koala_chats;

CREATE POLICY "koala_chats_select" ON koala_chats FOR SELECT
  TO anon, authenticated USING (user_id = get_user_id());
CREATE POLICY "koala_chats_insert" ON koala_chats FOR INSERT
  TO anon, authenticated WITH CHECK (user_id = get_user_id());
CREATE POLICY "koala_chats_update" ON koala_chats FOR UPDATE
  TO anon, authenticated USING (user_id = get_user_id()) WITH CHECK (user_id = get_user_id());
CREATE POLICY "koala_chats_delete" ON koala_chats FOR DELETE
  TO anon, authenticated USING (user_id = get_user_id());

-- ─── A11. koala_messages (AI chat mesajları) ───────────────────────────────
DROP POLICY IF EXISTS "Users manage own messages" ON koala_messages;
DROP POLICY IF EXISTS "Users read own messages" ON koala_messages;
DROP POLICY IF EXISTS "Users insert own messages" ON koala_messages;
DROP POLICY IF EXISTS "Users update own messages" ON koala_messages;
DROP POLICY IF EXISTS "Users delete own messages" ON koala_messages;
DROP POLICY IF EXISTS "koala_msgs_select" ON koala_messages;
DROP POLICY IF EXISTS "koala_msgs_insert" ON koala_messages;
DROP POLICY IF EXISTS "koala_msgs_update" ON koala_messages;
DROP POLICY IF EXISTS "koala_msgs_delete" ON koala_messages;

CREATE POLICY "koala_msgs_select" ON koala_messages FOR SELECT
  TO anon, authenticated
  USING (EXISTS (SELECT 1 FROM koala_chats c WHERE c.id = chat_id AND c.user_id = get_user_id()));

CREATE POLICY "koala_msgs_insert" ON koala_messages FOR INSERT
  TO anon, authenticated
  WITH CHECK (EXISTS (SELECT 1 FROM koala_chats c WHERE c.id = chat_id AND c.user_id = get_user_id()));

CREATE POLICY "koala_msgs_update" ON koala_messages FOR UPDATE
  TO anon, authenticated
  USING (EXISTS (SELECT 1 FROM koala_chats c WHERE c.id = chat_id AND c.user_id = get_user_id()));

CREATE POLICY "koala_msgs_delete" ON koala_messages FOR DELETE
  TO anon, authenticated
  USING (EXISTS (SELECT 1 FROM koala_chats c WHERE c.id = chat_id AND c.user_id = get_user_id()));

-- ─── A12. koala_user_prefs ─────────────────────────────────────────────────
DROP POLICY IF EXISTS "Users manage own prefs" ON koala_user_prefs;
DROP POLICY IF EXISTS "Users read own prefs" ON koala_user_prefs;
DROP POLICY IF EXISTS "Users insert own prefs" ON koala_user_prefs;
DROP POLICY IF EXISTS "Users update own prefs" ON koala_user_prefs;
DROP POLICY IF EXISTS "Users delete own prefs" ON koala_user_prefs;
DROP POLICY IF EXISTS "prefs_select" ON koala_user_prefs;
DROP POLICY IF EXISTS "prefs_insert" ON koala_user_prefs;
DROP POLICY IF EXISTS "prefs_update" ON koala_user_prefs;
DROP POLICY IF EXISTS "prefs_delete" ON koala_user_prefs;

CREATE POLICY "prefs_select" ON koala_user_prefs FOR SELECT
  TO anon, authenticated USING (user_id = get_user_id());
CREATE POLICY "prefs_insert" ON koala_user_prefs FOR INSERT
  TO anon, authenticated WITH CHECK (user_id = get_user_id());
CREATE POLICY "prefs_update" ON koala_user_prefs FOR UPDATE
  TO anon, authenticated USING (user_id = get_user_id()) WITH CHECK (user_id = get_user_id());
CREATE POLICY "prefs_delete" ON koala_user_prefs FOR DELETE
  TO anon, authenticated USING (user_id = get_user_id());


-- ═══════════════════════════════════════════════════════════════════════════
-- B.  security_definer_view → security_invoker
-- ═══════════════════════════════════════════════════════════════════════════
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_views WHERE schemaname = 'public' AND viewname = 'v_swipe_metrics'
  ) THEN
    EXECUTE 'ALTER VIEW public.v_swipe_metrics SET (security_invoker = on)';
  END IF;
END
$$;


-- ═══════════════════════════════════════════════════════════════════════════
-- C.  public.scans → RLS aç (policy yok = deny-by-default)
--     Servis akışları service_role ile çalıştığı için bozulmaz.
--     Kullanılmadığı kesinleşirse DROP TABLE public.scans;
-- ═══════════════════════════════════════════════════════════════════════════
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_tables WHERE schemaname = 'public' AND tablename = 'scans') THEN
    EXECUTE 'ALTER TABLE public.scans ENABLE ROW LEVEL SECURITY';
  END IF;
END
$$;


-- ═══════════════════════════════════════════════════════════════════════════
-- D.  function_search_path_mutable fix'leri
--     Tüm kullanıcı-tanımlı fonksiyonlara SET search_path = public, pg_temp
-- ═══════════════════════════════════════════════════════════════════════════
DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure AS sig
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname IN (
        'update_learning_stage',
        'subtract_scaled_vector',
        'cleanup_old_seen_cards',
        'update_updated_at',
        'update_affinity_ewma_multi',
        'update_user_taste_updated_at',
        'get_user_id',
        'update_affinity_ewma',
        'ingest_swipe_v2',
        'ewma_vector',
        'update_koala_cards_updated_at',
        'cleanup_old_analytics',
        'ingest_swipe',
        'get_swipe_feed',
        'queue_message_push'
      )
  LOOP
    EXECUTE format('ALTER FUNCTION %s SET search_path = public, pg_temp', r.sig);
  END LOOP;
END
$$;


-- ═══════════════════════════════════════════════════════════════════════════
-- E.  public_bucket_allows_listing fix
--     Public bucket'lar URL ile doğrudan erişilebilir; SELECT policy
--     sadece "listeleme" izni verir — gereksiz. Policy'leri kaldır.
-- ═══════════════════════════════════════════════════════════════════════════
DROP POLICY IF EXISTS "Avatar public read" ON storage.objects;
DROP POLICY IF EXISTS "Public can view question images" ON storage.objects;


-- ═══════════════════════════════════════════════════════════════════════════
-- DOĞRULAMA YARDIMCISI
-- ═══════════════════════════════════════════════════════════════════════════
-- Migration sonrası Supabase Linter'ı yeniden çalıştır.
-- Kalan (true) policy'leri listelemek için:
--
--   SELECT schemaname, tablename, policyname, cmd, qual, with_check
--   FROM pg_policies
--   WHERE schemaname = 'public'
--     AND (qual = 'true' OR with_check = 'true')
--     AND cmd IN ('INSERT','UPDATE','DELETE','ALL');
--
-- search_path set edilmemiş fonksiyonları listelemek için:
--
--   SELECT n.nspname, p.proname
--   FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
--   WHERE n.nspname = 'public'
--     AND NOT EXISTS (
--       SELECT 1 FROM unnest(coalesce(p.proconfig,'{}')) c
--       WHERE c LIKE 'search_path=%'
--     );
