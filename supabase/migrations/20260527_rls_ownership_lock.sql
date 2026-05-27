-- RLS ownership lock — replace WITH CHECK (true) policies with strict ones.
--
-- ARCHITECTURE NOTE:
--   Koala uses Firebase Auth on the client and verifies Firebase ID tokens
--   server-side. The server uses Supabase service_role (which bypasses RLS).
--   Clients hitting Supabase directly with the anon key have NO auth.uid()
--   context (auth.uid() is NULL). Therefore the strict policies below
--   deny-by-default for client-side mutations. Server-side service_role
--   continues to work because it bypasses RLS entirely.
--
--   Where SELECT was permissive (true) we leave it alone unless within scope.
--   Where the task explicitly required ownership checks (sender_id =
--   auth.uid()::text, conversation membership), we encode them; under the
--   current architecture those checks evaluate to false for anon clients,
--   producing the same deny-by-default outcome but with the correct intent
--   so that future Supabase-auth migration "just works".
--
-- Wrapped per-table in DO blocks so a missing/renamed policy never aborts
-- the whole migration.

-- =============================================================
-- collections
-- =============================================================
DO $$
BEGIN
  BEGIN
    DROP POLICY IF EXISTS collections_insert ON public.collections;
    CREATE POLICY collections_insert ON public.collections
      FOR INSERT TO anon, authenticated
      WITH CHECK (auth.uid()::text = user_id);
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'collections_insert: %', SQLERRM;
  END;
  BEGIN
    DROP POLICY IF EXISTS collections_update ON public.collections;
    CREATE POLICY collections_update ON public.collections
      FOR UPDATE TO anon, authenticated
      USING (auth.uid()::text = user_id)
      WITH CHECK (auth.uid()::text = user_id);
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'collections_update: %', SQLERRM;
  END;
  BEGIN
    DROP POLICY IF EXISTS collections_delete ON public.collections;
    CREATE POLICY collections_delete ON public.collections
      FOR DELETE TO anon, authenticated
      USING (auth.uid()::text = user_id);
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'collections_delete: %', SQLERRM;
  END;
END $$;

-- =============================================================
-- koala_conversations
-- =============================================================
DO $$
BEGIN
  BEGIN
    DROP POLICY IF EXISTS koala_conv_insert ON public.koala_conversations;
    CREATE POLICY koala_conv_insert ON public.koala_conversations
      FOR INSERT TO anon, authenticated
      WITH CHECK (auth.uid()::text = user_id);
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'koala_conv_insert: %', SQLERRM;
  END;
  BEGIN
    DROP POLICY IF EXISTS koala_conv_update ON public.koala_conversations;
    CREATE POLICY koala_conv_update ON public.koala_conversations
      FOR UPDATE TO anon, authenticated
      USING (auth.uid()::text = user_id)
      WITH CHECK (auth.uid()::text = user_id);
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'koala_conv_update: %', SQLERRM;
  END;
END $$;

-- =============================================================
-- koala_direct_messages
--   INSERT requires: sender owns the row AND is a participant in the
--   referenced conversation. Conversations table user_id stores the
--   conversation owner; membership lookup is via koala_conversations.
-- =============================================================
DO $$
BEGIN
  BEGIN
    DROP POLICY IF EXISTS koala_dm_insert ON public.koala_direct_messages;
    CREATE POLICY koala_dm_insert ON public.koala_direct_messages
      FOR INSERT TO anon, authenticated
      WITH CHECK (
        sender_id = auth.uid()::text
        AND EXISTS (
          SELECT 1 FROM public.koala_conversations c
          WHERE c.id = koala_direct_messages.conversation_id
            AND c.user_id = auth.uid()::text
        )
      );
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'koala_dm_insert: %', SQLERRM;
  END;
END $$;

-- =============================================================
-- ai_chat_sessions
-- =============================================================
DO $$
BEGIN
  BEGIN
    DROP POLICY IF EXISTS ai_sess_insert ON public.ai_chat_sessions;
    CREATE POLICY ai_sess_insert ON public.ai_chat_sessions
      FOR INSERT TO anon, authenticated
      WITH CHECK (auth.uid()::text = user_id);
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'ai_sess_insert: %', SQLERRM;
  END;
  BEGIN
    DROP POLICY IF EXISTS ai_sess_update ON public.ai_chat_sessions;
    CREATE POLICY ai_sess_update ON public.ai_chat_sessions
      FOR UPDATE TO anon, authenticated
      USING (auth.uid()::text = user_id)
      WITH CHECK (auth.uid()::text = user_id);
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'ai_sess_update: %', SQLERRM;
  END;
  BEGIN
    DROP POLICY IF EXISTS ai_sess_delete ON public.ai_chat_sessions;
    CREATE POLICY ai_sess_delete ON public.ai_chat_sessions
      FOR DELETE TO anon, authenticated
      USING (auth.uid()::text = user_id);
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'ai_sess_delete: %', SQLERRM;
  END;
END $$;

-- =============================================================
-- ai_chat_messages
--   INSERT allowed only if session belongs to caller.
-- =============================================================
DO $$
BEGIN
  BEGIN
    DROP POLICY IF EXISTS ai_msg_insert ON public.ai_chat_messages;
    CREATE POLICY ai_msg_insert ON public.ai_chat_messages
      FOR INSERT TO anon, authenticated
      WITH CHECK (
        EXISTS (
          SELECT 1 FROM public.ai_chat_sessions s
          WHERE s.id = ai_chat_messages.session_id
            AND s.user_id = auth.uid()::text
        )
      );
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'ai_msg_insert: %', SQLERRM;
  END;
END $$;

-- =============================================================
-- analytics_events
--   Allow anon analytics (user_id IS NULL) for unauth funnel events,
--   otherwise require ownership. Server-side rate limiting is the
--   intended throttle for the NULL case.
-- =============================================================
DO $$
BEGIN
  BEGIN
    DROP POLICY IF EXISTS analytics_insert ON public.analytics_events;
    CREATE POLICY analytics_insert ON public.analytics_events
      FOR INSERT TO anon, authenticated
      WITH CHECK (
        user_id IS NULL
        OR user_id = auth.uid()::text
      );
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'analytics_insert: %', SQLERRM;
  END;
END $$;
