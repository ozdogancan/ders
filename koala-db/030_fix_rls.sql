-- ═══════════════════════════════════════════════════════════
-- 030_fix_rls.sql — RLS güvenlik düzeltmesi
-- Anon ALL policy'leri kaldır, user-based policy'ler ekle
-- Flutter client Firebase UID'yi x-user-id header'ı ile gönderir
-- ═══════════════════════════════════════════════════════════

-- ─── HELPER FUNCTION ───
-- Firebase UID'yi JWT claims veya custom header'dan al
CREATE OR REPLACE FUNCTION get_user_id()
RETURNS TEXT
LANGUAGE sql
STABLE
AS $$
  SELECT coalesce(
    -- Supabase JWT auth (ileride Firebase → Supabase JWT bridge)
    nullif(current_setting('request.jwt.claims', true)::json->>'sub', ''),
    -- Custom header (şimdilik Flutter'dan gönderilen)
    nullif(current_setting('request.headers', true)::json->>'x-user-id', '')
  );
$$;

-- ═══════════════════════════════════════════════════════════
-- CONVERSATIONS — sadece katılımcılar erişebilir
-- ═══════════════════════════════════════════════════════════
DROP POLICY IF EXISTS "conversations_anon_all" ON koala_conversations;
DROP POLICY IF EXISTS "Users see own conversations" ON koala_conversations;
DROP POLICY IF EXISTS "Users insert own conversations" ON koala_conversations;
DROP POLICY IF EXISTS "Participants update conversation" ON koala_conversations;

CREATE POLICY "conv_select" ON koala_conversations FOR SELECT
  USING (user_id = get_user_id() OR designer_id = get_user_id());
CREATE POLICY "conv_insert" ON koala_conversations FOR INSERT
  WITH CHECK (user_id = get_user_id());
CREATE POLICY "conv_update" ON koala_conversations FOR UPDATE
  USING (user_id = get_user_id() OR designer_id = get_user_id());

-- ═══════════════════════════════════════════════════════════
-- MESSAGES — sadece conversation katılımcıları
-- ═══════════════════════════════════════════════════════════
DROP POLICY IF EXISTS "messages_anon_all" ON koala_direct_messages;
DROP POLICY IF EXISTS "Participants see messages" ON koala_direct_messages;
DROP POLICY IF EXISTS "Participants send messages" ON koala_direct_messages;
DROP POLICY IF EXISTS "Sender or recipient can update messages" ON koala_direct_messages;

CREATE POLICY "msg_select" ON koala_direct_messages FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM koala_conversations c
      WHERE c.id = conversation_id
      AND (c.user_id = get_user_id() OR c.designer_id = get_user_id())
    )
  );
CREATE POLICY "msg_insert" ON koala_direct_messages FOR INSERT
  WITH CHECK (sender_id = get_user_id());
CREATE POLICY "msg_update" ON koala_direct_messages FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM koala_conversations c
      WHERE c.id = conversation_id
      AND (c.user_id = get_user_id() OR c.designer_id = get_user_id())
    )
  );

-- ═══════════════════════════════════════════════════════════
-- SAVED ITEMS — sadece sahibi
-- ═══════════════════════════════════════════════════════════
DROP POLICY IF EXISTS "saved_items_anon_select" ON saved_items;
DROP POLICY IF EXISTS "saved_items_anon_insert" ON saved_items;
DROP POLICY IF EXISTS "saved_items_anon_delete" ON saved_items;
DROP POLICY IF EXISTS "Users manage own saved items" ON saved_items;

CREATE POLICY "saved_select" ON saved_items FOR SELECT
  USING (user_id = get_user_id());
CREATE POLICY "saved_insert" ON saved_items FOR INSERT
  WITH CHECK (user_id = get_user_id());
CREATE POLICY "saved_update" ON saved_items FOR UPDATE
  USING (user_id = get_user_id());
CREATE POLICY "saved_delete" ON saved_items FOR DELETE
  USING (user_id = get_user_id());

-- ═══════════════════════════════════════════════════════════
-- COLLECTIONS — sahibi + public read
-- ═══════════════════════════════════════════════════════════
DROP POLICY IF EXISTS "collections_anon_select" ON collections;
DROP POLICY IF EXISTS "collections_anon_insert" ON collections;
DROP POLICY IF EXISTS "collections_anon_update" ON collections;
DROP POLICY IF EXISTS "collections_anon_delete" ON collections;
DROP POLICY IF EXISTS "Users manage own collections" ON collections;

CREATE POLICY "coll_select" ON collections FOR SELECT
  USING (user_id = get_user_id());
CREATE POLICY "coll_insert" ON collections FOR INSERT
  WITH CHECK (user_id = get_user_id());
CREATE POLICY "coll_update" ON collections FOR UPDATE
  USING (user_id = get_user_id());
CREATE POLICY "coll_delete" ON collections FOR DELETE
  USING (user_id = get_user_id());

-- ═══════════════════════════════════════════════════════════
-- USERS — kendi profili + admin tümünü görebilir
-- ═══════════════════════════════════════════════════════════
DROP POLICY IF EXISTS "Users read own profile" ON users;
DROP POLICY IF EXISTS "Users update own profile" ON users;
DROP POLICY IF EXISTS "Insert user on signup" ON users;
DROP POLICY IF EXISTS "Admins read all users" ON users;

CREATE POLICY "user_select" ON users FOR SELECT
  USING (id = get_user_id() OR EXISTS (SELECT 1 FROM users u WHERE u.id = get_user_id() AND u.role = 'admin'));
CREATE POLICY "user_insert" ON users FOR INSERT
  WITH CHECK (id = get_user_id()); -- Sadece kendi UID'siyle kayıt oluşturabilir
CREATE POLICY "user_update" ON users FOR UPDATE
  USING (id = get_user_id());

-- ═══════════════════════════════════════════════════════════
-- NOTIFICATIONS — sadece sahibi
-- ═══════════════════════════════════════════════════════════
DROP POLICY IF EXISTS "Users see own notifications" ON koala_notifications;
DROP POLICY IF EXISTS "Insert notifications" ON koala_notifications;
DROP POLICY IF EXISTS "Users update own notifications" ON koala_notifications;
DROP POLICY IF EXISTS "Users delete own notifications" ON koala_notifications;

CREATE POLICY "notif_select" ON koala_notifications FOR SELECT
  USING (user_id = get_user_id());
CREATE POLICY "notif_insert" ON koala_notifications FOR INSERT
  WITH CHECK (true); -- Trigger'lar ekler
CREATE POLICY "notif_update" ON koala_notifications FOR UPDATE
  USING (user_id = get_user_id());
CREATE POLICY "notif_delete" ON koala_notifications FOR DELETE
  USING (user_id = get_user_id());

-- ═══════════════════════════════════════════════════════════
-- PUSH TOKENS — sadece sahibi
-- ═══════════════════════════════════════════════════════════
DROP POLICY IF EXISTS "Users manage own push tokens" ON koala_push_tokens;

CREATE POLICY "token_all" ON koala_push_tokens FOR ALL
  USING (user_id = get_user_id())
  WITH CHECK (user_id = get_user_id());
