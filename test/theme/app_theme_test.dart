import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hazardradarai/theme/app_theme.dart';

void main() {
  test('palette tokens match the approved hex values', () {
    expect(AppColors.cream, const Color(0xFFEFE6D5));
    expect(AppColors.sage, const Color(0xFF9DBEB7));
    expect(AppColors.redOrange, const Color(0xFFE73213));
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
}
