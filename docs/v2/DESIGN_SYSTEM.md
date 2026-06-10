# Koala Design System — V2

**Yön:** Sıcak-premium (Airbnb / Havenly ruhu). Krem kanvas, sıcak nötrler, mor = AI/marka imzası, yeşil = CTA, serif display başlıklar + sans gövde. Light mode öncelikli.
**Branch:** `v2` (master = canlı web, dokunulmaz). **Kaynak:** `lib/core/theme/koala_ds.dart` (yeni, additive) + mevcut `koala_tokens.dart` (korunur, Faz 2'de migrate edilir).

## 1. İlke
Her ekran SADECE `KoalaDS` (renk/spacing/tip/motion) ve `lib/core/widgets/` component'lerini kullanır. Ekranda hardcoded `Color(0xFF…)`, ham `TextStyle`, keyfi `EdgeInsets` YOK. "Biri Ankara'ya biri Konya'ya bakmasın" kuralı buradan gelir.

## 2. Renk — warm-premium (mevcut token şişkinliğini sadeleştirir)
Eski sistemde 6 mor + soğuk slate griler vardı. V2 tek semantik set:

| Rol | Token | Hex | Kullanım |
|---|---|---|---|
| Canvas | `bg` | #F6F1EB | Ana zemin (sıcak krem) |
| Canvas-2 | `bgSand` | #EFE8DD | Bölüm ayrımı, alt zemin |
| Yüzey | `surface` | #FFFFFF | Kart, sheet, modal |
| Yüzey-muted | `surfaceMuted` | #F4EFe8 | Skeleton, placeholder (krem-tinted) |
| Ink | `ink` | #211C29 | Başlık/gövde (sıcak charcoal, mavi değil) |
| Ink-soft | `inkSoft` | #5B5563 | İkincil metin (warm gray) |
| Ink-faint | `inkFaint` | #9A93A1 | Hint, disabled (warm gray) |
| Marka/AI | `accent` | #7C6EF2 | AI touchpoint, marka, seçim |
| Marka-deep | `accentDeep` | #6C5CE7 | Basılı, gradient ucu |
| CTA | `cta` | #1D9E75 | Birincil eylem (yeşil) |
| CTA-deep | `ctaDeep` | #0F6E56 | Basılı CTA |
| Sıcak aksan | `clay` | #C97B5A | Sıcak vurgu (rozet, öne çıkarma) — warm-premium imzası |
| Çizgi | `line` | #E7DFD4 | Border/divider (krem-tinted, soğuk değil) |
| Hata | `danger` | #E5484D | Tek kırmızı (eski 3 kırmızı birleşti) |
| Yıldız | `star` | #F5A623 | Puan |

**Kural:** soğuk slate/gri (#94A3B8, #475569, #E2E8F0…) V2'de YASAK — warm nötr rampa kullanılır. Bu, krem zeminle çatışmayı bitirir.

## 3. Tipografi — serif display + Inter gövde
- **Display (Fraunces, serif):** hero başlıklar. `display1` 40 / `display2` 32 / `display3` 26. letterSpacing -1 ~ -0.5, weight 600.
- **Heading (Inter):** `h1` 24/700, `h2` 20/700, `h3` 17/600, `h4` 15/600.
- **Body (Inter):** `body` 15/1.55, `bodySm` 13.5, `bodyLg` 16.
- **Label/Caption:** `label` 13/600, `caption` 11.5/600 letterSpacing 0.6 (ALL-CAPS bölüm başlıkları).
- **Button:** 15/700.
Tek serif (Fraunces) yalnız display'de; gövde her yerde Inter. Üçüncü font (Manrope) tamamen kaldırılır.

## 4. Spacing / Radius / Elevation
- **Spacing 4-tabanlı:** xs4 / sm8 / md12 / lg16 / xl20 / xxl24 / xxxl32 / huge48.
- **Radius:** sm10 / md14 / lg20 / xl28 / pill999. Kartlar `lg20`, sheet/modal üst `xl28`, butonlar `pill` veya `md14`.
- **Elevation (sıcak gölge, siyah değil mor-charcoal tint):** `card` (y2 blur14 %5), `lifted` (y8 blur28 %8), `accentGlow`, `ctaGlow`.

## 5. Motion
- Süre: `fast` 150ms / `base` 240ms / `slow` 360ms / `lazy` 600ms.
- Eğri: `enter` easeOutCubic, `exit` easeInCubic, `spring` (bounce — kart/sheet).
- Standart: sayfa geçişi base+enter; sheet slow+spring; buton press 120ms scale .97.

## 6. Component kütüphanesi (`lib/core/widgets/`)
- `KoalaButton` — variant: primary(yeşil CTA) / accent(mor) / secondary(outline) / ghost / danger; size sm/md/lg; loading & disabled & leading-icon; basışta scale animasyonu.
- `KoalaCard` — surface + line + card shadow + lg20 radius; tıklanabilir varyant ripple'lı.
- `KoalaChip` — seçili/seçilmemiş; accent tint.
- `KoalaTextField` — tek InputDecoration; warm line border, focus accent.
- `showKoalaSheet()` — tüm bottom-sheet'ler için tek taban: xl28 üst radius, drag handle, surface, safe-area, slow+spring giriş. 37 dağınık sheet bunu miras alacak.
- `KoalaScaffold` — bg + standart KoalaAppBar (geri butonu, başlık serif/inter).
- State: `KoalaLoading` (shimmer), `KoalaEmpty`, `KoalaError` — tek görsel dil.

## 7. Faz 2 migrasyon sırası (AUDIT_FRONTEND önceliğine göre)
1. Auth/login + Evlumba login + onboarding + splash (ilk izlenim)
2. Main shell + bottom nav + home
3. Chat list (v2 serifi DS'e bağla) + chat detail
4. Paywall + pro widgets (en çok hardcoded)
5. Mekan akışı + realize editör
6. Explore/swipe/style discovery
7. Profile + settings + saved/collections
8. Notifications + admin

Her ekran: DS'e geçir → web build + 1284×2778 screenshot ile görsel doğrula → commit. AUDIT_FRONTEND tablosundaki P sütunu checklist.

## 8. Karar günlüğü
- 2026-06-10: Yön = warm-premium seçildi (kullanıcı). Mor+yeşil korunur, soğuk griler warm nötrle değişir, serif display (Fraunces) geri gelir ama sadece token üzerinden. Eski `koala_tokens.dart` korunur; `koala_ds.dart` yeni kaynak; migrasyon ekran ekran.
