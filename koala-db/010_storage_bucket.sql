-- ═══════════════════════════════════════════════════════════
-- 010_storage_bucket.sql — Mesaj görselleri için storage bucket
-- ═══════════════════════════════════════════════════════════

-- Bucket oluştur (Supabase Dashboard > Storage'dan da yapılabilir)
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'message-images',
  'message-images',
  true, -- public (URL ile erişilebilir)
  5242880, -- 5MB limit
  ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/gif']
) ON CONFLICT (id) DO NOTHING;

-- RLS: Authenticated kullanıcılar yükleyebilir
CREATE POLICY "Authenticated users upload message images"
  ON storage.objects FOR INSERT
  WITH CHECK (
    bucket_id = 'message-images'
    AND auth.role() = 'authenticated'
  );

-- RLS: Herkes okuyabilir (public bucket)
CREATE POLICY "Public read message images"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'message-images');

-- RLS: Yükleyen silebilir
CREATE POLICY "Users delete own message images"
  ON storage.objects FOR DELETE
  USING (
    bucket_id = 'message-images'
    AND auth.uid()::text = (storage.foldername(name))[1]
  );
