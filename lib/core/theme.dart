import 'package:flutter/material.dart';

class HamrahColors {
  static const ink = Color(0xFF16211E);
  static const primary = Color(0xFF1F5C4A);
  static const primarySoft = Color(0xFFE6F1EC);
  static const gold = Color(0xFFB8862B);
  static const income = Color(0xFF2F7A5C);
  static const expense = Color(0xFFA6433A);
  static const surface = Color(0xFFF6F7F9);
  static const darkSurface = Color(0xFF12181A);
  static const darkCard = Color(0xFF1A2224);
}

ThemeData buildTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: HamrahColors.primary,
    brightness: brightness,
  ).copyWith(
    primary: isDark ? const Color(0xFF7FC3A8) : HamrahColors.primary,
    secondary: HamrahColors.gold,
    surface: isDark ? HamrahColors.darkCard : Colors.white,
    error: HamrahColors.expense,
  );

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: 'Vazirmatn',
    scaffoldBackgroundColor: isDark ? HamrahColors.darkSurface : HamrahColors.surface,
    visualDensity: VisualDensity.standard,
  );

  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: isDark ? const Color(0xFFE7ECEA) : HamrahColors.ink,
      displayColor: isDark ? const Color(0xFFE7ECEA) : HamrahColors.ink,
    ).copyWith(
      titleLarge: base.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
      titleMedium: base.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      bodySmall: base.textTheme.bodySmall?.copyWith(fontSize: 12),
      labelSmall: base.textTheme.labelSmall?.copyWith(fontSize: 12),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: isDark ? HamrahColors.darkCard : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: isDark ? HamrahColors.darkSurface : HamrahColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: base.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
        color: isDark ? const Color(0xFFE7ECEA) : HamrahColors.ink,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: isDark ? HamrahColors.darkCard : Colors.white,
      indicatorColor: isDark ? const Color(0xFF24413A) : HamrahColors.primarySoft,
      labelTextStyle: WidgetStatePropertyAll(base.textTheme.labelMedium),
      height: 68,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: isDark ? const Color(0xFF1F2A2C) : Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: isDark ? const Color(0xFF2F3B3D) : const Color(0xFFDDE3E1)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: isDark ? const Color(0xFF2F3B3D) : const Color(0xFFDDE3E1)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.primary, width: 1.4),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontFamily: 'Vazirmatn', fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    dividerTheme: DividerThemeData(
      color: isDark ? const Color(0xFF2A3436) : const Color(0xFFE8ECEA),
      thickness: 1,
      space: 1,
    ),
    chipTheme: base.chipTheme.copyWith(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      side: BorderSide(color: isDark ? const Color(0xFF33403F) : const Color(0xFFDDE3E1)),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      labelStyle: base.textTheme.bodyMedium,
    ),
  );
}

Color directionColor(String direction, {bool dark = false}) =>
    direction == 'in' ? HamrahColors.income : HamrahColors.expense;
