# Koala - Recommended Stabilization Plan
**Tarih:** 2026-04-09

## Genel Strateji

Koala'yi yeniden yazmiyoruz. Mevcut calisan yapiyi koruyarak, kontrollü adimlarla stabilize ediyoruz.

**Toplam tahmini sure:** 4-5 gun (her gun 2-3 saat calisma)

---

## Faz 0: Repo Temizligi (Gun 1 - Sabah)

### 0.1 Python Scriptlerini Arsivle
```
mkdir scripts/archive
mv *.py scripts/archive/
```
- 73 Python dosyasi root'tan kaldirilir
- Claude artik bunlari proje kodu sanmaz
- Git history korunur

### 0.2 Olu Alt Projeleri Kaldir
```
# Bu klasorler aktif kullanilmiyor:
koala-v2/
koala-splitview/
koala-grupA/
```
- Sil veya `.gitignore`'a ekle
- Claude'un context'ini temizler

### 0.3 Logo Optimize Et
- koala_logo_no_bg.png: 5.5 MB → ~150 KB hedef
- Web build boyutunu dusurur

### 0.4 .gitignore Guncelle
- build/ klasoru gitignore'da olmali (Vercel deploy icin ayri strateji)
- Python cache dosyalari
- IDE dosyalari

**Beklenen sonuc:** Temiz repo, Claude icin net context

---

## Faz 1: Kurallar ve Sinirlar (Gun 1 - Ogleden Sonra)

### 1.1 claude_operating_rules.md Olustur
- Claude'un hangi dosyalara nasil dokunacagi
- Modul sinirlari
- Yasak operasyonlar

### 1.2 module_boundaries.md Olustur
- Her modulun dosya listesi
- Modul arasi bagimliliklar
- Hangi modul hangi servisi kullanir

### 1.3 design_system_rules.md Olustur
- Canonical widget listesi
- Renk, spacing, typography kurallari
- Yeni widget ekleme kurallari

### 1.4 known_issues.md Olustur
- Bilinen buglar
- Yarim kalan ozellikler
- Teknik borc listesi

**Beklenen sonuc:** Claude artik kuralli calisir

---

## Faz 2: Credential ve Config Merkezilestirme (Gun 2)

### 2.1 config.dart Olustur
```dart
class AppConfig {
  static const supabaseUrl = '...';
  static const supabaseAnonKey = '...';
  static const geminiModel = 'gemini-2.0-flash-001';
  // tum sabitler burada
}
```

### 2.2 Tum Servislerde Hardcoded Degerleri Kaldir
- supabase_service.dart
- koala_ai_service.dart
- notification_service.dart
- Hepsinde AppConfig referansi kullan

**Beklenen sonuc:** Tek degisiklik noktasi, guvenli

---

## Faz 3: chat_detail_screen.dart Bolme (Gun 2-3)

Bu en buyuk tek risk. 2993 LOC'u bolmek sart.

### 3.1 Analiz
- Dosyadaki sorumluluk alanlari cikar
- Her alan icin ayri dosya planla

### 3.2 Bolme Plani
```
screens/chat/
  chat_detail_screen.dart      # Ana ekran (max 200 LOC)
  widgets/
    chat_message_list.dart     # Mesaj listesi
    chat_input_bar.dart        # Input alani
    chat_message_bubble.dart   # Tek mesaj balonu
    chat_ai_response.dart      # AI yanit gosterimi
  logic/
    chat_controller.dart       # Business logic
    chat_state.dart            # State yonetimi
```

### 3.3 Uygulama
- Once yeni dosyalari olustur
- Sonra ana ekrandan parcalari tasi
- Her adimda test et (manual)

**Beklenen sonuc:** En kirilgan dosya kontrol altinda

---

## Faz 4: State Management Karari (Gun 3)

### Karar: Riverpod mi, setState mi?

**Onerim:** Mevcut durumda hybrid yaklaşim:
- **Basit ekranlar:** setState kalsin (profile, settings, about)
- **Karmasik ekranlar:** Riverpod'a gec (chat, tutor_listing, booking)
- **Yeni ekranlar:** Hep Riverpod

### 4.1 Mevcut Provider'lari Denetle
### 4.2 Eksik Provider'lari Ekle (chat, booking)
### 4.3 Dokumante Et

**Beklenen sonuc:** State yonetimi tahmin edilebilir

---

## Faz 5: Canonical Widget Seti (Gun 3-4)

### 5.1 Mevcut Widget'lari Standartlastir
- KoalaButton → 3 varyant (primary, secondary, text)
- KoalaCard → base + tutor/lesson varyantlari
- KoalaTextField → validation destekli

### 5.2 Eksik Widget'lari Ekle
- KoalaAppBar
- KoalaLoadingState
- KoalaErrorState  
- KoalaEmptyState

### 5.3 Tum Ekranlari Migrate Et
- Ekran ekran, eski widget kullanımlarini yenileriyle degistir

**Beklenen sonuc:** Tutarli UI, Claude dogru widget secer

---

## Faz 6: Error Handling Standartlastirma (Gun 4)

### 6.1 Global Error Handler
### 6.2 Service Layer Error Pattern
### 6.3 UI Error Display Pattern

**Beklenen sonuc:** Hata durumlarinda tutarli kullanici deneyimi

---

## Faz 7: Modul Modul Feature Review (Gun 4-5)

Her modul icin:
1. Mevcut durumu incele
2. Eksikleri listele
3. Minimum fix uygula
4. Calisiyor mu kontrol et

Sira:
1. Auth (en stabil, hizli biter)
2. Onboarding
3. Profile/Settings
4. Tutor Listing/Detail
5. Booking
6. Chat/AI
7. Dashboard/Home

**Beklenen sonuc:** Her modul stabil ve dokumante

---

## Basari Kriterleri

Stabilization tamamlandiginda:
- [ ] Root'ta Python scripti yok
- [ ] Olu alt projeler kaldirildi
- [ ] chat_detail_screen.dart < 300 LOC
- [ ] Tum credential'lar AppConfig'de
- [ ] Canonical widget seti tanimli ve kullaniliyor
- [ ] Her modul icin boundary dokumani var
- [ ] Claude operating rules yazili
- [ ] Known issues listesi guncel
- [ ] Error handling tutarli
- [ ] State management karari dokumante

---

## Onemli Kural

> Her faz sonunda `git commit` yap. Boylece bir sey bozulursa geri donebilirsin.
> Claude'a asla "tum projeyi duzelt" deme. Her seferinde tek faz, tek modul.
