# Koala — Product Requirements Document (PRD)
**Versiyon:** 1.0
**Tarih:** 2026-04-09
**Durum:** MVP Tanimi

---

## Problem Statement

Turkiye'de evine bir sey yapmak isteyen (yenileme, sifirdan doseme, tek oda degisikligi) milyonlarca kisi var. Bunlarin buyuk cogunlugu ne istedigini tam ifade edemiyor, bir ic mimara butcesi yetmiyor (5.000-50.000 TL), Pinterest'te saatlerce bakip karar veremiyor.

Sonuc: Ya hic bir sey yapmiyorlar, ya rastgele alisveris yapip pismin oluyorlar, ya da cok para harcayip beklentilerini karsilamayan sonuclar aliyorlar.

**Koala bu problemi cozer:** AI destekli kisisel tasarim danismani olarak kullanicinin tarzini anlar, butcesine uygun somut urunler onerir ve isterse bir profesyonelle tanistirir — ucretsiz.

---

## Product Vision

> Koala, herkesin cebindeki ic mekan tasarim danismani.
> Tarzini anlar, butcene uygun onerir, istersen profesyonelle tanistirir.

Koala bir e-ticaret sitesi **degildir**. Koala bir **eslestirme platformudur**:
- Kullaniciyi dogru urunle eslestirir (tedarikci entegrasyonlari)
- Kullaniciyi dogru profesyonelle eslestirir (ic mimar, dekorator)
- Markalari dogru musteri ile eslestirir (sponsorlu oneriler)

---

## Target Users

### Birincil: "Kararsiz Ev Sahibi"
- 25-45 yas, kadin agirlikli (%65-70)
- Evine bir sey yapmak istiyor ama nereden baslayacagini bilmiyor
- Butcesi sinirli (5K-30K TL arasi)
- Pinterest/Instagram'da ilham ariyor ama karara donusturemiyor
- Ic mimara butcesi yetmiyor veya "o kadar buyuk is degil" diye dusunuyor

### Ikincil: Profesyoneller (Phase 2)
- Ic mimarlar, dekoratorler, uygulama ekipleri
- Musteri bulmak istiyor
- Portfolyo gostermek istiyor

### Ucuncul: Markalar/Tedarikciler (Phase 2+)
- Mobilya/dekorasyon markalari
- Hedefli kitlelere urun gostermek istiyor

---

## Core User Journey (MVP)

```
[Kullanici siteye gelir]
        |
        v
[Guided Discovery - 4 Adim]
  1. "Evinde ne yapmak istiyorsun?"
     [Salon] [Yatak Odasi] [Mutfak] [Sifirdan] [Sadece Fikir]
  2. Stil Tespiti (3-5 gorsel secim)
     "Hangisi sana daha yakin?"
  3. Butce Araligi
     [5-15K] [15-30K] [30-50K] [50K+]
  4. AI Kisisel Plan
     → Stil ozeti + renk paleti
     → Urun onerileri (evlumba linki)
     → "Profesyonelle taniSmak ister misin?"
     → "Daha fazla konusmak ister misin?" → Chat
        |
        v
[AI Chat - Serbest Sohbet]
  - Stil hakkinda daha derin sorular
  - Spesifik urun arama
  - Fotograf yukleme + analiz
  - Butce detaylandirma
  - Profesyonel yonlendirme
```

---

## UX Karari: Guided-First, Chat-Second

| Karar | Gerekce |
|-------|---------|
| Ilk deneyim guided flow | Bos chat ekrani korkusu yok, kullanici ne yapacagini bilir |
| 4 adimda deger ver | Retention icin kritik — ilk 2 dakikada "vay beni anladi" hissi |
| Chat ikinci katman | Merak eden, daha fazla isteyen kullanici icin |
| Guided flow sonucu kaydet | Kullanici geri dondigunde kaldigi yerden devam eder |

---

## Business Model

### Katmanli Gelir Yapisi

| Katman | Mekanizma | Zamanlama |
|--------|-----------|-----------|
| **1. Affiliate** | Urun onerisi → tedarikci sitesine yonlendirme → %5-15 komisyon | MVP |
| **2. Lead Gen** | Profesyonele musteri yonlendirme → islem basi komisyon | MVP (basit form) |
| **3. Profesyonel Abonelik** | Aylik uyelik → profil, portfolio, oncelikli listeleme | Phase 2 |
| **4. Sponsorlu Oneriler** | Marka: "benim urunlerimi one cikar" → reklam geliri | Phase 2 |
| **5. B2B White-label** | Markalara ozel AI asistan → lisans geliri | Phase 3 |

### Tedarikci Entegrasyonu Mimarisi
- evlumba.com (mevcut, MVP)
- Yeni tedarikciler API/katalog entegrasyonu ile baglanir
- Koala tedarikci-agnostik calisir, en uygun urunu onerir

---

## Goals (MVP)

| # | Hedef | Olcum |
|---|-------|-------|
| G1 | Kullanici ilk 2 dakikada deger alsin | Guided flow tamamlama orani > %60 |
| G2 | AI onerileri aksiyona donussun | Urun karti tiklama orani > %15 |
| G3 | Kullanicilar geri donsun | 7 gunluk retention > %20 |
| G4 | Monetize temeli kurulsun | Aylik evlumba yonlendirme > 500 tiklama |
| G5 | Profesyonel ilgi olculsun | Aylik profesyonel form dolum > 50 |

---

## Non-Goals (MVP'de YOK)

| # | Kapsam Disi | Neden |
|---|------------|-------|
| NG1 | Coklu tedarikci entegrasyonu | Once tek tedarikci ile modeli kanitla |
| NG2 | Profesyonel dashboard/abonelik | Once talebi olc, sonra dashboard yap |
| NG3 | Odeme/siparis entegrasyonu | Koala satiS yapmaz, yonlendirir |
| NG4 | Mobil uygulama (native) | Web-first, PWA yeterli |
| NG5 | A/B test altyapisi | Manuel metrik takibi yeterli MVP icin |
| NG6 | Sosyal ozellikler (yorum, begeni) | Odagi dagitir |
| NG7 | Coklu dil destegi | Sadece Turkce, Turkiye pazari |

---

## User Stories

### Kararsiz Ev Sahibi (Birincil Kullanici)

**US-01: Guided Discovery**
> Bir kullanici olarak, bana sorulan 3-4 basit soruyla tarzimin belirlenmesini istiyorum, boylece ne istedigimi bilmesem bile kisisel oneriler alabilirim.

Kabul kriterleri:
- [ ] 4 adimli flow: oda secimi → stil gorselleri → butce → sonuc
- [ ] Her adim tek ekranda, tek aksiyonla tamamlanir
- [ ] Toplam sure 2 dakikayi gecmez
- [ ] Sonucta stil ozeti + renk paleti + urun onerileri gosterilir

**US-02: Urun Onerisi Goruntuleme**
> Bir kullanici olarak, tarzima ve butceme uygun somut urunleri gorselleriyle gormek istiyorum, boylece ne alacagimi bilebilirim.

Kabul kriterleri:
- [ ] Her urun: gorsel, isim, fiyat, neden onerildigi
- [ ] Tiklayinca tedarikci sitesine gider (yeni sekmede)
- [ ] En az 3, en fazla 8 urun gosterilir
- [ ] Butce araligina uygun urunler filtrelenir

**US-03: AI Chat ile Derinlestirme**
> Bir kullanici olarak, guided flow sonrasi AI ile serbest sohbet etmek istiyorum, boylece spesifik sorularima cevap alabilirim.

Kabul kriterleri:
- [ ] Guided flow sonucundaki "Daha fazla konusmak ister misin?" butonu chat'e yonlendirir
- [ ] Chat, guided flow'dan gelen context'i bilir (tarz, butce, oda)
- [ ] Kullanici fotograf yukleyebilir
- [ ] AI Turkce yanitlar verir

**US-04: Profesyonele Ulasma**
> Bir kullanici olarak, isin buyuklugune gore bir profesyonelle tanismak istiyorum, boylece kendim yapamayacagim isleri teslim edebilirim.

Kabul kriterleri:
- [ ] "Profesyonelle Tanisin" butonu guided flow sonucunda gosterilir
- [ ] Basit form: isim, telefon, sehir, ne yapmak istiyor
- [ ] Form gonderildikten sonra onay mesaji
- [ ] Formlar admin panelde listelenir

**US-05: Onceki Sonuclara Erisim**
> Bir kullanici olarak, daha once aldıgım stil analizine ve onerilere geri donmek istiyorum, boylece kararlilari tekrar gorebilirim.

Kabul kriterleri:
- [ ] Guided flow sonucu local storage'a kaydedilir
- [ ] Ana sayfada "Onceki Analizlerin" bolumu
- [ ] Tiklayinca sonuc ekrani tekrar acilir

### Admin

**US-06: Profesyonel Basvurulari Goruntuleme**
> Admin olarak, gelen profesyonel talep formlarini gormek istiyorum, boylece potansiyel musteri leadlerini takip edebilirim.

Kabul kriterleri:
- [ ] Admin panelde "Profesyonel Talepleri" sekmesi
- [ ] Liste: tarih, isim, sehir, talep detayi
- [ ] Durum: Yeni / Iletildi / Kapandi

**US-07: Temel Metrik Takibi**
> Admin olarak, guided flow tamamlama, urun tiklama ve profesyonel form oranlarini gormek istiyorum, boylece urunun performansini olcebilirim.

Kabul kriterleri:
- [ ] Admin panelde "Metrikler" sekmesi
- [ ] Gunluk/haftalik: flow baslama, tamamlama, urun tiklama, form gonderme
- [ ] Basit bar chart veya sayi gosterimi yeterli

---

## Requirements

### P0 — Must Have (MVP)

| ID | Gereksinim | Detay |
|----|-----------|-------|
| R01 | Guided Discovery Flow | 4 adim: oda → stil → butce → sonuc |
| R02 | Stil Gorselleri Seti | En az 20 gorsel, 5 farkli stil kategorisi |
| R03 | AI Stil Analizi | Guided flow sonucunda kisisel stil ozeti |
| R04 | Renk Paleti Onerisi | Tarz bazli renk paleti karti |
| R05 | Urun Onerileri (evlumba) | Butce + tarza uygun urunler, affiliate link |
| R06 | Chat Entegrasyonu | Guided flow sonrasindan chat'e gecis, context tasima |
| R07 | Profesyonel Ilgi Formu | Basit form: isim, tel, sehir, ihtiyac |
| R08 | Sonuc Kaydetme | Local storage ile onceki analizlere erisim |
| R09 | Temel Analytics | Flow tamamlama, urun tiklama, form gonderme event'leri |
| R10 | Responsive Web | Mobil ve desktop uyumlu |

### P1 — Nice to Have (Fast Follow)

| ID | Gereksinim | Detay |
|----|-----------|-------|
| R11 | Fotograf Analizi (guided flow icinde) | Oda fotosu yukle → AI analiz → oneriler |
| R12 | Sonuc Paylasma | WhatsApp/link ile sonuc paylasimi |
| R13 | Coklu Oda Destegi | Ayni kullanici birden fazla oda icin analiz |
| R14 | Admin Metrik Dashboard | Gorsel grafiklerle metrik takibi |
| R15 | Push Notification | "Yeni urun onerilerin var" bildirimi |

### P2 — Future (Phase 2+)

| ID | Gereksinim | Detay |
|----|-----------|-------|
| R16 | Coklu Tedarikci API | IKEA, Vivense, Kelebek vb. entegrasyonu |
| R17 | Profesyonel Profilleri | Portfolio, puan, yorum sistemi |
| R18 | Profesyonel Abonelik | Aylik uyelik + dashboard |
| R19 | Sponsorlu Oneriler | Marka tarafindan one cikartilan urunler |
| R20 | A/B Test Altyapisi | Guided flow varyantlari test etme |
| R21 | B2B White-label | Markalara ozel Koala AI |

---

## Success Metrics

### North Star Metric

> **Aylik AI onerisi sonrasi aksiyona gecen tekil kullanici sayisi**
> Aksiyon = urun tiklama + profesyonel form + plan kaydetme

### Leading Indicators (Gunler icinde olculur)

| Metrik | Hedef | Olcum |
|--------|-------|-------|
| Guided flow baslama orani | Ziyaretcinin %40'i | Analytics event |
| Guided flow tamamlama orani | Baslayanlarin %60'i | Analytics event |
| Urun kartina tiklama orani | Sonuc gorenlerin %15'i | Analytics event |
| Chat'e gecis orani | Sonuc gorenlerin %25'i | Analytics event |
| Profesyonel form dolum | Sonuc gorenlerin %5'i | Form submit event |

### Lagging Indicators (Haftalar icinde olculur)

| Metrik | Hedef | Olcum |
|--------|-------|-------|
| 7 gunluk retention | %20 | Tekrar ziyaret |
| Aylik aktif kullanici (MAU) | 1000+ (3. ayda) | Unique visitors |
| evlumba yonlendirme | 500+/ay | Affiliate tiklama |
| Profesyonel lead | 50+/ay | Form sayisi |

### Olcum Zamani
- **Lansman + 1 hafta:** Leading indicator'lari kontrol et
- **Lansman + 1 ay:** Retention ve MAU degerlendir
- **Lansman + 3 ay:** Monetize metrikleri degerlendir, Phase 2 karar ver

---

## Technical Architecture (Ozet)

| Katman | Teknoloji |
|--------|-----------|
| Frontend | Flutter Web (Dart) |
| Hosting | Vercel (static deploy) |
| AI | Google Gemini via Supabase Edge Function proxy |
| Database | Supabase (PostgreSQL + REST API) |
| Auth | Firebase Authentication |
| Analytics | Supabase analytics tablolari + admin panel |
| Tedarikci | evlumba.com (affiliate link, urun katalogu) |

Detayli mimari: `docs/02_current_architecture.md`

---

## Open Questions

| # | Soru | Cevaplamasi Gereken | Blocker? |
|---|------|--------------------|---------| 
| Q1 | evlumba urun katalogu API ile mi cekilecek yoksa statik liste mi? | Engineering | Evet |
| Q2 | Stil gorselleri nereden gelecek? (Stok foto, AI uretim, evlumba?) | Design + Business | Evet |
| Q3 | Profesyonel leadleri kime iletilecek? (Manuel mi, otomatik mi?) | Business | Hayir |
| Q4 | Affiliate komisyon orani ve tracking nasil calisacak? | Business | Hayir |
| Q5 | Guided flow sonuclarini Supabase'e mi local'e mi kaydedelim? | Engineering | Hayir |
| Q6 | Mevcut chat ekranini mi kullanacagiz yoksa yeni guided+chat hybrid mi? | Engineering + Design | Evet |

---

## Timeline Considerations

### MVP Tahmini Sure: 3-4 Hafta

| Hafta | Odak |
|-------|------|
| 1 | Guided flow UI (4 adim) + stil gorsel seti hazirlama |
| 2 | AI entegrasyonu (guided flow → stil analizi → urun onerisi) |
| 3 | Profesyonel form + analytics event'leri + chat entegrasyonu |
| 4 | Test, bug fix, polish, deploy |

### Bagimliliklar
- evlumba urun verisi (Q1 cozulmeli)
- Stil gorselleri (Q2 cozulmeli)
- Mevcut chat altyapisi stabil (tamamlandi — stabilization fazinda yapildi)

### Phase 2 Baslangic Kosulu
MVP metriklerinde:
- Guided flow tamamlama > %50
- Urun tiklama > %10
- MAU > 500
Bu kosullar saglanirsa Phase 2 baslar.

---

## Appendix: Rekabet Analizi

| Rakip | Ne Yapar | Koala Farki |
|-------|---------|-------------|
| Pinterest | Ilham galerisi, gorseller | Koala kisisel oneri verir, Pinterest pasif |
| Houzz | Profesyonel + urun + ilham | Koala AI-first, Houzz insan-first |
| IKEA Planner | 3D oda planlama | Koala tarz kesfi + urun onerisi, 3D yok |
| Havenly (ABD) | Online ic tasarim servisi | Koala Turkiye pazari, Turkce, yerel tedarikciler |
| Modanisa/Trendyol Ev | E-ticaret | Koala satis yapmaz, eslestirme yapar |

Koala'nin benzersiz konumu: **AI destekli, Turkce, yerel tedarikci entegrasyonlu, ucretsiz kisisel tasarim danismani.**
