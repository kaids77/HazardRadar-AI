import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hazardradarai/services/app_settings.dart';
import 'package:hazardradarai/theme/app_theme.dart';

void main() {
  test('palette tokens match the approved hex values', () {
    expect(AppColors.cream, const Color(0xFFF3F7FA));
    expect(AppColors.sage, const Color(0xFFD5E1E0));
    expect(AppColors.logoSage, const Color(0xFF8AA3A0));
    expect(AppColors.ink, const Color(0xFF111925));
    expect(AppColors.darkPaper, const Color(0xFF0F131E));
    expect(AppColors.darkSage, const Color(0xFF1D2836));
    expect(AppColors.redOrange, const Color(0xFF111925));
    expect(AppColors.riskHigh, const Color(0xFFE73213));
  });

  test('theme uses the palette and has no elevation or surface tint', () {
    final theme = AppTheme.light();

    expect(theme.colorScheme.primary, AppColors.redOrange);
    expect(theme.scaffoldBackgroundColor, AppColors.cream);
    expect(theme.appBarTheme.elevation, 0);
    expect(theme.appBarTheme.scrolledUnderElevation, 0);
    expect(theme.cardTheme.elevation, 0);
    expect(theme.cardTheme.shadowColor, Colors.transparent);
    expect(theme.colorScheme.surfaceTint, Colors.transparent);
  });

  test('dark mode swaps background and text, and keeps the flat look', () {
    final theme = AppTheme.dark();

    expect(theme.brightness, Brightness.dark);
    expect(theme.scaffoldBackgroundColor, AppColors.darkPaper);
    expect(theme.extension<AppPalette>(), AppPalette.dark);
    expect(theme.extension<AppPalette>()!.ink, AppColors.cream);
    expect(theme.colorScheme.primary, AppColors.logoSage);
    expect(theme.appBarTheme.elevation, 0);
  });

  test('light mode is the default, and the choice is saved', () async {
    final store = MemorySettingsStore();
    final settings = AppSettings(store);
    await settings.load();
    expect(settings.themeMode, ThemeMode.light);

    await settings.setThemeMode(ThemeMode.dark);
    final reloaded = AppSettings(store);
    await reloaded.load();
    expect(reloaded.themeMode, ThemeMode.dark);
  });
}
