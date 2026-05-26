import 'package:flutter/material.dart';

import 'package:google_fonts/google_fonts.dart';

import 'koala_tokens.dart';

class AppTheme {
  const AppTheme._();

  static ThemeData get lightTheme {
    final ColorScheme colorScheme = ColorScheme.fromSeed(
      seedColor: KoalaColors.accent,
      brightness: Brightness.light,
      primary: KoalaColors.accent,
      surface: KoalaColors.surface,
    );

    return ThemeData(
      useMaterial3: true,
      textTheme: GoogleFonts.interTextTheme(),
      colorScheme: colorScheme,
      // Single source of truth for app-wide screen background.
      // Chat screens override explicitly (see chat_detail_screen.dart:1298).
      scaffoldBackgroundColor: KoalaColors.bg,
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: KoalaColors.surface,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: KoalaColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KoalaRadius.md),
          side: const BorderSide(color: KoalaColors.borderSolid),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: false,
        fillColor: Colors.transparent,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(KoalaRadius.sm),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(KoalaRadius.sm),
          borderSide: const BorderSide(
            color: KoalaColors.accent,
            width: 1.3,
          ),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: KoalaColors.accent,
        foregroundColor: KoalaColors.textInv,
      ),
      // Modern, yumuşak toast görünümü — floating, yuvarlak köşe, hafif gölge.
      // Tüm SnackBar'lar bu temayı miras alır; call-site değişikliği gerekmez.
      // Renk/davranış'ı açıkça set eden çağrılar kendi değerini korur.
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: KoalaColors.ink, // #1A1D2A — koyu charcoal
        elevation: 6,
        insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(17),
        ),
        contentTextStyle: GoogleFonts.inter(
          color: Colors.white,
          fontSize: 13.5,
          fontWeight: FontWeight.w600,
          height: 1.35,
        ),
        actionTextColor: KoalaColors.accentMuted,
      ),
    );
  }
}
