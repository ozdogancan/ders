# Koala Google Play Billing — Setup Guide

Bu dosya canlı abonelik gelirine geçmek için yapman gereken adımları sıralıyor. Kod tarafı %100 hazır; geri kalanlar **Play Console, RevenueCat, Vercel** dashboardlarında yapılacak konfigürasyon.

## Mevcut durum

| Parça | Durum |
|---|---|
| Flutter client (RevenueCat SDK, BillingService) | ✅ Hazır |
| Paywall ekranı | ✅ Hazır |
| `/api/billing/verify` (backend purchase verify) | ✅ Hazır |
| `/api/billing/restore` | ✅ Hazır |
| `/api/billing/play-webhook` (RTDN otomatik renewal/cancel/refund) | ✅ Hazır |
| `/api/billing/status` (Pro durum sorgulama) | ✅ Hazır |
| `user_profiles.pro_until`, `billing_events`, `billing_quota_usage` tabloları | ✅ Hazır |
| RevenueCat dashboard config | ❌ Yapılacak |
| Play Console subscription products | ❌ Yapılacak |
| Vercel env: `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` | ❌ Yapılacak |
| Vercel env: `GOOGLE_PUBSUB_AUDIENCE` (webhook) | ❌ Yapılacak |
| Build script `REVENUECAT_ANDROID_KEY` desteği | ✅ Eklendi |

## Ürün ID'leri (kod tarafında hardcoded)

Backend `koala-api/lib/google-play.ts:144` şu ID'leri bekliyor — Play Console'da bunlarla eşleşmesi şart:

- `koala_pro_weekly_v1` → Haftalık
- `koala_pro_monthly_v1` → Aylık (opsiyonel, paywall'da gözükmüyor)
- `koala_pro_yearly_v1` → Yıllık

## Adım 1 — Google Play Console

### 1.1 Uygulamayı oluştur
1. https://play.google.com/console → "Create app"
2. Paket adı: **`com.egitim_ai_tutor.app`** (mevcut applicationId — değiştirmen önerilmez, signing key bağlı)
3. Uygulama detayları, content rating, target audience, data safety formlarını doldur
4. **Test track**'e bir AAB yükle (`build/app/outputs/bundle/release/app-release.aab`) — internal testing önerilir

### 1.2 Abonelik ürünlerini oluştur
1. Play Console → Koala → **Monetize → Products → Subscriptions**
2. **Create subscription** × 2:

   **Haftalık plan:**
   - Product ID: `koala_pro_weekly_v1`
   - Name: "Koala Pro Haftalık"
   - Base plan ID: `weekly`
   - Billing period: 1 week
   - Price: ₺79,99 TR (diğer ülkeler için Play otomatik conversion)
   - **Free trial offer:** 7 gün — eligibility: "new customer"

   **Yıllık plan:**
   - Product ID: `koala_pro_yearly_v1`
   - Name: "Koala Pro Yıllık"
   - Base plan ID: `yearly`
   - Billing period: 1 year
   - Price: ₺999,99 TR
   - Trial yok (haftalık üzerinden trial veriliyor)

3. Her ikisi için **"Active"** olarak işaretle.

### 1.3 Real-Time Developer Notifications (RTDN)
Webhook'un otomatik renewal/cancel/refund işlemesi için:
1. Play Console → Monetize → **Monetization setup → Real-time developer notifications**
2. **Cloud Pub/Sub Topic**: Google Cloud Console'da yeni bir Pub/Sub topic oluştur (`projects/<proj>/topics/koala-rtdn`)
3. Topic'e PUSH subscription ekle:
   - Endpoint: `https://koala-api-olive.vercel.app/api/billing/play-webhook`
   - Authentication: "Enable authentication" → service account ekle
   - Audience: `https://koala-api-olive.vercel.app` (Vercel env `GOOGLE_PUBSUB_AUDIENCE` ile eşleşmeli)
4. Play Console'a topic name'i gir.

### 1.4 Service Account (verify endpoint için)
Backend purchase verify yapmak için Google Play Developer API erişimi gerek:
1. https://console.cloud.google.com → IAM → Service Accounts → Create
2. Role: **"Service Account User"**
3. JSON key indir
4. Play Console → Setup → API access → "Link service account"
5. Service account'a permission: "View financial data, orders, and cancellation survey responses" + "Manage orders and subscriptions"

## Adım 2 — RevenueCat

RevenueCat, billing'i basitleştiriyor (verify + restore + RTDN handling) ama bizim backend zaten doğrudan Google Play API kullanıyor. **RevenueCat opsiyonel ama önerilir** (cross-platform, retry logic, observability).

### Eğer RevenueCat KULLANACAKSAN
1. https://app.revenuecat.com → Yeni proje
2. Add app → Android → package `com.egitim_ai_tutor.app`
3. **Public Android SDK key** (`goog_xxxx`) — kopyala
4. Build sırasında env var olarak ver:
   ```powershell
   $env:REVENUECAT_ANDROID_KEY = "goog_xxxx..."
   .\build_android.ps1
   ```
5. RevenueCat dashboard'da:
   - **Products** → Play Console'daki product ID'leri ekle (`koala_pro_weekly_v1`, `koala_pro_yearly_v1`)
   - **Entitlements** → Tek entitlement: `pro`
   - **Offerings** → "Default" offering, içine 2 paket (`weekly`, `yearly`)

### RevenueCat OLMADAN
Mevcut backend (`/api/billing/verify`) doğrudan Play API kullanıyor. RevenueCat SDK'sı flutter app'inde initialize edilmeden purchase tetiklenmez. Bu durumda `billing_service.dart`'ı `in_app_purchase` paketine geçirmek gerek — bu BÜYÜK refactor. Önerim: **RevenueCat kullan**.

## Adım 3 — Vercel env

Koala-api Vercel projesinde (https://vercel.com/dashboard → koala-api → Settings → Environment Variables):

```
GOOGLE_PLAY_SERVICE_ACCOUNT_JSON  = <Adım 1.4'teki JSON içeriği — tek satıra çevirip yapıştır VEYA base64 encode et>
GOOGLE_PUBSUB_AUDIENCE            = https://koala-api-olive.vercel.app
GOOGLE_PLAY_PACKAGE_NAME          = com.egitim_ai_tutor.app
REVENUECAT_WEBHOOK_SECRET         = <RevenueCat webhooks settings'ten>
```

Deploy: env değişiklikleri Vercel'de otomatik propagate olur ama bir redeploy gerekir.

## Adım 4 — Test akışı

1. Play Console'da **internal testing** track'e tester e-postanı ekle
2. AAB yükle (`build_android.ps1` ile build edilen)
3. Tester linki ile telefonunda yükle
4. Uygulamaya gir → paywall aç → satın al (test card kullanılır, gerçek ücret çekilmez)
5. Webhook'un Vercel logs'ta düşüp düşmediğini kontrol et
6. `billing_events` tablosuna kayıt düştü mü, `user_profiles.pro_until` doldu mu — Supabase'den bak

## Adım 5 — Adım 1.1'de paket adı kararı

Şu an applicationId `com.egitim_ai_tutor.app`. Bu eski "Egitim AI Tutor" projesinden gelmiş.

**Önerilerim:**
- **Devam ettir** (`com.egitim_ai_tutor.app`): Mevcut signing key (`koala-release.jks`) bu ID için imzalı. Değiştirmen Play Console'da yeni uygulama açmanı gerektirir, eski yüklemeler geçersiz olur.
- **Değiştir** (`com.evlumba.koala` gibi): Eğer henüz Play Console'a bir uygulama yüklemediysen yapabilirsin. Build sonrası yeni keystore + yeni signing.

Şu an Play Console'da uygulama varsa → DEVAM ET. Yoksa karar ver.

## Adım 6 — Ne zaman para görmeye başlarsın?

Play Console hesabını oluştururken **Merchant Profile** oluşturman gerekti (banka bilgileri). Her ay sonu Play o ay içindeki net gelirin %85'ini (Google %15 alır — yıllık abonelikler 1. yıldan sonra %85 → %30 indirim) bankana yatırır. İlk ödeme ~45 gün gecikmeli.

## SSS

**Q: RevenueCat olmadan da çalışır mı?**
A: Backend evet (Play API doğrudan). Ama Flutter client RevenueCat SDK'sını kullanıyor. RevenueCat olmadan client tarafını `in_app_purchase` paketine geçirmek gerek — büyük iş.

**Q: iOS App Store'a da koyacak mıyım?**
A: Aynı backend (`/api/billing/verify`) hem iOS hem Android'i destekleyebilir, sadece App Store Connect tarafında ayrı products gerek. Şu anki kod sadece Android'i implement ediyor; iOS için `apple-app-store-server-api` paketi eklemek gerek.

**Q: Free trial nasıl çalışıyor?**
A: 7 gün boyunca Pro özellikler açık, kullanıcı iptal etmezse 8. gün otomatik ücret düşer. `user_profiles.trial_used = true` set edildikten sonra aynı kullanıcıya bir daha trial verilmez (kod tarafında handle edildi).

**Q: Vergi?**
A: Play Console'da TR kullanıcıları için KDV otomatik tahsil edilir + Google ödeme öncesi kesilir. Net gelirin %85'i sana yatar.
