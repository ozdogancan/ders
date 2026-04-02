-- ═══════════════════════════════════════════════════════════
-- 015_api_functions.sql — RPC fonksiyonlar
-- Birden fazla sorguyu tek cagriyla birlestir
-- ═══════════════════════════════════════════════════════════

-- 1. Home feed — tek RPC ile ana sayfa verisi
CREATE OR REPLACE FUNCTION get_home_feed(p_user_id TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE result JSONB;
BEGIN
  SELECT jsonb_build_object(
    'saved_items', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', si.id, 'item_id', si.item_id, 'item_type', si.item_type,
        'title', si.title, 'image_url', si.image_url
      ))
      FROM (SELECT * FROM saved_items WHERE user_id = p_user_id ORDER BY created_at DESC LIMIT 5) si
    ), '[]'::jsonb),
    'conversations', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', c.id, 'designer_id', c.designer_id, 'title', c.title,
        'last_message', c.last_message, 'last_message_at', c.last_message_at,
        'unread_count_user', c.unread_count_user
      ))
      FROM (SELECT * FROM koala_conversations WHERE user_id = p_user_id AND status = 'active' ORDER BY last_message_at DESC LIMIT 3) c
    ), '[]'::jsonb),
    'unread_messages', COALESCE((
      SELECT SUM(unread_count_user) FROM koala_conversations WHERE user_id = p_user_id AND status = 'active'
    ), 0),
    'unread_notifications', (
      SELECT COUNT(*) FROM koala_notifications WHERE user_id = p_user_id AND is_read = false
    )
  ) INTO result;
  RETURN result;
END;
$$;

-- 2. User stats — profil ekrani icin
CREATE OR REPLACE FUNCTION get_user_stats(p_user_id TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE result JSONB;
BEGIN
  SELECT jsonb_build_object(
    'saved_design', (SELECT COUNT(*) FROM saved_items WHERE user_id = p_user_id AND item_type = 'design'),
    'saved_designer', (SELECT COUNT(*) FROM saved_items WHERE user_id = p_user_id AND item_type = 'designer'),
    'saved_product', (SELECT COUNT(*) FROM saved_items WHERE user_id = p_user_id AND item_type = 'product'),
    'collections', (SELECT COUNT(*) FROM collections WHERE user_id = p_user_id),
    'conversations', (SELECT COUNT(*) FROM koala_conversations WHERE user_id = p_user_id),
    'messages_sent', (SELECT COUNT(*) FROM koala_direct_messages WHERE sender_id = p_user_id)
  ) INTO result;
  RETURN result;
END;
$$;
