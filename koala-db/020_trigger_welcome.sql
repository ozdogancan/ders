-- ═══════════════════════════════════════════════════════════
-- 020_trigger_welcome.sql — Yeni kullanıcıda hoşgeldin emaili
-- users INSERT → outbound_queue (5dk delay)
-- ═══════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION queue_welcome_email()
RETURNS TRIGGER AS $$
BEGIN
  -- Email yoksa atla
  IF NEW.email IS NULL OR NEW.email = '' THEN
    RETURN NEW;
  END IF;

  -- 5 dakika sonra gönder (kullanıcı hemen çıkmasın)
  INSERT INTO outbound_queue (channel, user_id, title, body, payload, send_after)
  VALUES (
    'email', NEW.id,
    'Koala''ya hoş geldin! 🐨',
    'Yapay zeka ile iç mimari keşfine başla',
    jsonb_build_object(
      'template', 'welcome',
      'email', NEW.email,
      'display_name', COALESCE(NEW.display_name, 'Merhaba')
    ),
    now() + interval '5 minutes'
  );

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER trg_welcome_email
  AFTER INSERT ON public.users
  FOR EACH ROW EXECUTE FUNCTION queue_welcome_email();
