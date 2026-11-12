import 'package:flutter/material.dart';

abstract final class AquaColors {
  static const navy = Color(0xFF1B2921),
      blue = Color(0xFF2B5F46),
      deep = Color(0xFF142D22),
      teal = Color(0xFF2D6749),
      background = Color(0xFFF4F4ED),
      paper = Color(0xFFFEFEFA),
      sage = Color(0xFFE8EDE0),
      lime = Color(0xFFE3EFAD),
      muted = Color(0xFF526157),
      line = Color(0xFFE0E4D9),
      orange = Color(0xFF87551D),
      red = Color(0xFFA03632);
}

ThemeData buildTheme() => ThemeData(
  useMaterial3: true,
  fontFamily: 'NotoSansThai',
  scaffoldBackgroundColor: AquaColors.background,
  colorScheme: ColorScheme.fromSeed(seedColor: AquaColors.blue).copyWith(
    primary: AquaColors.blue,
    secondary: AquaColors.teal,
    surface: AquaColors.paper,
    onSurface: AquaColors.navy,
    error: AquaColors.red,
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: AquaColors.background,
    foregroundColor: AquaColors.navy,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
  ),
  textTheme: const TextTheme(
    headlineLarge: TextStyle(
      fontSize: 34,
      fontWeight: FontWeight.w700,
      color: AquaColors.navy,
    ),
    headlineMedium: TextStyle(
      fontSize: 28,
      fontWeight: FontWeight.w700,
      color: AquaColors.navy,
    ),
    titleLarge: TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
    titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
    bodyMedium: TextStyle(fontSize: 15, height: 1.5),
    bodySmall: TextStyle(fontSize: 13, height: 1.5, color: AquaColors.muted),
  ),
  cardTheme: CardThemeData(
    elevation: 0,
    color: AquaColors.paper,
    surfaceTintColor: Colors.transparent,
    margin: EdgeInsets.zero,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(22),
      side: const BorderSide(color: AquaColors.line),
    ),
  ),
  dividerTheme: const DividerThemeData(color: AquaColors.line, thickness: 1),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: AquaColors.sage,
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
    backgroundColor: AquaColors.paper,
    surfaceTintColor: Colors.transparent,
    indicatorColor: AquaColors.lime,
    height: 68,
    labelTextStyle: WidgetStatePropertyAll(
      TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
    ),
  ),
);
