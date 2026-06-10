import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ═══════════════════════════════════════════════════════════════
// KOALA DESIGN SYSTEM — V2  (warm-premium • Airbnb/Havenly ruhu)
//
// Tek kaynak. Ekranlar SADECE buradan ve lib/core/widgets/'tan beslenir.
// Hardcoded Color / ham TextStyle / keyfi EdgeInsets ekranlarda YASAK.
//
// Eski koala_tokens.dart korunur (legacy ekranlar bozulmasın); Faz 2'de
// her ekran KoalaDS'e migrate edilir. Detay: docs/v2/DESIGN_SYSTEM.md
// ═══════════════════════════════════════════════════════════════

/// Renk — warm-premium semantik set. Soğuk slate/gri YOK; tüm nötrler
/// krem zeminle uyumlu sıcak tonda.
abstract final class KoalaDS {
  // ─── Canvas & yüzey ───
  static const bg           = Color(0xFFF6F1EB); // ana zemin — sıcak krem
  static const bgSand       = Color(0xFFEFE8DD); // bölüm ayrımı, alt zemin
  static const surface      = Color(0xFFFFFFFF); // kart, sheet, modal
  static const surfaceMuted = Color(0xFFF4EFE8); // skeleton, placeholder
  static const overlay      = Color(0xCC1A1622); // görsel üstü scrim (warm)

  // ─── Metin (sıcak charcoal — mavi/slate değil) ───
  static const ink      = Color(0xFF211C29); // başlık & gövde
  static const inkSoft  = Color(0xFF5B5563); // ikincil metin
  static const inkFaint = Color(0xFF9A93A1); // hint, disabled
  static const onAccent = Color(0xFFFFFFFF); // mor/yeşil üstü metin

  // ─── Marka / AI (mor) ───
  static const accent     = Color(0xFF7C6EF2);
  static const accentDeep = Color(0xFF6C5CE7);
  static const accentTint = Color(0xFFEFECFE); // chip bg, seçim tint

  // ─── CTA (yeşil) ───
  static const cta     = Color(0xFF1D9E75);
  static const ctaDeep = Color(0xFF0F6E56);
  static const ctaTint = Color(0xFFE1F5EE);

  // ─── Sıcak aksan (warm-premium imzası) ───
  static const clay     = Color(0xFFC97B5A); // rozet, öne çıkarma
  static const clayTint = Color(0xFFF6E7DE);

  // ─── Çizgi / semantik ───
  static const line    = Color(0xFFE7DFD4); // border & divider (krem-tinted)
  static const lineSoft = Color(0x14000000); // 8% — ince ayraç
  static const danger  = Color(0xFFE5484D);
  static const dangerTint = Color(0xFFFBE9E9);
  static const star    = Color(0xFFF5A623);

  // ─── Gradient ───
  static const accentGradient = LinearGradient(
    colors: [Color(0xFF8B7DF5), accentDeep],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const ctaGradient = LinearGradient(
    colors: [Color(0xFF26B187), ctaDeep],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

/// Spacing — 4 tabanlı.
abstract final class KoalaGap {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0;
  static const xxl = 24.0;
  static const xxxl = 32.0;
  static const huge = 48.0;
}

/// Köşe yarıçapı.
abstract final class KoalaR {
  static const sm = 10.0;
  static const md = 14.0;
  static const lg = 20.0;
  static const xl = 28.0;
  static const pill = 999.0;
}

/// Gölge — sıcak (mor-charcoal tint), saf siyah değil.
abstract final class KoalaElev {
  static final card = [
    BoxShadow(
      color: const Color(0xFF2A2233).withValues(alpha: 0.05),
      blurRadius: 14,
      offset: const Offset(0, 2),
    ),
  ];
  static final lifted = [
    BoxShadow(
      color: const Color(0xFF2A2233).withValues(alpha: 0.09),
      blurRadius: 28,
      offset: const Offset(0, 8),
    ),
  ];
  static final accentGlow = [
    BoxShadow(
      color: KoalaDS.accent.withValues(alpha: 0.28),
      blurRadius: 26,
      offset: const Offset(0, 8),
    ),
  ];
  static final ctaGlow = [
    BoxShadow(
      color: KoalaDS.cta.withValues(alpha: 0.26),
      blurRadius: 22,
      offset: const Offset(0, 8),
    ),
  ];
}

/// Motion.
abstract final class KoalaMotion {
  static const fast = Duration(milliseconds: 150);
  static const base = Duration(milliseconds: 240);
  static const slow = Duration(milliseconds: 360);
  static const lazy = Duration(milliseconds: 600);

  static const enter = Curves.easeOutCubic;
  static const exit = Curves.easeInCubic;
  static const spring = Curves.easeOutBack;
}

/// Tipografi — Fraunces (serif) display + Inter gövde.
/// Gövde stilleri const; Inter'i global theme'den miras alır.
abstract final class KoalaType {
  // Display (serif, Fraunces) — hero başlıklar
  static TextStyle display1({Color color = KoalaDS.ink}) => GoogleFonts.fraunces(
        fontSize: 40, fontWeight: FontWeight.w600, color: color,
        letterSpacing: -1.0, height: 1.05);
  static TextStyle display2({Color color = KoalaDS.ink}) => GoogleFonts.fraunces(
        fontSize: 32, fontWeight: FontWeight.w600, color: color,
        letterSpacing: -0.6, height: 1.08);
  static TextStyle display3({Color color = KoalaDS.ink}) => GoogleFonts.fraunces(
        fontSize: 26, fontWeight: FontWeight.w600, color: color,
        letterSpacing: -0.4, height: 1.12);

  // Heading (Inter)
  static const h1 = TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: KoalaDS.ink, letterSpacing: -0.4);
  static const h2 = TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: KoalaDS.ink, letterSpacing: -0.2);
  static const h3 = TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: KoalaDS.ink);
  static const h4 = TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: KoalaDS.ink);

  // Body (Inter)
  static const bodyLg = TextStyle(fontSize: 16, color: KoalaDS.ink, height: 1.5);
  static const body   = TextStyle(fontSize: 15, color: KoalaDS.ink, height: 1.55);
  static const bodySm = TextStyle(fontSize: 13.5, color: KoalaDS.inkSoft, height: 1.5);
  static const bodySoft = TextStyle(fontSize: 15, color: KoalaDS.inkSoft, height: 1.55);

  // Label / caption
  static const label   = TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: KoalaDS.ink);
  static const labelSm = TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500, color: KoalaDS.inkSoft);
  static const caption = TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: KoalaDS.inkFaint, letterSpacing: 0.6);
  static const button  = TextStyle(fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 0.1);
}
