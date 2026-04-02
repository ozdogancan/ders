-- ═══════════════════════════════════════════════════════════
-- 023_increment_unread.sql — Mesajlaşma unread sayaç RPC'si
-- Sadece izin verilen kolonları arttırır ve son mesaj bilgisini günceller
-- ═══════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.increment_unread(
  conv_id UUID,
  field_name TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  IF field_name NOT IN ('unread_count_user', 'unread_count_designer') THEN
    RAISE EXCEPTION 'invalid unread field: %', field_name;
  END IF;

  IF field_name = 'unread_count_user' THEN
    UPDATE public.koala_conversations
    SET unread_count_user = COALESCE(unread_count_user, 0) + 1,
        updated_at = now()
    WHERE id = conv_id;
  ELSE
    UPDATE public.koala_conversations
    SET unread_count_designer = COALESCE(unread_count_designer, 0) + 1,
        updated_at = now()
    WHERE id = conv_id;
  END IF;
END;
$$;

COMMENT ON FUNCTION public.increment_unread(UUID, TEXT) IS
  'Mesajlaşma unread sayaçlarını güvenli biçimde arttırır.';
