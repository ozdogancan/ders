# Product Scope - Koala

## Koala Ne Yapar?
Koala, yapay zeka destekli bir ic mekan tasarim asistanidir. Kullanicilar Koala AI ile sohbet ederek:

- **Stil analizi** alir (modern, minimalist, bohemian, vb.)
- **Renk paleti** onerileri gorur
- **Urun onerileri** alir (evlumba.com entegrasyonu)
- **Tasarimci eslestirme** yapar
- **Butce plani** olusturur
- **Fotograf analizi** yaptirir (mekan fotosu yukle → AI oneri)
- **Gorsel uretimi** ister (AI ile mekan gorseli)

## Koala Ne YAPMAZ?
- E-ticaret / odeme islemi (sadece evlumba.com'a yonlendirme)
- Tasarimci ile canli gorusme / video
- 3D modelleme / AR deneyimi
- Proje yonetimi / takvim
- Sosyal ag ozellikleri (yorum, begeni, paylasim)

## Hedef Kitle
- Evini dekore etmek isteyen bireyler
- Ic mekan tasarimina ilgi duyan kullanicilar
- Turkiye pazari (UI dili: Turkce)

## Ana Ekranlar ve Akislar

### 1. Onboarding
Yeni kullanici → Stil kesfi → Ilgi alani secimi → Ana sayfa

### 2. Ana Sayfa (Home)
Hizli aksiyonlar + ilham grid + trend kartlari

### 3. Chat (Ana Deneyim)
Kullanici mesaj yazar veya fotograf yukler → AI yanitlar → Kart widget'lari (stil, renk, urun, tasarimci, butce)

### 4. Tasarimcilar
Tasarimci listesi → Profil detay → Mesaj gonderme

### 5. Kaydedilenler
Begenilen urunler, planlar, koleksiyonlar

### 6. Profil / Ayarlar
Kullanici bilgileri, bildirim tercihleri

### 7. Admin Panel
Kullanici yonetimi, mesaj izleme, analitik, bildirim gonderme

## Teknik Sinirlamalar
- Flutter Web only (mobil native yok, su an)
- AI yanit suresi 3-8 sn (Gemini API gecikme)
- SharedPreferences ile local chat (max 50 sohbet)
- Supabase free tier limitleri
