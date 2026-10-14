import 'package:flutter/material.dart';

import 'app_colors.dart';

class AppTheme {
  static ThemeData light() {
    const scheme = ColorScheme.light(
      primary: AppColors.teal,
      onPrimary: Colors.white,
      secondary: AppColors.blue,
      onSecondary: Colors.white,
      surface: AppColors.card,
      onSurface: AppColors.ink,
      error: AppColors.danger,
      onError: Colors.white,
    );
    return _theme(scheme, AppColors.background, AppColors.ink, AppColors.muted);
  }

  static ThemeData dark() {
    const scheme = ColorScheme.dark(
      primary: Color(0xFF5EEAD4),
      onPrimary: Color(0xFF042F2E),
      secondary: Color(0xFF93C5FD),
      onSecondary: Color(0xFF0B1220),
      surface: Color(0xFF173047),
      onSurface: Color(0xFFF8FAFC),
      error: Color(0xFFFCA5A5),
      onError: Color(0xFF7F1D1D),
    );
    return _theme(scheme, const Color(0xFF0F1C2E), const Color(0xFFF8FAFC), const Color(0xFFCBD5E1));
  }

  static ThemeData _theme(
    ColorScheme scheme,
    Color scaffold,
    Color body,
    Color muted,
  ) {
    final text = TextTheme(
      displaySmall: TextStyle(fontSize: 32, fontWeight: FontWeight.w700, color: body, height: 1.2),
      headlineMedium: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: body, height: 1.25),
      headlineSmall: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: body, height: 1.3),
      titleLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: body, height: 1.3),
      titleMedium: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: body, height: 1.35),
      bodyLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.w400, color: body, height: 1.4),
      bodyMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w400, color: body, height: 1.4),
      bodySmall: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: muted, height: 1.35),
      labelLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: body),
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scaffold,
      textTheme: text,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: body,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge,
      ),
      cardTheme: CardThemeData(
        color: scheme.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.45)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 76,
        labelTextStyle: WidgetStateProperty.all(
          const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: scheme.surface,
        selectedIconTheme: IconThemeData(color: scheme.primary, size: 26),
        unselectedIconTheme: IconThemeData(color: muted, size: 24),
        selectedLabelTextStyle: TextStyle(color: scheme.primary, fontWeight: FontWeight.w700, fontSize: 14),
        unselectedLabelTextStyle: TextStyle(color: muted, fontWeight: FontWeight.w600, fontSize: 13),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 52),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 52),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
    );
  }
}
