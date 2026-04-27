# Koala 2.0 — Launch Roadmap (Android-öncelikli)

> **Pozisyon:** "Odanı çek, AI yeniden tasarlasın — beğendiysen Koala sana onu gerçeğe çevirecek mimarı/ustayı bulur."
> RoomGPT/SnapHome/Reroom render satıyor. Koala **render + gerçeğe dönüştürme** satıyor.

---

## 3 Pillar (Lansman kapsamı)
1. **Snap** — AI restyle (foto → analiz → swipe taste → restyle → before/after)
2. **Match** — pgvector ile stil-eşleşen 3 pro önerisi (Evlumba ağı)
3. **Chat & Quote** — in-app chat + structured teklif kartı + onay → **%10 komisyon**

SnapHome'un "cost estimate, wall paint, object remove" feature'ları **Sprint 4+**. Önce 3 pillar'ı taş gibi yapıp çıkıyoruz.

---

## Gelir Modeli
| Kanal | Fiyat | Not |
|---|---|---|
| **Koala Pro abonelik** | 5 render/ay free → ₺149/ay veya ₺999/yıl | Paywall **6. render'da**, ilk render'ın önüne değil |
| **Pro match komisyonu** | İş bedelinin %10'u | Pro için ilk 3 lead bedava, sonra ₺49/lead veya %10 success fee |

Break-even: ayda ~80 Pro abone (render maliyeti + altyapı ~$265/ay).

---

## Sprint Planı

### ✅ Sprint 1 — Snap temeli (bu hafta) — **TAMAMLANDI**
- [x] Android applicationId korundu (`com.egitim_ai_tutor.app` — Play Store'da yaşıyor)
- [x] pubspec: ML Kit face, image_cropper, flutter_animate, purchases_flutter, screenshot
- [x] `/api/restyle` → **Gemini 2.5 Flash Image (nano-banana)** — tek senkron HTTP, ~4 sn, ~$0.04/render
- [x] Supabase şema migration (`supabase/migrations/20260424_koala2_full_schema.sql`) — 10 tablo + RLS + pgvector + 2 RPC
- [x] ML Kit face gate (`FaceGateService`) — selfie/troll Gemini'ye hit etmeden 50ms'de eler
- [x] StyleStage header sadeleştirme — tek satırda renk daireleri + stil rozeti

### 🟡 Sprint 2 — Taste + Prefetch — **BÜYÜK ÖLÇÜDE TAMAMLANDI**
- [ ] `classify_user_taste` RPC'sini client'tan çağır (Supabase fn) — *deferred, local TasteService yeterli*
- [ ] Swipe'ı Thompson Sampling bandit'a çevir (her stil için beta dist) — *deferred Sprint 3+*
- [x] Swipe bittiğinde **moodboard reveal** ekranı (flutter_animate staggered)
- [x] Prefetch worker (in-memory, `RestylePrefetchService`) — taste güçlüyse arkadan restyle başlıyor
- [ ] Before/After slider widget audit — *Sprint 3'e kaydı*
- [x] Restyle sonucunu **Vercel Blob**'a upload — `/api/restyle` `{url, output}` dönüyor
- [x] `/api/restyle` observability — `[restyle] ok/blob_uploaded/gemini_http_error/no_image_in_response` logları
- [x] **ContentGate v2** — face + image labeling (ML Kit) paralel; kedi/yemek/araba/belge/ekran/giysi/manzara Gemini'ye hit etmeden eler

### 🔵 Sprint 3 — Pro Marketplace v1 — **MVP TAMAMLANDI**
- [x] `pros` + `pro_portfolio` seed: 5 demo pro + 17 portfolio görseli (İstanbul/Ankara/İzmir, placeholder — Evlumba network'ten değiştir)
- [ ] Pro başvuru formu + admin onay flow — **Sprint 3.5**
- [ ] Portfolio upload → CLIP embed → Supabase vector kolonu — **Sprint 3.5** (şemada hazır, pipeline yok)
- [x] `match_pros_by_style` RPC (text array overlap + city + rating) + `ProMatchService` Dart wrapper
- [x] Pro profil sayfası (`ProProfileScreen`) — portfolio grid + stil rozeti + fiyat + staggered animasyon
- [x] Mekan result → "Bu tasarımı gerçeğe dönüştür" → `ProListSheet` modal (8 match, rating + overlap sıralaması)
- [x] WhatsApp deep-link MVP — `wa.me/{phone}?text=…` (chat Sprint 4'te)
- [ ] `image_cropper` ile portfolio upload'ta crop step — **Sprint 3.5**

### 🟢 Sprint 4 — Chat + Quote — **MVP TAMAMLANDI (legacy chat üzerine)**
> Mimari karar: Yeni `conversations/messages` (auth.users FK) yerine var olan `koala_conversations` + `koala_direct_messages` tablolarına genişletildi — Koala Firebase Auth kullanıyor, auth.users uid yok. Non-breaking migration.
- [x] Supabase Realtime subscription — `koala_direct_messages` / `koala_conversations` canlı dinleme (conversation_detail_screen mevcut)
- [x] Chat UI (mesaj balonu + foto attachment) — mevcut ekran genişletildi
- [x] Migration `20260426_sprint4_quote_support.sql` — `is_quote`, `quote_json`, `accepted_quote_id`, `quote_total_amount`, `quote_currency`, `pros.designer_id` (Firebase UID bridge)
- [x] Structured **QuoteCard** widget — `lib/views/chat/widgets/quote_card.dart` — kalem tablosu + toplam + süre + geçerlilik + durum rozeti
- [x] `MessagingService.sendQuote()` + `acceptQuote()` — quote_json insert + conversation kabul kaydı
- [x] Kullanıcı tarafı "Onayla / Pazarlık / Reddet" aksiyonları — onay akışı tam uçtan uca
- [x] Pro profilinde "Sohbet Başlat" CTA — `pros.designer_id` varsa in-app chat, yoksa WhatsApp fallback
- [ ] `transactions` insert + Stripe hold → komisyon hesap — **Sprint 5**
- [ ] Push notification: "Pro teklif gönderdi" / "Kullanıcı onayladı" — **Sprint 5**
- [ ] Pazarlık counter-offer akışı (QuoteCard → yeni teklif) — **Sprint 4.5**
- [ ] Pro-side web panel (reply + quote send) — **Sprint 4.5**
- [x] **Demo Quote Simulator** — `koala-api/app/api/demo/seed-quote/route.ts` — pre-baked quote insert etmek için service-role route, `DEMO_SEED_TOKEN` header'ı ile guard. Product Hunt video + investor demo + closed testing için "yerine pro koymadan" QuoteCard akışını tetikler.
- [x] Demo pro bridge script — `supabase/migrations/20260427_demo_pro_designer_bridge.sql` — Firebase test UID'i Elif'in `pros.designer_id`'ine bağlar.

**Demo/Test akışı (Sprint 5 beta öncesi doğrulama):**
1. Firebase Console → test user aç, uid'i kopyala
2. `20260427_demo_pro_designer_bridge.sql` → `REPLACE_WITH_FIREBASE_TEST_UID` yerine yaz → run
3. `vercel env add DEMO_SEED_TOKEN production` → random 32-byte hex
4. Flutter client → demo pro profiline git → "Sohbet Başlat" → conversation id'yi not et
5. `curl -X POST https://koala-api.vercel.app/api/demo/seed-quote -H "x-demo-seed-token: $TOKEN" -H "content-type: application/json" -d '{"conversationId":"...","quote":{"items":[{"label":"Boya + duvar kağıdı","qty":45,"unit":"m²","unit_price":280}],"total":12600,"duration_days":14,"notes":"İşçilik dahil."}}'`
6. Chat ekranında QuoteCard anında görünür → "Onayla" → `accepted_quote_id` DB'ye yazılır → kart onay rozeti gösterir.

### 🟠 Sprint 5 — Android beta — **HARDENING BAŞLADI**
- [x] **Firebase Crashlytics wired** — `firebase_crashlytics: ^5.0.2` pubspec, `com.google.firebase.crashlytics` gradle plugin (root + app), `FlutterError.onError` + `PlatformDispatcher.onError` mobile-release'te Crashlytics'e forward, debug/web'de bypass. Collection `setCrashlyticsCollectionEnabled(kReleaseMode)`.
- [x] **ProGuard hardening** — ML Kit (vision + internal), uCrop, FirebaseMessaging, Crashlytics, OkHttp dontwarn kuralları `android/app/proguard-rules.pro`'ya eklendi. `isMinifyEnabled=true` ile runtime crash riski düştü.
- [x] **targetSdk 34 explicit** — Play Store Aug 2024 zorunluluğu. `flutter.targetSdkVersion` drift'ine karşı sabitlendi.
- [x] **READ_MEDIA_IMAGES + POST_NOTIFICATIONS** — Android 13+ için manifest permissions.
- [ ] `flutter build appbundle --release` smoke test — ML Kit face gate + image_cropper + restyle akışı release'te çalışıyor mu? (Play Store'a upload ETMEDEN önce local smoke test şart — minify sorunlarını erken yakala.)
- [ ] `koala-release.jks` offsite backup (OneDrive + harici disk) — kaybedilirse applicationId'yi Play Store'da bir daha kullanamayız
- [ ] Assetlinks.json publish — `https://koala.evlumba.com/.well-known/assetlinks.json` release SHA-256 fingerprint ile
- [ ] Play Store Console: app listing (screenshot, açıklama, privacy policy URL)
- [ ] Closed Testing track: 50 beta kullanıcı (e-posta davet)
- [ ] Haptic feedback, camera overlay grid, background isolate restyle
- [ ] Push notification akışı: "Pro teklif gönderdi" / "Kullanıcı onayladı" (Sprint 4'ten devir)

### 🟣 Sprint 6 — iOS + Paywall lansmanı
- [ ] RevenueCat dashboard setup + `purchases_flutter` init
- [ ] Paywall ekranı (6. render'da veya "Pro match" öncesi)
- [ ] App Store Connect: ikon, screenshot, In-App Purchase setup (Koala Pro Aylık/Yıllık)
- [ ] iOS submit + review
- [ ] Web'de Stripe Checkout (aynı Pro planı, RevenueCat Stripe integration)
- [ ] Lansman iletişimi: product-hunt, Twitter, Evlumba network

---

## Teknik Stack (kararlar final)

| Katman | Seçim |
|---|---|
| Client | Flutter 3.10+ (web + Android + iOS tek kod) |
| API | Next.js 15 App Router (Vercel Fluid Compute) |
| DB | Supabase Postgres + pgvector + Realtime + Storage |
| Queue | Vercel Queues (beta) |
| Payment | RevenueCat (mobil) + Stripe (web) |
| Analytics | PostHog self-host |
| Crash | Sentry |
| Push | Firebase Cloud Messaging (zaten bağlı) |
| AI — analyze | Gemini 2.5 Flash (is_room + palette + style + mood) |
| AI — face gate | Google ML Kit on-device (bedava) |
| AI — restyle MVP | **Gemini 2.5 Flash Image (nano-banana)** — ~$0.04/img, 4sn |
| AI — restyle v2 | Flux Depth / Flux Kontext (Replicate) — oda bazlı routing |

---

## Tahmini Maliyet (aylık 10k render senaryosu)
- Gemini analyze: 10k × $0.0005 = **$5**
- Nano-banana restyle: 10k × $0.04 = **$400**
- Supabase Pro: **$25**
- Vercel Pro: **$20**
- RevenueCat: **~$15** (%1 after $10k MTR)
- **Toplam: ~$465/ay**

10k render ≈ 1-2k aktif kullanıcı ≈ 50-100 Pro abone × ₺149 ≈ ₺7.500-15.000 gelir ≈ $250-500 + komisyon.

**Break-even: ayda ~80 Pro abone** (komisyon olmadan). İlk Match komisyonuyla (₺1.500-4.000) break-even %80+ yakınlaşır.

---

## İleride (Sprint 7+)
- Cost Estimate Pin Overlay (SnapHome paritesi)
- Wall Paint (SAM segmentation + color picker)
- Object Remove (LaMa inpainting)
- Reference Style (IP-Adapter / Flux Redux)
- Exterior + Bahçe restyle
- B2B: kafe/restoran sahipleri için ticari segment
- iOS Vision Pro build
