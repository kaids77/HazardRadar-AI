import 'package:flutter/material.dart';

/// Palette from the approved design: cream, sage, and red-orange.
/// Low and Medium risk colors sit outside the palette on purpose (approved), so the
/// three risk levels stay easy to tell apart.
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

  /// Reports a crew is working on. A flat ink-blue, with cream text on top (about 9:1).
  static const inProgress = Color(0xFF2E4A62);
  static const onInProgress = cream;
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
        titleTextStyle: TextStyle(
          fontFamily: 'DMSerifDisplay',
          fontSize: 22,
          color: AppColors.ink,
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: AppColors.redOrange),
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
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.cream,
        elevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        indicatorColor: AppColors.sage,
        indicatorShape: const RoundedRectangleBorder(),
        labelTextStyle: WidgetStateProperty.all(const TextStyle(color: AppColors.ink, fontSize: 12)),
        iconTheme: WidgetStateProperty.all(const IconThemeData(color: AppColors.ink)),
      ),
      chipTheme: const ChipThemeData(
        backgroundColor: AppColors.cream,
        selectedColor: AppColors.redOrange,
        labelStyle: TextStyle(color: AppColors.ink),
        side: BorderSide(color: AppColors.ink),
        shape: RoundedRectangleBorder(),
        elevation: 0,
        pressElevation: 0,
        showCheckmark: false,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.all(AppColors.ink),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? AppColors.redOrange : AppColors.sage,
        ),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
    );
  }
}
