# Koala - Design Inconsistencies
**Tarih:** 2026-04-09

## Tasarim Sistemi Durumu

### Mevcut Durum: Parcali
Koala'da bir theme/ klasoru var ve temel renk/font tanimlari mevcut.
Ancak ekranlar arasinda tutarlilik dusuk.

## Tespit Edilen Tutarsizliklar

### 1. Buton Stilleri
- **Sorun:** Bazi ekranlarda ElevatedButton, bazi yerlerde TextButton, bazi yerlerde custom InkWell
- **Olmasi gereken:** Tek bir KoalaButton widget'i her yerde kullanilmali
- **Etkilenen ekranlar:** login, register, booking, profile

### 2. Kart Tasarimlari
- **Sorun:** TutorCard, LessonCard ve diger kartlar farkli shadow, radius, padding kullanıyor
- **Olmasi gereken:** Ortak bir KoalaCard base widget'i, ustune ozel kartlar
- **Etkilenen ekranlar:** tutor_listing, my_lessons, dashboard

### 3. Spacing / Padding
- **Sorun:** Bazi yerlerde 8, bazi yerlerde 12, bazi yerlerde 16 px padding - standart yok
- **Olmasi gereken:** 4px grid sistemi (4, 8, 12, 16, 24, 32)
- **Etkilenen ekranlar:** Neredeyse hepsi

### 4. Renk Kullanimi
- **Sorun:** Theme'deki renkler var ama bazi yerlerde hardcoded Color(0xFF...) kullanilmis
- **Olmasi gereken:** Sadece theme uzerinden renk erisimi
- **Etkilenen ekranlar:** Dagitik

### 5. Typography
- **Sorun:** Font size'lar ekrandan ekrana degisiyor, bazen TextTheme kullaniliyor bazen manual
- **Olmasi gereken:** Theme.of(context).textTheme uzerinden tutarli erisim
- **Etkilenen ekranlar:** Cogu ekran

### 6. Loading State Gosterimi
- **Sorun:** Bazi ekranlarda CircularProgressIndicator, bazi yerlerde custom shimmer, bazi yerlerde hicbir sey yok
- **Olmasi gereken:** Tek bir LoadingWidget + Shimmer pattern
- **Etkilenen ekranlar:** tutor_listing, chat_list, my_lessons

### 7. Error State Gosterimi
- **Sorun:** Bazi yerlerde SnackBar, bazi yerlerde AlertDialog, bazi yerlerde inline text, bazi yerlerde hic yok
- **Olmasi gereken:** Tutarli error handling UX pattern'i
- **Etkilenen ekranlar:** Tum data-fetch yapan ekranlar

### 8. Empty State Gosterimi
- **Sorun:** Liste bos oldugunda bazi ekranlar bos gorunuyor, bazilari mesaj gosteriyor
- **Olmasi gereken:** KoalaEmptyState widget'i - ikon + mesaj + aksiyon butonu
- **Etkilenen ekranlar:** my_lessons, chat_list, notifications

### 9. AppBar Tutarsizligi
- **Sorun:** Bazi ekranlarda custom AppBar, bazilarina standart, bazilarinda yok
- **Olmasi gereken:** KoalaAppBar - back button, title, optional actions

### 10. Form Validation
- **Sorun:** Bazi formlarda client-side validation var, bazilarda yok
- **Olmasi gereken:** Her form input'unda tutarli validation + error mesajlari

## Canonical Olmasi Gereken Widget Listesi

Bu widget'lar projenin "tasarim dili"ni olusturmali:

| Widget | Durum | Oncelik |
|--------|-------|---------|
| KoalaButton (primary, secondary, text) | Kismi var | Yuksek |
| KoalaCard | Kismi var | Yuksek |
| KoalaTextField | Kismi var | Yuksek |
| KoalaAppBar | Yok | Orta |
| KoalaLoadingState | Yok | Orta |
| KoalaErrorState | Yok | Orta |
| KoalaEmptyState | Yok | Orta |
| KoalaAvatar | Yok | Dusuk |
| KoalaBadge | Yok | Dusuk |
| KoalaBottomSheet | Yok | Dusuk |

## Sonuc

Tasarim sistemi %30 oturmus durumda. Kalan %70 ekrandan ekrana farklilik gosteriyor.
Bu hem kullanici deneyimini bozuyor hem de Claude'un "dogru" tasarim kararini vermesini zorlastiriyor.

Oncelikli adim: Once mevcut widget'lari canonical hale getir, sonra tum ekranlari bunlara migrate et.
