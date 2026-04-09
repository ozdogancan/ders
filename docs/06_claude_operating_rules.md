# Claude Operating Rules - Koala Project

## Genel Kurallar

1. **Tek seferde tek modul** - Birden fazla modulu ayni anda degistirme
2. **Once oku, sonra degistir** - Bir dosyaya dokunmadan once tamamini oku ve anla
3. **Yan etki kontrolu** - Degisiklik yaptiginda, o dosyayi import eden tum dosyalari kontrol et
4. **Minimum degisiklik** - Istenen isi en az satir degisikligiyle yap
5. **Mevcut pattern'i takip et** - Yeni pattern icat etme, mevcut calisan yapiyi koru

## Yasak Operasyonlar

- **Toplu refactor yasak** - "Tum dosyalarda su degisikligi yap" gibi genis islemler yapma
- **Dependency ekleme yasak** (onay almadan) - pubspec.yaml'a yeni paket ekleme
- **Routing degistirme yasak** (onay almadan) - Mevcut route yapisini bozma
- **State management degistirme yasak** (onay almadan) - setState'i Riverpod'a cevirmek gibi
- **Dosya silme yasak** - Kullanilmadigini dusunsen bile silme, sadece raporla
- **Theme degistirme yasak** (onay almadan) - Renk, font degisiklikleri global etkili

## Kritik Dosyalar - Ekstra Dikkat

Bu dosyalara dokunurken MUTLAKA once durumu raporla:

| Dosya | Neden Kritik |
|-------|-------------|
| main.dart | App initialization, tum provider'lar burada |
| app.dart | Routing, theme, global yapilandirma |
| supabase_service.dart | Tum DB islemleri, credential'lar |
| koala_ai_service.dart | AI entegrasyonu, prompt'lar |
| chat_detail_screen.dart | 2993 LOC, en kirilgan dosya |
| auth_service.dart | Giris/kayit, token yonetimi |

## Dosya Degistirme Protokolu

Her degisiklik icin su adimlar:

1. **Degistirilecek dosyayi tam oku**
2. **Bu dosyayi import eden dosyalari bul**
3. **Degisiklik planini acikla** (ne yapacagini, neden yapacagini)
4. **Kullanicidan onay al**
5. **Degisikligi yap**
6. **Yan etkileri kontrol et**

## Commit Kurallari

- Her mantiksal degisiklik ayri commit
- Commit mesaji Turkce, aciklayici
- Ornek: "chat: mesaj listesi ayri widget'a cikarildi"
- Birden fazla modulu etkileyen commit YAPMA

## Raporlama Formati

Her gorev sonunda su formatta rapor ver:

```
## Yapilan Is
- [ne yapildi]

## Degisen Dosyalar
- [dosya adi]: [ne degisti]

## Yan Etkiler
- [varsa listele, yoksa "Yok"]

## Bilinen Kisitlamalar
- [varsa listele]

## Sonraki Adim Onerisi
- [ne yapilmali]
```

## Widget Kullanim Kurallari

- Buton: KoalaButton kullan, ElevatedButton/TextButton dogrudan kullanma
- Kart: KoalaCard kullan
- Input: KoalaTextField kullan
- Yeni canonical widget lazimsa once tanimla, sonra kullan

## Naming Convention

- Dosyalar: snake_case (tutor_detail_screen.dart)
- Siniflar: PascalCase (TutorDetailScreen)
- Degiskenler: camelCase (tutorName)
- Sabitler: camelCase (defaultPadding)
- Widget dosyalari: snake_case, sonunda _widget veya _card veya _bar

## Import Sirasi

1. dart: paketleri
2. package: flutter
3. package: dis paketler (riverpod, supabase, vs.)
4. package: proje ici (koala/...)
5. relative import'lar
