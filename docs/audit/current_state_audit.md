# Koala - Current State Audit
**Tarih:** 2026-04-09  
**Mod:** Salt okunur analiz - kod degisikligi yok

## Genel Bakis

| Metrik | Deger |
|--------|-------|
| Toplam Dart dosyasi | 79 |
| Toplam Dart LOC | ~26,600 |
| Ekran sayisi | 32 |
| Servis dosyasi | 8 |
| Widget dosyasi | 15+ |
| Test dosyasi | 0 |
| Python script (root) | 73 adet |
| Olu alt proje | 3 (koala-v2, koala-splitview, koala-grupA) |

## Teknoloji Stack

- **Frontend:** Flutter Web (Dart)
- **Auth:** Firebase Authentication
- **Database:** Supabase (PostgreSQL + REST API)
- **AI:** Google Gemini (gemini-2.0-flash-001)
- **AI Proxy:** Supabase Edge Functions (Deno/TypeScript)
- **Push:** Supabase Edge Function (send-push-notification)
- **Hosting:** Vercel (build/web deploy)
- **State:** Riverpod (minimal) + StatefulWidget (cogunluk)

## Deploy Sureci

1. `flutter build web` 
2. `git add -f build/web` (force add)
3. Push to GitHub → Vercel auto-deploy
4. Vercel root: `build/web`

## Repo Sagligi

### Kritik Sorunlar
1. **73 Python scripti root'ta** - tek seferlik fix/migration dosyalari, hicbiri aktif kullanilmiyor
2. **3 olu alt proje** - koala-v2/, koala-splitview/, koala-grupA/ klasorleri karmasiklik yaratiyor
3. **Sifir test** - hicbir ekran veya servis test edilmemis
4. **5.5 MB logo** - koala_logo_no_bg.png performansi olumsuz etkiliyor
5. **Hardcoded credentials** - Supabase key ve URL dogrudan kodda
6. **chat_detail_screen.dart 2993 LOC** - tek dosyada cok fazla sorumluluk

### Orta Sorunlar
1. State management tutarsiz - Riverpod var ama cogu ekran local state
2. Naming convention karisik - snake_case + PascalCase dosya isimleri
3. Bazi ekranlar duplicate/overlap - ornegin profil duzenleme alanlarinda
4. Widget extraction yetersiz - buyuk ekranlar monolitik
5. Error handling tutarsiz - bazi yerlerde try-catch, bazi yerlerde hic yok

### Dusuk Oncelik
1. Kullanilmayan import'lar var
2. Bazi TODO/FIXME comment'leri birikmi
3. pubspec.yaml'da kullanilmayan dependency'ler olabilir
