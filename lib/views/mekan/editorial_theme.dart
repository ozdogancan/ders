import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Editoryal dergi paleti — Kinfolk/Cereal diline yakın.
/// Mor-gradient AI app klişesinden uzak; sıcak krem + terracotta + moss.
class MekanPalette {
  static const paper = Color(0xFFEFE9DE);
  static const ink = Color(0xFF1C1814);
  static const oat = Color(0xFFDDD3C0);
  static const burnt = Color(0xFFB44A1C); // terra cotta — tek aksanımız
  static const moss = Color(0xFF3E4A30);
  static const fog = Color(0xFF8B8478);
  static final line = ink.withValues(alpha: 0.14);
}

/// Tipografi: Fraunces (display, yumuşak serif) + Geist Mono (etiketler).
/// Google Fonts paketi runtime'da assets/google_fonts/ içinden çekiyor.
class MekanType {
  static TextStyle display({
    double size = 56,
    bool italic = false,
    Color? color,
  }) =>
      GoogleFonts.fraunces(
        fontSize: size,
        fontWeight: FontWeight.w300,
        fontStyle: italic ? FontStyle.italic : FontStyle.normal,
        height: 1.0,
        letterSpacing: -1.2,
        color: color ?? MekanPalette.ink,
      );

  static TextStyle body({
    double size = 15,
    bool italic = false,
    Color? color,
  }) =>
      GoogleFonts.fraunces(
        fontSize: size,
        fontWeight: FontWeight.w400,
        fontStyle: italic ? FontStyle.italic : FontStyle.normal,
        height: 1.45,
        color: color ?? MekanPalette.moss,
      );

  static TextStyle caps({
    double size = 11,
    Color? color,
    double tracking = 2.2,
  }) =>
      GoogleFonts.geistMono(
        fontSize: size,
        fontWeight: FontWeight.w500,
        height: 1.2,
        letterSpacing: tracking,
        color: color ?? MekanPalette.fog,
      );

  static TextStyle mono({
    double size = 11,
    Color? color,
    double tracking = 1.6,
  }) =>
      GoogleFonts.geistMono(
        fontSize: size,
        fontWeight: FontWeight.w400,
        letterSpacing: tracking,
        color: color ?? MekanPalette.fog,
      );
}
