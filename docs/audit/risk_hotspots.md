# Koala - Risk Hotspots
**Tarih:** 2026-04-09

## Kritik Risk Dosyalari

### 1. chat_detail_screen.dart (2993 LOC) - EN YUKSEK RISK
- **Sorun:** Tek dosyada 3000 satir kod - UI, business logic, state, AI entegrasyonu hepsi ic ice
- **Etki:** Claude bu dosyaya dokunursa yan etki olasiligi cok yuksek
- **Oneri:** En az 5 parcaya bolunmeli (chat UI, message list, input bar, AI logic, chat state)

### 2. koala_ai_service.dart (787 LOC) - YUKSEK RISK
- **Sorun:** Gemini API entegrasyonu, prompt yonetimi, response parsing hepsi tek dosyada
- **Etki:** AI davranisi degisirse tum uygulama etkilenir
- **Oneri:** Prompt'lar ayri dosyaya, API client ayri, response parser ayri

### 3. supabase_service.dart - YUKSEK RISK
- **Sorun:** Tum veritabani islemleri tek serviste, hardcoded credentials
- **Etki:** Herhangi bir tablo degisikligi tum CRUD'u etkileyebilir
- **Oneri:** Tablo bazli repository pattern'e gecis

### 4. main.dart + app.dart - ORTA RISK
- **Sorun:** Routing, initialization, provider setup hepsi burada
- **Etki:** Yeni ekran eklemek veya navigation degistirmek riskli
- **Oneri:** Route tanimlarini ayri dosyaya cikarmak

### 5. Root klasordeki 73 Python scripti - ORTA RISK
- **Sorun:** Hicbiri aktif degil ama repo'yu kirletiyor, Claude'u sasirtiyor
- **Etki:** Claude bunlari proje parcasi sanabilir, yanlis context olusturur
- **Oneri:** Hepsini scripts/archive/ altina tasinmali veya silinmeli

## Modul Bazli Risk Haritasi

| Modul | Stabilite | Risk | Aciklama |
|-------|-----------|------|----------|
| Auth | Stabil | Dusuk | Firebase Auth duz calisiyor |
| Onboarding | Stabil | Dusuk | Basit akis, az bagimlilik |
| Home/Dashboard | Orta | Orta | Veri cekme mantigi karisik |
| Tutor Listing | Orta | Orta | Filtreleme/siralama karmasik |
| Tutor Detail | Orta | Orta | Cok fazla bilgi tek ekranda |
| Chat/Messaging | Kirilgan | Yuksek | 2993 LOC tek dosya |
| AI Chat | Kirilgan | Yuksek | Gemini entegrasyonu hassas |
| Booking | Orta | Orta | Takvim/zaman mantigi |
| Profile | Stabil | Dusuk | Basit CRUD |
| Settings | Stabil | Dusuk | Basit ayarlar |
| Payment | Belirsiz | Yuksek | Tam calisip calismadigi net degil |

## Claude'un Sasma Noktalari

### Neden Claude bu repoda hata yapiyor?

1. **Dosya boyutu:** 2993 LOC'lik dosyada context window dolabiliyor, Claude parcayi gorup karar veriyor
2. **Duplicate logic:** Ayni is birden fazla yerde yapiliyor, Claude hangisini guncelleyecegini bilemiyor
3. **Implicit dependencies:** Servisler arasi bagimliliklar acik degil, bir degisiklik zincirleme kirilma yapiyor
4. **Naming tutarsizligi:** Bazen camelCase bazen snake_case, Claude yanlis convention uygulayabiliyor
5. **73 Python scripti:** Claude bunlari okuyup yanlis context cikarabiliyor
6. **State management karisikligi:** Riverpod var ama cogu yerde setState, Claude hangisini kullanacagini karistiriyor
7. **Hardcoded degerler:** URL, key gibi degerler kodda dagitik, Claude yanlislikla degistirebilir

## En Acil Mudahale Gereken 5 Alan

1. **chat_detail_screen.dart bolunmesi** - En buyuk tek risk
2. **Python scriptlerinin temizlenmesi** - Claude context kirliligi
3. **Credential'larin merkezilesmesi** - Guvenlik + bakim kolayligi
4. **State management karari** - Ya tamamen Riverpod ya da tamamen local, karisik olmasin
5. **Error handling standartlastirma** - Simdi tutarsiz, kullanici deneyimini bozuyor
