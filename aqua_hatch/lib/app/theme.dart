import 'package:flutter/material.dart';

abstract final class AquaMotion {
  static const curve = Cubic(.22, 1, .36, 1);
  static const move = Duration(milliseconds: 500);
  static const fade = Duration(milliseconds: 300);
}

abstract final class AquaType {
  static const metric = TextStyle(
    fontSize: 48,
    height: 1,
    fontWeight: FontWeight.w500,
    letterSpacing: -1.5,
    fontFeatures: [FontFeature.tabularFigures()],
  );
  static const reading = TextStyle(
    fontSize: 30,
    height: 1.2,
    fontWeight: FontWeight.w500,
    fontFeatures: [FontFeature.tabularFigures()],
  );
  static const caption = TextStyle(
    fontSize: 12,
    height: 1.4,
    color: AquaColors.muted,
  );
}

abstract final class AquaColors {
  static const navy = Color(0xFF252B2B),
      blue = Color(0xFF146A70),
      deep = Color(0xFF181818),
      teal = Color(0xFF267C80),
      background = Color(0xFFF7F8F8),
      paper = Color(0xFFFFFFFF),
      sage = Color(0xFFEDF2F1),
      lime = Color(0xFFD5EAE6),
      muted = Color(0xFF576666),
      line = Color(0xFFDAE1DF),
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
    primaryContainer: AquaColors.sage,
    onPrimaryContainer: AquaColors.deep,
    secondaryContainer: AquaColors.lime,
    onSecondaryContainer: AquaColors.deep,
    surfaceContainerHighest: AquaColors.sage,
    outline: AquaColors.muted,
    outlineVariant: AquaColors.line,
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: AquaColors.background,
    foregroundColor: AquaColors.navy,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
  ),
  textTheme: const TextTheme(
    headlineLarge: TextStyle(
      fontSize: 36,
      fontWeight: FontWeight.w600,
      color: AquaColors.navy,
    ),
    headlineMedium: TextStyle(
      fontSize: 30,
      fontWeight: FontWeight.w600,
      color: AquaColors.navy,
    ),
    titleLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
    titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
    bodyMedium: TextStyle(fontSize: 16, height: 1.5),
    bodySmall: TextStyle(fontSize: 14, height: 1.5, color: AquaColors.muted),
  ),
  cardTheme: CardThemeData(
    elevation: 0,
    color: AquaColors.paper,
    surfaceTintColor: Colors.transparent,
    margin: EdgeInsets.zero,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: BorderSide.none,
    ),
  ),
  dividerTheme: const DividerThemeData(color: AquaColors.line, thickness: 1),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: AquaColors.sage,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: AquaColors.line),
    ),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      minimumSize: const Size(48, 48),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  ),
  navigationBarTheme: const NavigationBarThemeData(
    backgroundColor: AquaColors.paper,
    surfaceTintColor: Colors.transparent,
    indicatorColor: AquaColors.lime,
    height: 68,
    labelTextStyle: WidgetStatePropertyAll(
      TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
    ),
  ),
);
