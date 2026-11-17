import 'package:flutter/material.dart';

/// Palette from the approved design: cream, sage, and red-orange.
/// Low and Medium risk colors are not in the palette, so they are chosen to
/// read clearly next to red-orange. Confirm them before the map is built.
abstract final class AppColors {
  static const cream = Color(0xFFEFE6D5);
  static const sage = Color(0xFF9DBEB7);
  static const redOrange = Color(0xFFE73213);
  static const ink = Color(0xFF1B1B1B);

  // Black text on red-orange reaches about 4.9:1 contrast, above the 4.5:1 minimum.
  static const onRedOrange = Color(0xFF000000);

  static const riskLow = Color(0xFF2F7A56);
  static const riskMedium = Color(0xFFC77700);
  static const riskHigh = redOrange;
}

/// Flat light theme. No elevation, no shadows, no surface tint, and no gradients.
abstract final class AppTheme {
  static ThemeData light() {
    final scheme = ColorScheme.light(
      primary: AppColors.redOrange,
      onPrimary: AppColors.onRedOrange,
      secondary: AppColors.sage,
      onSecondary: AppColors.ink,
      error: AppColors.redOrange,
      onError: AppColors.onRedOrange,
      surface: AppColors.cream,
      onSurface: AppColors.ink,
      surfaceContainerHighest: AppColors.sage,
      surfaceTint: Colors.transparent,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.cream,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.cream,
        foregroundColor: AppColors.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
      ),
      cardTheme: const CardThemeData(
        color: AppColors.sage,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        margin: EdgeInsets.zero,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: AppColors.redOrange,
          foregroundColor: AppColors.onRedOrange,
          shadowColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
        ),
      ),
      dividerTheme: const DividerThemeData(color: AppColors.sage, space: 1),
    );
  }
}
