# Koala — Product Roadmap
**Son guncelleme:** 2026-04-10
**Format:** Now / Next / Later

---

## Ozet

| Faz | Odak | Sure | Durum |
|-----|------|------|-------|
| **MVP** | Guided flow + AI chat + evlumba + profesyonel form | 4 hafta | Baslamadi |
| **Phase 2** | Coklu tedarikci + profesyonel profilleri + sponsorlu | 6-8 hafta | Planlanmadi |
| **Phase 3** | B2B white-label + marketplace | 8-12 hafta | Vizyon |

---

## NOW — MVP (Hafta 1-4)

> Hedef: Kullanici 2 dakikada kisisel stil analizi + urun onerisi alsin.
> Basari kosulu: Guided flow tamamlama > %60, urun tiklama > %15

### Hafta 1: Guided Discovery Flow + Gorseller

| ID | Is | Oncelik | Durum |
|----|---|---------|-------|
| MVP-01 | Guided flow UI — 4 adimli ekran | P0 | Not Started |
| MVP-02 | Adim 1: Oda secimi (salon, yatak odasi, mutfak, sifirdan, fikir) | P0 | Not Started |
| MVP-03 | Adim 2: Stil gorselleri secimi (5 kategori, 20+ gorsel) | P0 | Not Started |
| MVP-04 | Adim 3: Butce araligi secimi | P0 | Not Started |
| MVP-05 | Stil gorsel seti hazirlama (stok foto veya AI uretim) | P0 | Not Started |
| MVP-06 | Guided flow responsive tasarim (mobil + desktop) | P0 | Not Started |

**Bagimlilklar:** Stil gorselleri nereden gelecek (Q2 — open question)
**Cikti:** Kullanici 4 adimi tamamlayip sonuc ekranina ulasabilir

### Hafta 2: AI Entegrasyonu + Sonuc Ekrani

| ID | Is | Oncelik | Durum |
|----|---|---------|-------|
| MVP-07 | Guided flow sonucunu AI'a gonder → kisisel stil analizi | P0 | Not Started |
| MVP-08 | Sonuc ekrani: stil ozeti karti | P0 | Not Started |
| MVP-09 | Sonuc ekrani: renk paleti karti | P0 | Not Started |
| MVP-10 | Sonuc ekrani: urun onerileri (evlumba entegrasyonu) | P0 | Not Started |
| MVP-11 | Urun karti: gorsel + isim + fiyat + "Satin Al" linki | P0 | Not Started |
| MVP-12 | Butce filtreleme — urunler secilen araliga uygun | P0 | Not Started |
| MVP-13 | Sonuc kaydetme (local storage) | P0 | Not Started |

**Bagimlilklar:** evlumba urun verisi API mi statik mi (Q1 — open question)
**Cikti:** AI kisisel plan sunar, kullanici urunleri gorup tiklayabilir

### Hafta 3: Chat + Profesyonel Form + Analytics

| ID | Is | Oncelik | Durum |
|----|---|---------|-------|
| MVP-14 | Sonuc ekranindan chat'e gecis butonu | P0 | Not Started |
| MVP-15 | Chat context tasima — guided flow verisini chat'e aktar | P0 | Not Started |
| MVP-16 | "Profesyonelle Tanisin" butonu + form ekrani | P0 | Not Started |
| MVP-17 | Profesyonel form: isim, telefon, sehir, ihtiyac aciklamasi | P0 | Not Started |
| MVP-18 | Form verisi Supabase'e kayit | P0 | Not Started |
| MVP-19 | Admin panelde profesyonel talep listesi | P0 | Not Started |
| MVP-20 | Analytics event'leri: flow_start, flow_complete, product_click, form_submit | P0 | Not Started |

**Bagimlilklar:** Mevcut chat altyapisi (stabil — tamamlandi)
**Cikti:** Tam MVP akisi calisiyor, metrikler olculuyor

### Hafta 4: Test + Polish + Deploy

| ID | Is | Oncelik | Durum |
|----|---|---------|-------|
| MVP-21 | End-to-end test: guided flow → sonuc → chat → form | P0 | Not Started |
| MVP-22 | Mobil responsive test ve fix | P0 | Not Started |
| MVP-23 | Loading/error/empty state'ler (canonical widget'lar) | P0 | Not Started |
| MVP-24 | Ana sayfada "Onceki Analizlerin" bolumu | P1 | Not Started |
| MVP-25 | Performans kontrolu (logo, asset boyutlari, lazy load) | P1 | Not Started |
| MVP-26 | Production build + Vercel deploy | P0 | Not Started |

**Cikti:** MVP canli, metrik toplaniyor

---

## NEXT — Phase 2 (Hafta 5-12)

> Hedef: Platform yapisini kur — coklu tedarikci + profesyonel profilleri
> Baslama kosulu: MVP metrikleri tutarsa (flow tamamlama > %50, MAU > 500)

### Coklu Tedarikci Altyapisi

| ID | Is | Oncelik |
|----|---|---------|
| P2-01 | Tedarikci API abstraction layer — evlumba'ya bagimli olmayan yapi | P0 |
| P2-02 | Urun katalogu DB modeli (Supabase) | P0 |
| P2-03 | Ikinci tedarikci entegrasyonu (hedef: IKEA veya Vivense) | P0 |
| P2-04 | AI onerilerinde coklu tedarikci kaynagi gosterme | P0 |
| P2-05 | Fiyat karsilastirma karti | P1 |

### Profesyonel Profilleri

| ID | Is | Oncelik |
|----|---|---------|
| P2-06 | Profesyonel kayit akisi | P0 |
| P2-07 | Profil sayfasi: portfolio, uzmanlik alani, sehir, puan | P0 |
| P2-08 | Profesyonel listeleme ekrani (sehir + uzmanlik filtre) | P0 |
| P2-09 | Kullanici → profesyonel mesajlasma | P1 |
| P2-10 | Profesyonel abonelik modeli (aylik uyelik) | P1 |
| P2-11 | Profesyonel dashboard (gelen talepler, istatistikler) | P1 |

### Kullanici Deneyimi Gelistirme

| ID | Is | Oncelik |
|----|---|---------|
| P2-12 | Guided flow icinde fotograf yukleme + AI analiz | P1 |
| P2-13 | Sonuc paylasma (WhatsApp / link) | P1 |
| P2-14 | Coklu oda destegi (ayni kullanici birden fazla analiz) | P1 |
| P2-15 | Admin metrik dashboard (gorsel grafikler) | P1 |
| P2-16 | Push notification ("Yeni oneriler var") | P2 |

---

## LATER — Phase 3 (Hafta 13+)

> Hedef: Gelir kanallarini coklastir, B2B acil
> Baslama kosulu: Phase 2 tamamlanmis, MAU > 2000, profesyonel taraf aktif

| ID | Is | Aciklama |
|----|---|---------|
| P3-01 | Sponsorlu urun onerileri | Marka odemesi ile one cikartilan urunler |
| P3-02 | A/B test altyapisi | Guided flow varyantlari, farkli AI prompt'lar |
| P3-03 | B2B white-label API | Markalara ozel Koala AI entegrasyonu |
| P3-04 | Profesyonel puan/yorum sistemi | Kullanicidan profesyonele review |
| P3-05 | AR/gorsel deneyim | AI ile odada mobilya gorsellestirme |
| P3-06 | Coklu dil destegi | Ingilizce, Arapca (bolgesel buyume) |
| P3-07 | Mobil native uygulama | iOS/Android (Flutter zaten destekliyor) |

---

## Risk Haritasi

| Risk | Olasilik | Etki | Azaltma |
|------|----------|------|---------|
| evlumba urun verisi gecikir | Orta | Yuksek | Statik urun listesi ile baslayabilirsiniz |
| Stil gorselleri telif sorunu | Dusuk | Yuksek | AI ile gorsel uretim veya lisansli stok foto |
| Gemini API maliyet artisi | Dusuk | Orta | Edge function proxy ile cache + rate limit |
| Kullanici guided flow tamamlamaz | Orta | Yuksek | 3 adima dusur, progress bar ekle |
| Profesyonel tarafa ilgi dusuk | Orta | Orta | Phase 2'de test et, MVP'de sadece form |

---

## Karar Noktalari

| Tarih | Karar | Veri Kaynagi |
|-------|-------|-------------|
| MVP + 1 hafta | Flow cok mu uzun? 3 adima dusurulmeli mi? | Flow tamamlama orani |
| MVP + 1 ay | Phase 2'ye gecmeli miyiz? | MAU, retention, urun tiklama |
| MVP + 2 ay | Profesyonel tarafi MVP'ye dahil etmeli miyiz? | Form dolum sayisi |
| Phase 2 + 1 ay | Hangi ikinci tedarikci? | Kullanici talepleri, tedarikci ilgisi |
| Phase 2 + 2 ay | B2B'ye gecmeli miyiz? | Marka ilgisi, platform metrikler |

---

## Basari Olcum Takvimi

| Zaman | Olculecek | Hedef |
|-------|----------|-------|
| MVP + 1 hafta | Guided flow tamamlama | > %60 |
| MVP + 1 hafta | Urun tiklama orani | > %15 |
| MVP + 1 ay | 7 gunluk retention | > %20 |
| MVP + 1 ay | MAU | > 300 |
| MVP + 3 ay | MAU | > 1000 |
| MVP + 3 ay | Aylik evlumba yonlendirme | > 500 |
| MVP + 3 ay | Aylik profesyonel form | > 50 |
