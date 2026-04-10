# CLAUDE.md
This file provides guidance to Claude Code when working with this repository.

## Project Overview
Koala is a Flutter-based AI interior design assistant. Users chat with Koala AI about home decoration — get style analysis, color palettes, product recommendations, designer matching, and budget plans. Powered by Gemini AI with evlumba.com marketplace integration.

## Run Command
```powershell
.\run.ps1
```
Or manually:
```
flutter run -d chrome --dart-define=AI_PROVIDER=gemini --dart-define=GEMINI_API_KEY=xxx --dart-define=GEMINI_MODEL=gemini-2.5-flash --dart-define=SUPABASE_URL=xxx --dart-define=SUPABASE_ANON_KEY=xxx
```

## Architecture

### Core Flow
Home Screen → ChatDetailScreen (intent-based) → KoalaAIService → Gemini API → Structured JSON response → Card widgets

### Key Files
- `lib/views/home_screen.dart` — Main screen with quick actions, inspiration grid, trend cards
- `lib/views/chat_detail_screen.dart` — Chat UI with card renderers (style, product, color, designer, budget, tips, question_chips)
- `lib/services/koala_ai_service.dart` — Gemini API with conversation history, intent routing
- `lib/services/koala_image_service.dart` — Gemini image generation
- `lib/services/chat_persistence.dart` — SharedPreferences chat storage
- `lib/core/constants/koala_prompts.dart` — AI system prompt + intent-specific prompts

### AI Card Types
- `question_chips` — Tappable options (handles both string[] and {label,value}[] formats)
- `style_analysis` — Style name, color palette, tags, description
- `product_grid` — Products with name, price, reason → evlumba.com deep link
- `color_palette` — Color swatches with HEX, name, usage
- `designer_card` — Designers with avatar, rating, bio → evlumba.com profile
- `budget_plan` — Category breakdown with amounts and priorities
- `quick_tips` — Tip list (handles string and {emoji, text} formats)
- `image_prompt` — AI image generation trigger
- `before_after` — Transformation story with changes list

### Auth
Firebase Auth (Google, Phone, Email). Dev bypass in `auth_gate.dart` (`devBypass = true`).

### Storage
- Chat history: SharedPreferences (local, max 50 conversations)
- Images: Supabase Storage
- User profiles: Firestore

### Conventions
- UI language: Turkish
- Theme: Purple accent (#6C5CE7)
- All AI responses must be JSON: `{"message": "...", "cards": [...]}`
- No plain text AI responses

## Stabilization Mode - TAMAMLANDI → MVP MODE AKTIF

> Stabilizasyon tamamlandi. Simdi MVP gelistirme modundayiz.
> Guided Discovery Flow + evlumba entegrasyonu + profesyonel form

### Zorunlu Okunan Dokumanlar
Claude bu repo uzerinde calismadan once asagidaki dokumanlari MUTLAKA okumali:

1. `docs/07_product_spec.md` — PRD: kullanici hikayeleri, gereksinimler, basari metrikleri
2. `docs/08_roadmap.md` — MVP roadmap: hafta hafta plan
3. `docs/06_claude_operating_rules.md` — Calisma kurallari, yasak operasyonlar
4. `docs/04_module_boundaries.md` — Modul sinirlari, etki matrisi
5. `docs/03_design_system_rules.md` — UI/tasarim kurallari
6. `docs/05_known_issues.md` — Bilinen sorunlar listesi

### Audit Raporlari
- `docs/audit/current_state_audit.md` — Genel durum
- `docs/audit/module_inventory.md` — Ekran ve servis envanteri
- `docs/audit/risk_hotspots.md` — Risk alanlari
- `docs/audit/design_inconsistencies.md` — Tasarim tutarsizliklari
- `docs/audit/recommended_stabilization_plan.md` — Stabilizasyon plani

### Temel Kurallar
- Tek seferde tek modul degistir
- Shared dosyalara dokunmadan once tum etkilenen modulleri kontrol et
- chat_detail_screen.dart (2993 LOC) en kirilgan dosya - ekstra dikkat
- Her degisiklik sonrasi rapor ver
