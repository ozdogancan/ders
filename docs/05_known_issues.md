# Known Issues - Koala Project
**Son guncelleme:** 2026-04-09

## Kritik Sorunlar

### KI-001: chat_detail_screen.dart 2993 LOC
- **Durum:** Acik
- **Etki:** Yuksek - dosya cok buyuk, her degisiklik riskli
- **Cozum plani:** Faz 3'te bolunecek

### KI-002: Hardcoded Credentials
- **Durum:** Acik
- **Etki:** Yuksek - guvenlik riski, degisiklik zor
- **Dosyalar:** supabase_service.dart, koala_ai_service.dart
- **Cozum plani:** Faz 2'de AppConfig'e tasinacak

### KI-003: Root'ta 73 Python Scripti
- **Durum:** Acik
- **Etki:** Orta - repo kirlilik, Claude'u sasirtiyor
- **Cozum plani:** Faz 0'da arsivlenecek

### KI-004: 3 Olu Alt Proje
- **Durum:** Acik
- **Etki:** Orta - koala-v2, koala-splitview, koala-grupA kullanilmiyor
- **Cozum plani:** Faz 0'da kaldirilacak

## Orta Sorunlar

### KI-005: State Management Tutarsizligi
- **Durum:** Acik
- **Etki:** Orta - Riverpod + setState karisik kullanim
- **Cozum plani:** Faz 4'te karar alinacak

### KI-006: Error Handling Tutarsizligi
- **Durum:** Kismen cozuldu
- **Etki:** Dusuk - canonical widget'lar mevcut, 8 ekranda ErrorState/ErrorView aktif
- **Kalan:** Bazi ekranlarda hala try-catch sonrasi sadece print() var, UI'da hata gosterilmiyor

### KI-007: Logo 5.5 MB
- **Durum:** Acik
- **Etki:** Orta - web yukleme suresi
- **Cozum plani:** Faz 0'da optimize edilecek

### KI-008: Sifir Test
- **Durum:** Acik
- **Etki:** Orta - degisikliklerin dogrulugu kontrol edilemiyor
- **Cozum plani:** Stabilizasyon sonrasinda test ekleme fazi

## Dusuk Oncelik

### KI-012: 11 inline CPI kaldi (bilerek birakildi)
- **Durum:** Tasarim karari - degistirilmeyecek
- **Etki:** Yok - buton/inline spinner'lar LoadingState ile degistirilmemeli
- **Aciklama:** Buton icindeki kucuk (18-22px) spinner'lar, pagination spinner'lar, image placeholder'lar

### KI-009: Kullanilmayan Import'lar
- **Durum:** Acik
- **Etki:** Dusuk - derleme uyarilari

### KI-010: Naming Convention Tutarsizligi
- **Durum:** Acik
- **Etki:** Dusuk - okunabilirlik

### KI-011: Widget Extraction Yetersizligi
- **Durum:** Acik
- **Etki:** Dusuk - tekrar eden UI kodu

## Cozulmus Sorunlar

### KI-001: chat_detail_screen.dart 2993 LOC → COZULDU
- **Cozum:** 9 kart widget'i ayri dosyalara cikarildi (lib/views/chat/widgets/)
- **Sonuc:** 2993 → 1702 LOC, 0 compile error
- **Tarih:** 2026-04-09

### KI-003: Root'ta 73 Python Scripti → COZULDU
- **Cozum:** scripts/archive/ altina tasindi
- **Tarih:** 2026-04-09

### KI-004: 3 Olu Alt Proje → COZULDU
- **Cozum:** scripts/archive/dead_projects/ altina tasindi
- **Tarih:** 2026-04-09

### KI-007: Logo 5.5 MB → COZULDU
- **Cozum:** 5.3 MB → 129 KB optimize edildi
- **Tarih:** 2026-04-09

---

## Sorun Ekleme Formati

Yeni sorun eklerken:
```
### KI-0XX: Kisa baslik
- **Durum:** Acik / Devam ediyor / Cozuldu
- **Etki:** Kritik / Yuksek / Orta / Dusuk
- **Aciklama:** (opsiyonel detay)
- **Cozum plani:** (ne yapilacak)
```
