# Koala

Flutter tabanli Koala uygulamasi. Firebase auth, Supabase veri katmani, n8n/edge-function entegrasyonlari ve Evlumba read-only veri kaynagi ile calisir.

## Tech Stack

- Flutter
- Firebase Auth + Firestore + Firebase Messaging
- Supabase (uygulama verisi, realtime, edge functions)
- Riverpod
- Gemini tabanli AI servisleri
- n8n cron / outbound queue entegrasyonu

## Folder Structure

```text
lib/
  core/
    config/
    router/
    theme/
  providers/
  services/
  views/
  widgets/
koala-db/
n8n-docs/
n8n-workflows/
supabase-edge-functions/
```

## Required Setup

1. Firebase'i Android/iOS/Web icin kur.
2. Supabase proje bilgilerini ve gerekli migration'lari uygula.
3. Gerekliyse `n8n-workflows` ve `supabase-edge-functions` klasorlerindeki kurulum adimlarini tamamla.
4. Uygulamayi gerekli `--dart-define` degerleriyle calistir.

```bash
flutter run ^
  --dart-define=AI_PROVIDER=gemini ^
  --dart-define=GEMINI_API_KEY=YOUR_KEY ^
  --dart-define=GEMINI_MODEL=gemini-2.5-flash ^
  --dart-define=SUPABASE_URL=YOUR_SUPABASE_URL ^
  --dart-define=SUPABASE_ANON_KEY=YOUR_SUPABASE_ANON_KEY ^
  --dart-define=EVLUMBA_SUPABASE_URL=YOUR_EVLUMBA_URL ^
  --dart-define=EVLUMBA_SUPABASE_ANON_KEY=YOUR_EVLUMBA_ANON_KEY
```

Optional Google Sign-In overrides:

- `--dart-define=GOOGLE_CLIENT_ID=...`
- `--dart-define=GOOGLE_SERVER_CLIENT_ID=...`
