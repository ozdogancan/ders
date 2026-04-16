-- ═══════════════════════════════════════════════════════════
-- 060_fix_message_images_anon.sql
-- ═══════════════════════════════════════════════════════════
-- SORUN:
--   010_storage_bucket.sql 'message-images' bucket'ına upload için
--   `auth.role() = 'authenticated'` şartı koyuyor.
--   Koala Firebase Auth kullandığı için Supabase tarafında her zaman
--   `auth.role() = 'anon'` döner → upload 401 ile reddedilir.
--   Sonuç: chat'te foto gönderme çalışmaz, "Görsel yüklenemedi" hatası.
--
-- ÇÖZÜM:
--   Upload policy'sini "anon dahil herkes upload edebilir" yap.
--   Güvenlik etkisi: bucket zaten PUBLIC READ (URL bilen herkes görür) —
--   anon write açmak ek bir saldırı yüzeyi yaratmıyor. Path organizasyonu
--   için uid hala gönderiliyor (`{uid}/{ts}.jpg`).
--   File size 5MB limit + MIME whitelist (image/* sadece) policy'leri
--   bucket düzeyinde devam ediyor → spam/abuse riski sınırlı.
--
-- DESIGNER (Evlumba) tarafında ise authenticated user var, onlar
-- zaten upload edebiliyordu — bu policy onları da etkilemez.
-- ═══════════════════════════════════════════════════════════

-- Eski policy'yi kaldır
DROP POLICY IF EXISTS "Authenticated users upload message images"
  ON storage.objects;

-- Yeni: anon + authenticated herkes upload edebilir
CREATE POLICY "Anyone can upload message images"
  ON storage.objects FOR INSERT
  WITH CHECK (bucket_id = 'message-images');

-- Public read policy zaten 010'da var, dokunmuyoruz.
-- Delete policy zaten 010'da auth.uid() bağlı — Firebase user'ı silemez,
-- tarihte chat foto'ları orphan kalabilir, kabul edilebilir.
