# Koala Flutter App — Backend & Functionality Audit (V2 Input)

**Date**: 2026-06-10  
**Scope**: Read-only deep audit of lib/services, lib/providers, lib/helpers, and koala-api endpoints  
**Platform**: Flutter (web + Android + iOS)

---

## 1. ARCHITECTURE SUMMARY (10 lines)

**Auth Layer**: Firebase Auth (Google/Apple OAuth; anonymous disabled in production). Supabase users table synced on login, x-user-id header injected for RLS. Evlumba professional login bridge via /api/auth/evlumba/\* (magic link + Evlumba DB sync).

**Data Layer**: Koala primary Supabase (xgefjepaqnghaotqybpi) holds users, conversations, messages, notifications, saved_items, koala_cards. Evlumba read-only Supabase (vgtgcjnrsladdharzkwn, anon) feeds designer_projects, profiles for search/swipe/match. Firebase Firestore syncs user metadata (legacy, mostly unused).

**API Gateway**: koala-api (Vercel Next.js, https://koala-api-olive.vercel.app) proxies Gemini chat, enforces per-user quota, bridges messaging to Evlumba DB, handles RevenueCat verification (Android only; iOS deferred). 51 endpoints.

**Service Ecosystem**: 47+ service classes (auth, billing, quota, messaging, AI chat, restyle, swipe, analytics) + 4 Riverpod providers (auth state, pro status, saved counts, unread). Boot parallelizes Firebase, Supabase, EvlumbaLiveService prefetch, BillingService with 12-60s timeouts.

**Key Features**: Swipe-deck (aesthetic discovery), restyle (3-variant Gemini Image + judge), Koala AI chat (Gemini with function calling), Evlumba pro matching, direct messaging (user↔designer), designer quotes, saved projects/collections, pro gating (RevenueCat Android + server quota), push notifications (FCM).

---

## 2. SERVICE LAYER MAP (CONDENSED)

47 services identified. Key categories:

- **Auth**: FirebaseService, AuthTokenService, authStateProvider (WORKING)
- **Billing**: BillingService (Android live, iOS deferred), QuotaService (30s cache), UsageLimitService (client daily counters)
- **AI Chat**: KoalaAIService (Gemini via /api/chat proxy, function calling), TasteProfileService (user preference injection)
- **Restyle**: MekanRestyleService (3-variant batch), MekanAnalyzeService (room type hints), ReplicateService (legacy, dead)
- **Messaging**: MessagingService (CRUD conversations, messages, realtime, Evlumba bridge, retry queue, free consult gate)
- **Data Fetch**: EvlumbaLiveService (read-only Evlumba DB, prefetch + passive retry), SavedItemsService (CRUD with data URL stripping issue)
- **Notifications**: NotificationsService, PushHandlerService (foreground only; background badge TODO)
- **Analytics**: AnalyticsService (batching, lifecycle flush TODO), ProductAnalyticsService

### Critical Issues Found

| Service | Issue | Severity |
|---------|-------|----------|
| MekanRestyleService | All variants rejected → exception uncaught → crash | **HIGH** |
| SavedItemsService | Data URL stripped, re-upload never called → missing image | **HIGH** |
| AnalyticsService | Lifecycle flush not wired → event loss on crash | **MEDIUM** |
| KoalaAIService | Moondream API disabled (401) → 8s wasted timeout | **LOW** |
| MessagingService | Chat list N+1 mitigated by RPC; fallback available | LOW |

---

## 3. DATA FLOWS (Summary)

**Auth**: GoogleSignIn → FirebaseAuth → Firestore + Supabase sync → x-user-id header → RLS  
**Swipe**: Deck (prefetch warm) → like/pass → TasteProfileService → analytics → paywall if quota hit  
**Restyle**: Photo → MekanRestyleService.restyleBatch() → 3-variant parallel → SavedItemsService.saveItem() → projectsTick notify  
**Koala AI**: User message → KoalaAIService.askWithIntent() → intent routing → Gemini tools (search_products/search_projects/search_designers) → return KoalaResponse { message, cards }  
**Messaging**: getOrCreateConversation (/api/conversations/ensure) → sendMessage → bridge to Evlumba (fire-and-forget + retry queue) → realtime listen → markAsRead (RPC with fallback)  
**Push**: FCM token register → Supabase fcm_tokens → notification arrives (background no-op, foreground routes) → deep link to conversation  

---

## 4. VERCEL API ENDPOINTS (51 TOTAL)

**Key Endpoints**:
- /api/chat (Gemini proxy)
- /api/restyle/batch (3-variant generation)
- /api/billing/{status,verify,restore}
- /api/quota/usage
- /api/conversations/ensure (RLS bypass)
- /api/messages/{bridge,inbound}
- /api/saved-items
- /api/auth/evlumba/{login,magic/*,forgot}
- /api/admin/\*, /api/cron/\* (admin + scheduled tasks)
- /api/analytics (batch event upload)
- +35 more (mostly working, no major issues found)

**Broken**: /api/analyze-room (Moondream, 401 key)

---

## 5. DEAD CODE & UNIMPLEMENTED

| Item | Status | Fix Direction |
|------|--------|----------------|
| ReplicateService (restyle) | DEAD | Remove; replaced by MekanRestyleService |
| Moondream endpoint | BROKEN | Remove; Gemini 2.5 Flash sufficient |
| Analytics lifecycle flush | TODO | Add WidgetsBindingObserver, wire flush on pause/detach |
| Push badge (background) | TODO | Implement badge increment in FCM background handler |
| Image re-upload (SavedItems) | DEAD | Wire UploadService or store base64 in extraData |
| Shared collections UI | PARTIAL | Schema exists; build UI in v2 |
| Quote payment (Stripe) | DEAD | Only acceptance recorded; payment Sprint 5 |

---

## 6. TOP 10 V2 FIXES

1. **Restyle Variant Crash** (2h, HIGH): Catch all-rejected-variants exception, retry with lower judge threshold or show user error.
2. **Saved Item Missing Image** (4h, HIGH): Wire UploadService.upload() after saveItem(), show placeholder until uploaded.
3. **Analytics Lifecycle Flush** (1h, MEDIUM): Add WidgetsBindingObserver, call Analytics.flushNow() on pause/detached.
4. **Moondream Removal** (1h, LOW): Delete _moondreamPreAnalyze() call and endpoint reference.
5. **Chat History Windowing** (2h, LOW): Increase window (30→50) if token budget allows.
6. **Swipe Deck Empty State** (3h, LOW): Add skeleton UI + loading indicator while prefetch/fetch in progress.
7. **Bridge Retry Queue SQLite** (6h, MEDIUM): Migrate from SharedPreferences to sqflite for better overflow handling.
8. **Casual Chat Retry Logic** (2h, LOW): Implement exponential backoff (1s, 2s, 4s) for Gemini timeout.
9. **Taste Profile Invalidation** (1h, LOW): Call invalidateTasteCache() in swipe_screen after like().
10. **Admin Monitoring Dashboard** (8h, MEDIUM): Wire Crashlytics + Sentry, add read-only RPC for health metrics (API errors, quota rate, restyle success %, latencies).

---

## 7. BOOT-TIME INITIALIZATION

**Critical sequence** (main.dart):
1. Parallel (Future.wait): SavedItemsService.warmFromDiskCache, EvlumbaLiveService.warmDeckFromDisk, BillingService.initialize
2. Firebase.initializeApp (12s timeout)
3. Supabase.initialize (implicit)
4. Anonymous sign-out check / sign-in (6s timeout)
5. initRouterState (6s timeout)
6. Unawaited prefetch: EvlumbaLiveService.prefetchForHome (2-5s background)

**Risk**: All three 12s/6s/6s timeouts could stack. **Mitigation**: Catch blocks + SplashScreen waits. No known hangs reported.

---

## 8. CONCLUSION

**Health**: GOOD, focused issues.

**Strengths**: Clean service architecture, robust error handling, quota gating (client + server), boot parallelization.

**Weaknesses**: Image loss (SavedItemsService), restyle crash (judge rejection), analytics gap (lifecycle), half-built features (collections, quote payment, iOS billing).

**V2 Priority**: Fix #1, #2, #3 (week 1); then #7, #10 (monitoring). Secondary: iOS billing, quote payment, collections UI.

---

Generated: 2026-06-10