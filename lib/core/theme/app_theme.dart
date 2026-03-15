import 'package:flutter/material.dart';

class AppTheme {
  static const Color gold = Color(0xFFD4AF37);
  static const Color background = Color(0xFF101114);
  static const Color surface = Color(0xFF1A1D24);
  static const Color surfaceAlt = Color(0xFF232834);

  static ThemeData build() {
    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: gold,
          brightness: Brightness.dark,
        ).copyWith(
          primary: gold,
          secondary: gold,
          surface: surface,
          error: const Color(0xFFFF6B6B),
          onPrimary: Colors.black,
        );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: background,
      textTheme: Typography.whiteMountainView.apply(
        bodyColor: const Color(0xFFF1F3F8),
        displayColor: const Color(0xFFF1F3F8),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(color: gold),
        titleTextStyle: TextStyle(
          color: Color(0xFFF8F8F8),
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: const CardThemeData(
        color: surface,
        elevation: 2,
        shadowColor: Colors.black45,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surfaceAlt,
        selectedColor: gold.withValues(alpha: 0.2),
        side: BorderSide(color: gold.withValues(alpha: 0.32)),
        labelStyle: const TextStyle(
          color: Color(0xFFF6F7FB),
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceAlt,
        labelStyle: const TextStyle(color: Color(0xFFD7DDE8)),
        hintStyle: const TextStyle(color: Color(0xFFA9B1BF)),
        helperStyle: const TextStyle(color: Color(0xFFBFC6D3)),
        errorStyle: const TextStyle(color: Color(0xFFFFA2A2)),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: gold, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFFFA2A2)),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFFFA2A2), width: 1.4),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: gold,
          foregroundColor: Colors.black,
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFFF3D87A),
          side: BorderSide(color: gold.withValues(alpha: 0.75)),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Color(0xFF1F2430),
        contentTextStyle: TextStyle(color: Color(0xFFF5F6FA)),
      ),
    );
  }
}
