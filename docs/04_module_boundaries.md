# Module Boundaries - Koala Project

## Modul Haritasi

```
koala/
├── AUTH           → Giris, kayit, sifre sifirlama, email dogrulama
├── ONBOARDING     → Ilk kurulum, profil olusturma, ilgi alani secimi
├── HOME           → Ana sayfa, dashboard
├── TUTOR          → Egitmen listeleme, detay, egitmen olma
├── LESSON/BOOKING → Ders detay, randevu alma, ders gecmisi
├── CHAT           → Mesajlasma, AI sohbet
├── PROFILE        → Profil goruntuleme, duzenleme, ayarlar
├── NOTIFICATION   → Bildirimler
├── SEARCH         → Arama
└── SHARED         → Ortak widget, servis, model, util
```

## Modul Detaylari

### AUTH Modulu
**Sinir:** Sadece authentication isleri
**Dosyalar:**
- screens/login_screen.dart
- screens/register_screen.dart
- screens/forgot_password_screen.dart
- screens/email_verification_screen.dart
- services/auth_service.dart

**Bagimliliklari:** Firebase Auth
**Baska modulu etkiler mi:** Evet - basarili login sonrasi Home'a yonlendirir

---

### ONBOARDING Modulu
**Sinir:** Ilk kullanim akisi
**Dosyalar:**
- screens/onboarding_screen.dart
- screens/profile_setup_screen.dart
- screens/interest_selection_screen.dart

**Bagimliliklari:** Auth (kullanici bilgisi), Supabase (profil kaydi)
**Baska modulu etkiler mi:** Hayir - tek yonlu akis

---

### HOME Modulu
**Sinir:** Ana sayfa ve dashboard
**Dosyalar:**
- screens/home_screen.dart
- screens/dashboard_screen.dart
- screens/bottom_nav_screen.dart

**Bagimliliklari:** Tutor, Lesson, Chat (veri gosterimi icin)
**Baska modulu etkiler mi:** Hayir - sadece goruntuleme

---

### TUTOR Modulu
**Sinir:** Egitmen listeleme, detay ve basvuru
**Dosyalar:**
- screens/tutor_listing_screen.dart
- screens/tutor_detail_screen.dart
- screens/tutor_profile_screen.dart
- screens/become_tutor_screen.dart
- widgets/tutor_card.dart

**Bagimliliklari:** Supabase, Review
**Baska modulu etkiler mi:** Booking modulu ile baglantili (ders al butonu)

---

### LESSON/BOOKING Modulu
**Sinir:** Ders yonetimi ve randevu
**Dosyalar:**
- screens/lesson_detail_screen.dart
- screens/booking_screen.dart
- screens/my_lessons_screen.dart
- screens/lesson_history_screen.dart
- services/booking_service.dart
- widgets/lesson_card.dart

**Bagimliliklari:** Tutor (egitmen bilgisi), Supabase, Notification
**Baska modulu etkiler mi:** Notification tetikler

---

### CHAT Modulu - EN KIRILGAN
**Sinir:** Kullanici-kullanici mesajlasma + AI sohbet
**Dosyalar:**
- screens/chat_list_screen.dart
- screens/chat_detail_screen.dart (2993 LOC - BOLUNMELI)
- screens/ai_chat_screen.dart
- services/chat_service.dart
- services/koala_ai_service.dart

**Bagimliliklari:** Supabase, Gemini AI (proxy uzerinden), Auth
**Baska modulu etkiler mi:** Hayir ama en cok ic bagimliligi olan modul

---

### PROFILE Modulu
**Sinir:** Kullanici profili ve ayarlar
**Dosyalar:**
- screens/profile_screen.dart
- screens/edit_profile_screen.dart
- screens/settings_screen.dart

**Bagimliliklari:** Auth, Supabase
**Baska modulu etkiler mi:** Hayir

---

### SHARED (Ortak)
**Dosyalar:**
- services/supabase_service.dart
- services/notification_service.dart
- services/storage_service.dart
- models/*.dart
- widgets/koala_button.dart (ve diger ortak widget'lar)
- utils/*.dart
- constants/*.dart
- theme/*.dart
- providers/*.dart

**Kural:** Shared dosyalari degistirmek TUM modulleri etkiler. Ekstra dikkat gerektirir.

## Modul Arasi Iletisim Kurallari

1. Modul A, Modul B'nin sadece **ekranina navigate** edebilir (route uzerinden)
2. Modul A, Modul B'nin **servisini dogrudan cagirabilir** (shared servisler uzerinden)
3. Modul A, Modul B'nin **internal widget'ini KULLANAMAZ** (sadece shared widget'lar ortaktir)
4. Veri paylasimi **Supabase uzerinden** olur, dogrudan state paylasimi yok (su an icin)

## Degisiklik Etki Matrisi

Bir modulu degistirdiginde kontrol edilmesi gerekenler:

| Degisen Modul | Kontrol Et |
|---------------|-----------|
| Auth | Home (redirect), Onboarding (redirect) |
| Shared/Services | TUM MODULLER |
| Shared/Widgets | Kullanan tum ekranlar |
| Shared/Theme | TUM EKRANLAR |
| Chat | Sadece Chat modulu ici |
| Tutor | Booking (ders al akisi) |
| Booking | Notification (bildirim tetiklemesi) |
| Diger moduller | Genelde izole, yan etki dusuk |
