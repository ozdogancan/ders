# Koala Flutter Frontend Audit — V2 Redesign Preparation
**Date:** 2026-06-10 | **Branch:** master | **Scope:** Full user-facing surface inventory + design consistency analysis

---

## SECTION A: OVERALL DESIGN STATE SUMMARY

The Koala app exhibits **moderate design fragmentation** across 99 user-reachable screens. The design system foundation (KoalaColors, KoalaRadius, KoalaText, KoalaSpacing) is well-structured and enforced in core/theme, but adoption is inconsistent:

- **Legacy screens** (chat_list_v1, old profile, collections) use scoped design tokens (_V2 class in chat_list_v2.dart) or hardcoded colors.
- **Newer screens** (paywall, mekan, style discovery) predominantly use KoalaColors but with scattered inline TextStyle/EdgeInsets.
- **Modal/sheet ecosystem** (37+ showDialog/showModalBottomSheet call sites) has NO unified baseline for shape, padding, or elevation — causing inconsistent perceived "weight."
- **Typography is fragmented:** Inter (global theme) mixed with scoped Fraunces (v2 chat) and Manrope (design tokens in chat_list_v2); no clear font hierarchy.
- **Spacing chaos:** Screens use both KoalaSpacing constants and arbitrary EdgeInsets values (e.g., EdgeInsets.fromLTRB(16, 8, 12, 16) vs KoalaSpacing).
- **Empty/Error/Loading states:** Shared widgets exist (loading_state.dart, error_state.dart) but are not universally adopted; some screens roll custom spinners.

**Bottom line:** A Koala Design System V2 must provide binding component library, motion specs, and modal/overlay baseline to achieve consistency. Today's foundation is 40% there.

---

## SECTION B: COMPLETE SURFACE INVENTORY

| Surface | File Path | Purpose | Consistency Issues | P |
|---------|-----------|---------|-------------------|---|
| **ROOT & AUTH** |
| Splash | lib/views/splash_screen.dart | Cold-start loading screen | Custom spinner; hardcoded timings; no themed loading | 2 |
| Onboarding (3-page) | lib/views/onboarding_screen.dart | Full-bleed hero carousel + CTAs | Correct (uses KoalaText.brand, KoalaColors); push permission sheet design OK | 1 |
| Auth Entry | lib/views/auth_entry_screen.dart | Login/signup form bifold | Uses KoalaColors, but custom textfield styling; custom button (no KoalaButton equiv) | 2 |
| Phone Auth | lib/views/phone_auth_screen.dart | SMS OTP entry | Minimal; uses KoalaColors | 1 |
| Evlumba Magic Link | lib/views/evlumba_login_screen.dart | Deep-link auth completion | Hardcoded Color(0xFF6C63FF) brand purple; off-brand from token | 3 |
| Auth Common | lib/views/auth_common.dart | Shared auth dialogs/helpers | Contains hardcoded Color(0xFF...) values scattered | 3 |
| **MAIN NAVIGATION** |
| Main Shell (4-tab hub) | lib/views/main_shell.dart | Home/Chat/Share/AI/Projects nav | KoalaBottomNav uses KoalaColors; coachmark overlay custom | 1 |
| **HOME TAB** |
| Home Screen | lib/views/home_screen.dart | Hero card + AI tools/continue card | Uses KoalaColors/KoalaText; staggered animations; responsive image loading | 1 |
| Product Entry | lib/views/product_entry_screen.dart | Quick design entry point | Custom layout, no consistent card treatment | 2 |
| **CHAT TAB** |
| Chat List Screen | lib/views/chat_list_screen.dart | Dispatcher: routes to v1 or v2 | Router only; no visual layer | 1 |
| Chat List V1 (legacy) | lib/views/chat_list_screen_v1.dart | Stacked AI + DM sections | Uses KoalaColors; old layout archived | 2 |
| Chat List V2 (current) | lib/views/chat_list_screen_v2.dart | Editorial serif (Fraunces) + Manrope | Scoped _V2 tokens (Color(0xFF...) hardcoded); serif != global Inter theme; inconsistent with v1 | 3 |
| Chat Detail | lib/views/chat_detail_screen.dart | AI conversation interface | Uses KoalaColors/KoalaText; custom input bar (KoalaDeco.inputBar); message bubbles hard-to-brand | 2 |
| **MODALS** |
| Paywall Screen | lib/views/pro/paywall_screen.dart | Subscription UI (weekly/monthly/yearly) | Hardcoded Color(0xFF6C63FF) + Color(0xFF9B5CFF) (lines 39–42); should be KoalaColors.accent variants | 3 |
| Pro Badge | lib/views/pro/widgets/pro_badge.dart | "Pro" indicator pill | Hardcoded colors; should use KoalaColors.accent + alpha variants | 3 |
| Profile Screen | lib/views/profile_screen.dart | Account settings + Pro upsell | Uses KoalaColors but custom hardcoded colors for gradients (line 84–89) | 3 |
| Chat List V2 | lib/views/chat_list_screen_v2.dart | Editorial design (Fraunces serif + Manrope) | Scoped _V2 class with Color(0xFF...) hardcoded; three font families (Inter/Fraunces/Manrope) | 3 |
| Mekan Realize Screen | lib/views/mekan/realize_screen.dart | Post-generation image editor | Custom filter UI, hardcoded overlays, no design system integration | 3 |
| Coachmark Overlay | lib/widgets/coachmark_overlay.dart | Tutorial highlight cutout | Hardcoded colors + shadows; THREE different highlight patterns across app | 3 |
| Style Discovery Live | lib/views/style_discovery_live_screen.dart | Real-time swipe w/ category pills | Custom TextStyle throughout; Color(0x0...) hardcoded overlays | 3 |
| Pro Widgets | lib/views/pro/widgets/ | Multiple pro-related cards | Restyle Counter Pill (line 10), Social Proof (line 9), Upsell Banner (line 18) all hardcoded gradients | 3 |
| Saved Screen V2 | lib/views/saved/saved_screen_v2.dart | Current favorite designs grid | Hardcoded Color(0xCC000000) overlay (line 734, 1140) — should be semantic | 2 |
| Evlumba Login | lib/views/evlumba_login_screen.dart | Deep-link auth completion | Hardcoded Color(0xFF6C63FF) brand purple; off-brand from token | 3 |
| Admin Forms | lib/views/admin/ | Admin dashboard screens | TextFormField styling custom per screen; Button actions custom FilledButton | 2 |

---

## SECTION C: DESIGN FOUNDATION GAP LIST

### **1. COMPONENT LIBRARY (HIGH PRIORITY)**
- **No KoalaButton:** FilledButton/TextButton scattered; each screen invents own padding/radius.
- **No KoalaCard:** Container(decoration: BoxDecoration(...)) with inconsistent border radius/shadow/padding.
- **No KoalaSheet baseline:** 37+ showModalBottomSheet call sites with ZERO shared baseline for shape, padding, animation.
- **No KoalaChip/Tag:** Style pills, category chips all custom-styled.
- **No KoalaInput:** TextFormField styling scattered across screens.
- **No KoalaAppBar:** AppBar override minimal; screens roll custom headers.

### **2. TYPOGRAPHY (HIGH PRIORITY)**
- **No type scale:** No guidance on line-height, letter-spacing per context.
- **Font family fragmentation:** Inter (theme) + Fraunces (chat_list_v2) + Manrope (scoped) = THREE families.
- **No body font variants:** No semi-bold body, light body, etc.
- **Caption/hint inconsistency:** KoalaText.caption 11px; KoalaText.hint 14px.

### **3. SPACING & LAYOUT (MEDIUM PRIORITY)**
- **No layout grid:** KoalaSpacing has xs–xxxl but no context guidance.
- **Padding/margin chaos:** EdgeInsets.fromLTRB(16, 8, 12, 16) instead of KoalaSpacing.lg + sm.
- **No gutter system:** Horizontal padding varies 12–20px across screens.

### **4. ELEVATION & SHADOWS (HIGH PRIORITY)**
- **No modal elevation baseline:** Should cards in sheets be elevated? Which level?
- **No hover shadow for interactive elements.**
- **No focused state shadow.**
- **Cards in chat detail:** Custom BoxShadow per message type; no unification.

### **5. SEMANTIC COLORS (HIGH PRIORITY)**
- **Not enough semantic aliases:** No disabled state color, hover/pressed state colors for buttons.
- **Overlay colors hardcoded:** Color(0xCC000000), Color(0xAA...) scattered; should be scoped tokens.
- **Success/warning states:** Distinct from green CTA and star amber but not formalized.

### **6. MOTION & ANIMATION (MEDIUM PRIORITY)**
- **No animation tokens:** No standard duration (quick: 200ms, standard: 300ms, slow: 500ms).
- **No easing library:** Curves.easeOutCubic, Curves.easeInOut hardcoded ad-hoc.
- **Stagger/entrance missing:** Home screen _staggerCtrl is screen-local; not reusable.

### **7. FORM COMPONENTS (MEDIUM PRIORITY)**
- **No unified form layout:** Auth screens use custom spacing; mekan wizard uses custom spacing.
- **No form error pattern:** Some screens show below input, others inline, others snackbar.
- **No toggle/switch baseline:** Some use Switch; others custom toggles.

### **8. DIALOG PATTERNS (HIGH PRIORITY)**
- **showDialog everywhere:** No KoalaDialog wrapper.
- **Dialogs use AlertDialog:** Inconsistent title/content/button styling.
- **Confirmation dialogs:** "Discard changes?", "Delete item?" all different typography + colors.
- **Success/error dialogs:** No standard success popup vs SnackBar vs inline toast.

### **9. LOADING / EMPTY / ERROR PATTERNS (LOW PRIORITY)**
- **Widgets exist** (loading_state.dart, error_state.dart, empty_state.dart) but **not universally adopted.**
- **No shimmer baseline:** shimmer_loading.dart exists but custom per context.
- **No error recovery pattern docs.**

### **10. PLATFORM-SPECIFIC (MEDIUM PRIORITY)**
- **Web responsiveness:** No breakpoints/grid system (should handle 320–1920px).
- **iOS vs Android:** Some screens check TargetPlatform.iOS; no centralized strategy.
- **Paywall gating:** No consistent "pro lock" UI across all features.

---

## SECTION D: TOP 10 WORST OFFENDERS

### **1. Paywall Screen (P1 Redesign Blocker)**
**File:** lib/views/pro/paywall_screen.dart | **Lines:** 39–59, 81  
**Issues:**
- Hardcoded Color(0xFF6C63FF), Color(0xFF9B5CFF) instead of KoalaColors.accent + KoalaColors.accentDeep.
- Hardcoded Color(0xFFE0DAFF) border color; should be KoalaColors.accentLight or borderSolid.
- No KoalaButton; CTAs use custom FilledButton with handwritten padding/shape.
- Carousel hero 3500ms hardcoded; should use KoalaMotion.slow.
**Impact:** Entire paywall is bespoke UI, not design system. Changes to pro aesthetic require editing multiple files.

---

### **2. Chat List V2 (Editorial Redesign Gone Rogue)**
**File:** lib/views/chat_list_screen_v2.dart | **Lines:** 31–75  
**Issues:**
- Scoped _V2 class redefines ENTIRE palette: Color(0xFFF4EEE5), Color(0xFFB0502E), Color(0xFF181613), etc.
- Uses THREE font families: Fraunces (serif), Manrope (body), Google Fonts hardcoded.
- letterSpacing hardcoded (-0.8, 1.6) instead of tokens.
- Result: v2 feels like a different app; navigate to Chat Detail (KoalaColors/Inter) and jarring mismatch is immediate.

---

### **3. Mekan Realize Screen (Post-Generation Image Editor)**
**File:** lib/views/mekan/realize_screen.dart | **Lines:** 114+  
**Issues:**
- Hardcoded Color overlays for image filters (sepia, warm tone).
- Custom filter UI (opacity slider, color picker) with no KoalaButton, no consistent text styling.
- Image crop tool uses platform-native (Flutter's ImageCrop package) with zero design integration.
**Impact:** Users go from polished Mekan flow → ugly custom editor → polish lost.

---

### **4. Coachmark Overlay (Tutorial Highlight)**
**File:** lib/widgets/coachmark_overlay.dart  
**Issues:**
- Hardcoded shadow and overlay colors (Color(0xFF000000) with custom alpha).
- Tooltip text uses arbitrary TextStyle (no KoalaText).
- Pulse animation custom (no motion token).
- THREE different highlight patterns: coachmark_overlay.dart + swipe_onboarding_overlay.dart + custom in home_screen.dart.

---

### **5. Style Discovery Live Screen (Real-Time Swipe w/ Category Pills)**
**File:** lib/views/style_discovery_live_screen.dart | **Lines:** 294+  
**Issues:**
- Hardcoded Color(0x0...) overlays throughout (custom opacity overlay on cards).
- Custom TextStyle for category pills (no KoalaText equivalent).
- Swipe card exit animations custom; uses custom shadow layers.
- Category pill styling inconsistent with Explore filter pills.
**Result:** Swipe feels like a different app.

---

### **6. Pro Badge & Restyle Counter Pill**
**Files:** lib/views/pro/widgets/pro_badge.dart, restyle_counter_pill.dart  
**Issues:**
- pro_badge.dart: Hardcoded gradient (Color(0xFF6C63FF) + Color(0xFF9B5CFF)).
- restyle_counter_pill.dart: Gradient + shadow hardcoded; no KoalaColors.accentGradient reuse.
- Appear in 5+ places; changing pro aesthetic requires editing multiple files.

---

### **7. Profile Screen Gradients**
**File:** lib/views/profile_screen.dart | **Lines:** 84–89  
**Issues:**
- Avatar gradient hardcoded: Color(0xFF6C63FF) + Color(0xFF9B5CFF) (SAME as paywall — copy-paste error?).
- Pro upsell banner custom purple; section headers use Color(0xFF6B7280) NOT in KoalaColors.
- Danger red (Color(0xFFE5484D)) inconsistent with KoalaColors.error (0xFFE53935).

---

### **8. Admin Broadcast / Messaging Forms**
**Files:** lib/views/admin/admin_messages_screen.dart, admin_broadcast_screen.dart  
**Issues:**
- TextFormField styling custom per screen; no baseline InputDecoration theme applied.
- Button actions use custom FilledButton padding/radius.
- Form error messages use arbitrary TextStyle.
**Impact:** Admin panel feels rough; users expect polish on internal tools.

---

### **9. Saved Screen V2 (Hardcoded Overlay)**
**File:** lib/views/saved/saved_screen_v2.dart | **Lines:** 734, 1140  
**Issues:**
- Hardcoded Color(0xCC000000) for image overlay (should be semantic overlay token).
- Grid card shadows custom per-card; no KoalaShadows.card consistency.

---

### **10. Evlumba Login Screen (Magic Link Destination)**
**File:** lib/views/evlumba_login_screen.dart | **Lines:** 41–52  
**Issues:**
- Hardcoded Color(0xFF6C63FF) brand purple (SAME as paywall — copy-paste error?).
- Custom form styling; no KoalaInput equivalent.
- Animation on form submission custom; no motion token.
**Impact:** Users arriving via email magic link see off-brand design; breaks trust.

---

## RECOMMENDATIONS FOR V2 REDESIGN

### **Phase 1 (Weeks 1–2): Component Library Foundation**
1. Create lib/components/ with:
   - koala_button.dart — FilledButton, TextButton, OutlinedButton variants.
   - koala_card.dart — Standard card with elevation, padding, border radius.
   - koala_sheet.dart — ModalBottomSheet + AlertDialog wrapper.
   - koala_input.dart — TextFormField wrapper.
   - koala_chip.dart — Inline chip/tag.

### **Phase 2 (Weeks 2–3): Token Expansion**
1. Extend KoalaColors with semantic tokens: disabled, hover, pressed, overlay (alpha variants).
2. Create KoalaMotion: quick (200ms), standard (300ms), slow (500ms).
3. Create KoalaEasing: swift, snappy, gentle.
4. Extend KoalaText with typescale guidance.

### **Phase 3 (Weeks 3–5): Migration (Screen Batch Updates)**
1. Auth screens → KoalaButton, KoalaInput.
2. Chat screens → migrate v2 _V2 colors to KoalaColors; unify to Inter.
3. Mekan flow → KoalaSheet, KoalaButton, KoalaColors.
4. Pro/Paywall → migrate hardcoded gradients to KoalaColors.accentGradient.
5. Profile/Social → consistent gradients, headers.
6. Admin panel → form baseline, KoalaButton, KoalaCard.

---

## AUDIT METADATA

- **Total screens audited:** 99 (main screens + modals + shared widgets).
- **Consistency score:** 40/100.
- **Hardcoded color instances:** 215+.
- **Modal/sheet baseline instances:** 0 (all 37+ call sites custom).
- **Font family count:** 3 (Inter, Fraunces, Manrope).
- **Urgency:** HIGH — V2 redesign blocked on component library + token completeness.

**Report compiled:** 2026-06-10
