# Current Architecture - Koala Project
**Son guncelleme:** 2026-04-09

## Stack

| Katman | Teknoloji |
|--------|-----------|
| Frontend | Flutter Web (Dart) |
| Auth | Firebase Authentication (Google, Phone, Email) |
| Database | Supabase (PostgreSQL + REST API) |
| AI | Google Gemini (gemini-2.0-flash-001) via Supabase Edge Function proxy |
| Push | Supabase Edge Function (send-push-notification) |
| Hosting | Vercel (build/web static deploy) |
| State | setState (27 ekran) + Riverpod (3 global provider) |

## Klasor Yapisi

```
lib/
├── main.dart                    # App initialization
├── core/
│   ├── config/
│   │   └── env.dart             # Environment variables (--dart-define)
│   └── theme/
│       ├── app_theme.dart       # ThemeData
│       └── koala_tokens.dart    # Design tokens (Colors, Spacing, Text, etc.)
├── models/                      # Data models
├── providers/                   # Riverpod providers (auth, unread, saved counts)
├── services/                    # Business logic services
│   ├── koala_ai_service.dart    # Gemini AI integration
│   ├── koala_image_service.dart # Image generation
│   ├── chat_persistence.dart    # SharedPreferences chat storage
│   ├── messaging_service.dart   # User-to-user messaging
│   ├── analytics_service.dart   # Event tracking
│   ├── profile_feedback_service.dart
│   ├── saved_items_service.dart
│   └── saved_plans_service.dart
├── views/                       # Screens
│   ├── chat/
│   │   └── widgets/             # Extracted chat card widgets (9 files)
│   ├── admin/                   # Admin panel screens
│   └── *.dart                   # Main app screens
└── widgets/                     # Shared/canonical widgets
    ├── koala_widgets.dart       # Barrel export
    ├── loading_state.dart       # Loading indicator
    ├── error_state.dart         # Error with retry
    ├── error_view.dart          # Typed errors (network/server/timeout)
    ├── empty_state.dart         # Empty list state
    ├── shimmer_loading.dart     # Shimmer skeleton loading
    ├── koala_logo.dart          # Logo widget
    ├── offline_banner.dart      # Connectivity banner
    ├── responsive_frame.dart    # Responsive layout wrapper
    ├── save_button.dart         # Save/bookmark button
    └── optimized_image.dart     # Cached network image
```

## State Management Karari

### Mevcut Durum
- **27 ekran:** setState kullanıyor
- **3 global provider:** Riverpod (auth state, unread counts, saved counts)
- **0 ekran:** ConsumerWidget/ConsumerStatefulWidget kullanmıyor

### Karar: Hybrid Yaklasim (Sabitlendi)
1. **Basit ekranlar:** setState KALSIN (profile, settings, about, admin screens)
2. **Global state:** Riverpod provider'lar KALSIN (auth, unread, saved)
3. **Yeni karmasik ekranlar:** Riverpod tercih edilsin
4. **Mevcut ekranlar:** setState'ten Riverpod'a gecis ZORUNLU DEGIL

> Onemli: Mevcut calisan setState yapisi bozulmamali.
> Riverpod migration sadece net fayda saglayacaksa yapilmali.

## Deploy Sureci

```
flutter build web → git add -f build/web → git push → Vercel auto-deploy
```

Vercel root directory: `build/web`

## AI Entegrasyonu

```
Kullanici → ChatDetailScreen → KoalaAIService → Supabase Edge Function (ai-proxy) → Gemini API
                                                                                         ↓
Kullanici ← Card Widgets ← JSON Response ← KoalaResponse parse ← ───────────────────────┘
```

AI response formati: `{"message": "...", "cards": [{"type": "...", "data": {...}}]}`

## Veritabani

- **Supabase PostgreSQL:** Kullanici profilleri, mesajlar, bildirimler, kaydedilenler
- **Firebase Auth:** Authentication (uid, email, displayName)
- **SharedPreferences:** Chat history (local, max 50 conversations)
- **Supabase Storage:** Kullanici yuklenen gorseller
