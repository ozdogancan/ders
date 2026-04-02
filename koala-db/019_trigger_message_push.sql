-- ═══════════════════════════════════════════════════════════
-- 019_trigger_message_push.sql — Yeni mesajda push + in-app bildirim
-- koala_direct_messages INSERT → outbound_queue + koala_notifications
-- ═══════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION queue_message_push()
RETURNS TRIGGER AS $$
DECLARE
  v_conv RECORD;
  v_target_user TEXT;
  v_sender_name TEXT;
BEGIN
  -- Conversation bilgilerini çek
  SELECT user_id, designer_id INTO v_conv
  FROM koala_conversations WHERE id = NEW.conversation_id;

  -- Hedef: mesajı gönderenin karşısındaki kişi
  IF NEW.sender_id = v_conv.user_id THEN
    v_target_user := v_conv.designer_id;
  ELSE
    v_target_user := v_conv.user_id;
  END IF;

  -- Gönderen adı
  v_sender_name := COALESCE(
    (SELECT display_name FROM users WHERE id = NEW.sender_id),
    'Tasarımcı'
  );

  -- Duplicate kontrol: son 2 dk'da aynı conversation için pending push var mı
  IF EXISTS (
    SELECT 1 FROM outbound_queue
    WHERE user_id = v_target_user AND channel = 'fcm_push' AND status = 'pending'
    AND payload->>'conversation_id' = NEW.conversation_id::text
    AND created_at > now() - interval '2 minutes'
  ) THEN
    RETURN NEW;
  END IF;

  -- Push kuyruğuna ekle
  INSERT INTO outbound_queue (channel, user_id, title, body, payload)
  VALUES (
    'fcm_push', v_target_user, v_sender_name, LEFT(NEW.content, 80),
    jsonb_build_object(
      'conversation_id', NEW.conversation_id,
      'sender_id', NEW.sender_id,
      'sender_name', v_sender_name,
      'message_type', NEW.message_type
    )
  );

  -- In-app bildirim de ekle
  INSERT INTO koala_notifications (user_id, type, title, body, action_type, action_data)
  VALUES (
    v_target_user, 'new_message',
    v_sender_name || ' mesaj gönderdi', LEFT(NEW.content, 100),
    'open_conversation',
    jsonb_build_object('conversation_id', NEW.conversation_id)
  );

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER trg_message_push
  AFTER INSERT ON public.koala_direct_messages
  FOR EACH ROW EXECUTE FUNCTION queue_message_push();
