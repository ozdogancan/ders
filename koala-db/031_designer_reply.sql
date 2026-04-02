-- ═══════════════════════════════════════════════════════════
-- 031_designer_reply.sql — Tasarımcı email reply token sistemi
-- Email'deki "Yanıtla" linki → token doğrula → mesaj INSERT
-- ═══════════════════════════════════════════════════════════

-- Reply token tablosu
CREATE TABLE IF NOT EXISTS designer_reply_tokens (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id UUID NOT NULL REFERENCES koala_conversations(id) ON DELETE CASCADE,
  designer_id TEXT NOT NULL,
  token TEXT NOT NULL UNIQUE DEFAULT encode(gen_random_bytes(32), 'hex'),
  expires_at TIMESTAMPTZ NOT NULL DEFAULT now() + interval '7 days',
  used_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_reply_token ON designer_reply_tokens(token) WHERE used_at IS NULL;

-- RLS: sadece service_role erişir
ALTER TABLE designer_reply_tokens ENABLE ROW LEVEL SECURITY;

-- Reply fonksiyonu — token ile mesaj gönder
CREATE OR REPLACE FUNCTION designer_reply(p_token TEXT, p_content TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_tok RECORD;
BEGIN
  -- Token doğrula
  SELECT * INTO v_tok FROM designer_reply_tokens
  WHERE token = p_token AND used_at IS NULL AND expires_at > now();

  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Gecersiz veya suresi dolmus link');
  END IF;

  -- Mesaj ekle
  INSERT INTO koala_direct_messages (conversation_id, sender_id, content, message_type)
  VALUES (v_tok.conversation_id, v_tok.designer_id, p_content, 'text');

  -- Conversation güncelle
  UPDATE koala_conversations
  SET last_message = LEFT(p_content, 100),
      last_message_at = now(),
      unread_count_user = unread_count_user + 1,
      updated_at = now()
  WHERE id = v_tok.conversation_id;

  -- Token'ı kullanıldı işaretle
  UPDATE designer_reply_tokens SET used_at = now() WHERE id = v_tok.id;

  RETURN jsonb_build_object('status', 'ok', 'conversation_id', v_tok.conversation_id);
END;
$$;

-- Trigger güncelleme: mesaj geldiğinde tasarımcıya email kuyruğuna ekle
-- (reply_token ile birlikte)
CREATE OR REPLACE FUNCTION queue_designer_email_notification()
RETURNS TRIGGER AS $$
DECLARE
  v_conv RECORD;
  v_designer_email TEXT;
  v_sender_name TEXT;
  v_reply_token TEXT;
BEGIN
  SELECT user_id, designer_id INTO v_conv
  FROM koala_conversations WHERE id = NEW.conversation_id;

  -- Sadece kullanıcı mesaj attığında tasarımcıya email gönder
  IF NEW.sender_id != v_conv.user_id THEN
    RETURN NEW;
  END IF;

  -- Tasarımcı emaili (evlumba profiles'tan veya users'tan)
  SELECT email INTO v_designer_email FROM users WHERE id = v_conv.designer_id;
  IF v_designer_email IS NULL THEN RETURN NEW; END IF;

  v_sender_name := COALESCE((SELECT display_name FROM users WHERE id = NEW.sender_id), 'Kullanıcı');

  -- Reply token oluştur
  INSERT INTO designer_reply_tokens (conversation_id, designer_id)
  VALUES (NEW.conversation_id, v_conv.designer_id)
  RETURNING token INTO v_reply_token;

  -- Email kuyruğuna ekle
  INSERT INTO outbound_queue (channel, user_id, title, body, payload)
  VALUES (
    'email', v_conv.designer_id,
    v_sender_name || ' size mesaj gönderdi',
    LEFT(NEW.content, 200),
    jsonb_build_object(
      'template', 'designer_message',
      'email', v_designer_email,
      'sender_name', v_sender_name,
      'message', LEFT(NEW.content, 500),
      'reply_token', v_reply_token,
      'reply_url', 'https://koala.evlumba.com/reply?token=' || v_reply_token
    )
  );

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Bu trigger'ı mevcut trg_message_push'tan sonra çalıştır
CREATE TRIGGER trg_designer_email
  AFTER INSERT ON public.koala_direct_messages
  FOR EACH ROW EXECUTE FUNCTION queue_designer_email_notification();
