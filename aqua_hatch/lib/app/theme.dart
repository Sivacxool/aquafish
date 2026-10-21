import 'package:flutter/material.dart';

abstract final class AquaColors {
  static const navy = Color(0xFF16354B),
      blue = Color(0xFF087D86),
      deep = Color(0xFF064563),
      teal = Color(0xFF08796F),
      background = Color(0xFFF5F8FA),
      muted = Color(0xFF526775),
      line = Color(0xFFE3EDF2),
      orange = Color(0xFFAC6715),
      red = Color(0xFFBC4252);
}

ThemeData buildTheme() => ThemeData(
  useMaterial3: true,
  fontFamily: 'NotoSansThai',
  scaffoldBackgroundColor: AquaColors.background,
  colorScheme: ColorScheme.fromSeed(seedColor: AquaColors.blue).copyWith(
    primary: AquaColors.blue,
    secondary: AquaColors.teal,
    surface: Colors.white,
    onSurface: AquaColors.navy,
    error: AquaColors.red,
  ),
  textTheme: const TextTheme(
    headlineLarge: TextStyle(
      fontSize: 30,
      fontWeight: FontWeight.w700,
      color: AquaColors.navy,
    ),
    headlineMedium: TextStyle(
      fontSize: 25,
      fontWeight: FontWeight.w700,
      color: AquaColors.navy,
    ),
    titleLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
    titleMedium: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
    bodyMedium: TextStyle(fontSize: 15, height: 1.5),
    bodySmall: TextStyle(fontSize: 13, height: 1.5, color: AquaColors.muted),
  ),
  cardTheme: CardThemeData(
    elevation: 0,
    color: Colors.white,
    margin: EdgeInsets.zero,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
      side: const BorderSide(color: AquaColors.line),
    ),
  ),
  dividerTheme: const DividerThemeData(color: AquaColors.line, thickness: 1),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: AquaColors.background,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: AquaColors.line),
    ),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      minimumSize: const Size(48, 48),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
      textStyle: const TextStyle(
        fontFamily: 'NotoSansThai',
        fontWeight: FontWeight.w600,
      ),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      minimumSize: const Size(48, 48),
      side: const BorderSide(color: AquaColors.line),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
    ),
  ),
  navigationBarTheme: const NavigationBarThemeData(
    backgroundColor: Colors.white,
    indicatorColor: Color(0xFFE3F1F6),
    height: 76,
  ),
);
