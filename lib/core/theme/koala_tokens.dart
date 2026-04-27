import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ═══════════════════════════════════════════════════════════
// KOALA by evlumba — Design Tokens
// Single source of truth for the entire app.
// Every screen imports from HERE. No local _K classes.
// ═══════════════════════════════════════════════════════════

abstract final class KoalaColors {
  // ─── Backgrounds ───
  static const bg          = Color(0xFFF6F1EB); // warm cream — ana bg
  static const bgCool      = Color(0xFFFAFBFD); // cool white (auth bg)
  static const surface     = Color(0xFFFFFFFF); // card, sheet, modal
  static const surfaceAlt  = Color(0xFFF0EDE8); // placeholder, skeleton
  static const surfaceCool = Color(0xFFF1F5F9); // cool gray surface
  static const surfaceMuted = Color(0xFFFAFAFA); // near-white surface

  // ─── Brand: Purple (accent) ───
  static const accent       = Color(0xFF7C6EF2);
  static const accentDeep   = Color(0xFF6C5CE7); // deeper purple — buttons, CTA
  static const accentDark   = Color(0xFF5A4DBF);
  static const accentDarker = Color(0xFF4F46E5); // onboarding gradient end
  static const accentDeepDark = Color(0xFF4338CA); // onboarding page2 gradient end
  static const accentMuted  = Color(0xFFA78BFA); // soft purple — gradient helper
  static const accentLight  = Color(0xFFEEEDFE); // chip bg, subtle tint
  static const accentSoft   = Color(0xFFF3F0FF); // icon circles, selection bg
  static const brand        = Color(0xFF6C63FF); // auth brand primary
  static const brandLight   = Color(0xFF9B5CFF); // auth gradient secondary

  // ─── Brand: Green (CTA / positive) ───
  static const green       = Color(0xFF1D9E75);
  static const greenDark   = Color(0xFF0F6E56);
  static const greenLight  = Color(0xFFE1F5EE);
  static const greenBright = Color(0xFF22C55E); // snackbar success
  static const greenAlt    = Color(0xFF10B981); // emerald variant

  // ─── Text ───
  static const text     = Color(0xFF1A1A1A); // headings, body
  static const ink      = Color(0xFF1A1D2A); // dark ink — chat, cards
  static const inkDeep  = Color(0xFF0F172A); // deepest text — auth
  static const inkSoft  = Color(0xFF1E293B); // body dark — auth, profile
  static const textSec  = Color(0xFF8E8E93); // secondary labels
  static const textMed  = Color(0xFF475569); // medium gray text
  static const textMuted = Color(0xFF94A3B8); // muted labels — auth hint
  static const textTer  = Color(0xFFAEAEB2); // hints, disabled
  static const textInv  = Color(0xFFFFFFFF); // on-accent, on-dark

  // ─── Borders & dividers ───
  static const border      = Color(0x0F000000); // 6% black
  static const borderLight = Color(0x0A000000); // 4% black
  static const borderSolid = Color(0xFFE2E8F0); // visible border — auth, input
  static const borderMed   = Color(0xFFE5E7EB); // medium gray border — steps
  static const hintBorder  = Color(0xFFCBD5E1); // input placeholder border
  static const divider     = Color(0x0D000000); // 5% black

  // ─── Semantic ───
  static const error      = Color(0xFFE53935);
  static const errorBright = Color(0xFFEF4444); // bright red — delete actions
  static const errorDark  = Color(0xFFDC2626); // dark red — error text
  static const warning    = Color(0xFFF5A623);
  static const star       = Color(0xFFF59E0B); // star rating, amber
  static const success    = Color(0xFF1D9E75); // = green
  static const pink       = Color(0xFFEC4899); // category accent — notifications
  static const blue       = Color(0xFF3B82F6); // info blue — product category

  // ─── Interaction (Style Discovery) ───
  static const like    = Color(0xFF39B97A); // swipe like
  static const dislike = Color(0xFFE26257); // swipe dislike

  // ─── Gradient presets ───
  static const accentGradient = LinearGradient(
    colors: [accent, accentDark],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const accentGradientV = LinearGradient(
    colors: [Color(0xFF8B7DF5), Color(0xFF6B5DD3), Color(0xFF5A4DBF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const greenGradient = LinearGradient(
    colors: [green, greenDark],
  );
}

abstract final class KoalaRadius {
  static const xs  = 8.0;
  static const sm  = 12.0;
  static const md  = 16.0;
  static const lg  = 20.0;
  static const xl  = 28.0;
  static const pill = 100.0;
}

abstract final class KoalaSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0;
  static const xxl = 24.0;
  static const xxxl = 32.0;
}

abstract final class KoalaShadows {
  static final card = [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.04),
      blurRadius: 12,
      offset: const Offset(0, 2),
    ),
  ];

  static final elevated = [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.08),
      blurRadius: 24,
      offset: const Offset(0, 8),
    ),
  ];

  static final accentGlow = [
    BoxShadow(
      color: KoalaColors.accent.withValues(alpha: 0.25),
      blurRadius: 32,
      offset: const Offset(0, 8),
    ),
  ];

  static final greenGlow = [
    BoxShadow(
      color: KoalaColors.green.withValues(alpha: 0.25),
      blurRadius: 20,
      offset: const Offset(0, 6),
    ),
  ];
}

// ─── Common Decorations ───
abstract final class KoalaDeco {
  static BoxDecoration get card => BoxDecoration(
    color: KoalaColors.surface,
    borderRadius: BorderRadius.circular(KoalaRadius.lg),
    border: Border.all(color: KoalaColors.border, width: 0.5),
  );

  static BoxDecoration get cardElevated => BoxDecoration(
    color: KoalaColors.surface,
    borderRadius: BorderRadius.circular(KoalaRadius.lg),
    border: Border.all(color: KoalaColors.border, width: 0.5),
    boxShadow: KoalaShadows.card,
  );

  static BoxDecoration get inputBar => BoxDecoration(
    color: Colors.white.withValues(alpha: 0.8),
    borderRadius: BorderRadius.circular(KoalaRadius.xl),
    border: Border.all(color: KoalaColors.border, width: 0.5),
  );

  static BoxDecoration get chip => BoxDecoration(
    color: KoalaColors.surface,
    borderRadius: BorderRadius.circular(KoalaRadius.lg),
    border: Border.all(color: KoalaColors.border, width: 0.5),
  );

  static BoxDecoration get accentPill => BoxDecoration(
    gradient: KoalaColors.accentGradient,
    borderRadius: BorderRadius.circular(KoalaRadius.xl),
  );

  static BoxDecoration get greenButton => BoxDecoration(
    color: KoalaColors.green,
    borderRadius: BorderRadius.circular(KoalaRadius.md + 2),
    boxShadow: KoalaShadows.greenGlow,
  );
}

// ─── Text Styles ───
//
// NOT: `brand` + `serif` eskiden `fontFamily: 'Georgia'` idi — ancak Georgia
// pubspec'te declared DEĞİL, Flutter web'de sessizce browser serif'ine (Times)
// fallback ediyordu. Cihaz/OS'ye göre aynı kelime farklı görünüyordu, marka
// tutarsızlığı yaratıyordu.
//
// Çözüm: `google_fonts` paketi zaten dep. Fraunces editorial serif, Koala'nın
// sıcak-krem estetiğine Georgia'dan daha iyi oturuyor. İlk web load'da ufak
// CDN fetch (~40KB), cache'leniyor. Mobile'da package otomatik local cache'e
// yazıyor. `const` kaybını kabul ediyoruz — brand style'ı zaten sık kullanılmaz.
abstract final class KoalaText {
  // Brand — hero lockup (44px serif)
  static TextStyle get brand => GoogleFonts.fraunces(
        fontSize: 44,
        fontWeight: FontWeight.w700,
        color: KoalaColors.text,
        letterSpacing: -1.9,
      );

  /// Editorial serif helper — h1/h2 seviyesinde "magazine" his vermek için.
  /// Eski `fontFamily: 'Georgia'` kullanımlarının yerine geçer.
  static TextStyle serif({
    double fontSize = 18,
    FontWeight fontWeight = FontWeight.w600,
    Color color = KoalaColors.text,
    double letterSpacing = -0.2,
    double? height,
    FontStyle? fontStyle,
  }) =>
      GoogleFonts.fraunces(
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
        letterSpacing: letterSpacing,
        height: height,
        fontStyle: fontStyle,
      );

  // Headings
  static const h1 = TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: KoalaColors.text, letterSpacing: -0.3);
  static const h2 = TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: KoalaColors.text);
  static const h3 = TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: KoalaColors.text);
  static const h4 = TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: KoalaColors.text);

  // Body
  static const body = TextStyle(fontSize: 14, color: KoalaColors.text, height: 1.55);
  static const bodyMedium = TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: KoalaColors.text);
  static const bodySec = TextStyle(fontSize: 14, color: KoalaColors.textSec);
  static const bodySmall = TextStyle(fontSize: 12, color: KoalaColors.textSec);

  // Labels
  static const label = TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: KoalaColors.text);
  static const labelSmall = TextStyle(fontSize: 11, color: KoalaColors.textSec);
  static const caption = TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: KoalaColors.textTer, letterSpacing: 0.8);

  // Special
  static const chip = TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: KoalaColors.text);
  static const button = TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white);
  static const hint = TextStyle(fontSize: 14, color: KoalaColors.textTer, fontWeight: FontWeight.w400);
  static const price = TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: KoalaColors.text);
}
