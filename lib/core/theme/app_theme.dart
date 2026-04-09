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
      textTheme: GoogleFonts.plusJakartaSansTextTheme(),
      colorScheme: colorScheme,
      scaffoldBackgroundColor: KoalaColors.surface,
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
    );
  }
}
