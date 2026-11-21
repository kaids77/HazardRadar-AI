import 'package:flutter/material.dart';

/// Fixed colors from the approved design: cream, sage, and red-orange.
/// Low and Medium risk colors sit outside the palette on purpose (approved), so the
/// three risk levels stay easy to tell apart.
///
/// These never change with light or dark mode. Screens use [AppPalette] (through
/// `context.palette`) for the background, text, and panel colors that do change.
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

  /// Success messages: a deeper green than [riskLow], so cream text reaches about 5.6:1.
  static const success = Color(0xFF256446);
  static const onSuccess = cream;

  /// Error messages use red-orange with black text, like the High-risk color.
  static const error = redOrange;
  static const onError = onRedOrange;

  /// Dark mode background and panel.
  static const darkPaper = Color(0xFF1C1B19);
  static const darkSage = Color(0xFF35504A);
}

/// The colors that switch between light and dark mode.
///
/// [paper] is the background (cream in light mode), [ink] the text and lines (ink in
/// light mode), and [sage] the panel color. Read it with `context.palette`.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({required this.paper, required this.ink, required this.sage});

  static const light = AppPalette(paper: AppColors.cream, ink: AppColors.ink, sage: AppColors.sage);
  static const dark = AppPalette(paper: AppColors.darkPaper, ink: AppColors.cream, sage: AppColors.darkSage);

  final Color paper;
  final Color ink;
  final Color sage;

  @override
  AppPalette copyWith({Color? paper, Color? ink, Color? sage}) =>
      AppPalette(paper: paper ?? this.paper, ink: ink ?? this.ink, sage: sage ?? this.sage);

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    return AppPalette(
      paper: Color.lerp(paper, other.paper, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      sage: Color.lerp(sage, other.sage, t)!,
    );
  }
}

extension AppPaletteContext on BuildContext {
  /// The light or dark palette of the current theme. Falls back to light, so widgets
  /// built without [AppTheme] (some tests) still get the approved colors.
  AppPalette get palette => Theme.of(this).extension<AppPalette>() ?? AppPalette.light;
}

/// Flat light and dark themes. No elevation, no shadows, no surface tint, and no gradients.
abstract final class AppTheme {
  static ThemeData light() => _build(AppPalette.light, Brightness.light);

  static ThemeData dark() => _build(AppPalette.dark, Brightness.dark);

  static ThemeData _build(AppPalette p, Brightness brightness) {
    final base = brightness == Brightness.light ? const ColorScheme.light() : const ColorScheme.dark();
    final scheme = base.copyWith(
      primary: AppColors.redOrange,
      onPrimary: AppColors.onRedOrange,
      secondary: p.sage,
      onSecondary: p.ink,
      error: AppColors.error,
      onError: AppColors.onError,
      surface: p.paper,
      onSurface: p.ink,
      onSurfaceVariant: p.ink,
      surfaceContainerLowest: p.paper,
      surfaceContainerLow: p.paper,
      surfaceContainer: p.paper,
      surfaceContainerHigh: p.paper,
      surfaceContainerHighest: p.sage,
      outline: p.ink,
      outlineVariant: p.sage,
      inverseSurface: p.ink,
      onInverseSurface: p.paper,
      surfaceTint: Colors.transparent,
    );
    final typography = Typography.material2021(colorScheme: scheme);
    final textTheme = (brightness == Brightness.light ? typography.black : typography.white)
        .apply(bodyColor: p.ink, displayColor: p.ink);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      textTheme: textTheme,
      extensions: [p],
      scaffoldBackgroundColor: p.paper,
      canvasColor: p.paper,
      appBarTheme: AppBarTheme(
        backgroundColor: p.paper,
        foregroundColor: p.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        titleTextStyle: TextStyle(fontFamily: 'DMSerifDisplay', fontSize: 22, color: p.ink),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: AppColors.redOrange),
      cardTheme: CardThemeData(
        color: p.sage,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        margin: EdgeInsets.zero,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.paper,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: const RoundedRectangleBorder(),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.paper,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: const RoundedRectangleBorder(),
      ),
      popupMenuTheme: PopupMenuThemeData(color: p.paper, surfaceTintColor: Colors.transparent, elevation: 0),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: p.ink,
        contentTextStyle: TextStyle(color: p.paper),
        elevation: 0,
        shape: const RoundedRectangleBorder(),
      ),
      textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: p.ink)),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: AppColors.redOrange,
          foregroundColor: AppColors.onRedOrange,
          shadowColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
        ),
      ),
      dividerTheme: DividerThemeData(color: p.sage, space: 1),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: p.paper,
        elevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        indicatorColor: p.sage,
        indicatorShape: const RoundedRectangleBorder(),
        labelTextStyle: WidgetStateProperty.all(TextStyle(color: p.ink, fontSize: 12)),
        iconTheme: WidgetStateProperty.all(IconThemeData(color: p.ink)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: p.paper,
        selectedColor: AppColors.redOrange,
        // Black on the red-orange selected chip in both modes.
        labelStyle: TextStyle(
          color: WidgetStateColor.resolveWith(
            (states) => states.contains(WidgetState.selected) ? AppColors.onRedOrange : p.ink,
          ),
        ),
        side: BorderSide(color: p.ink),
        shape: const RoundedRectangleBorder(),
        elevation: 0,
        pressElevation: 0,
        showCheckmark: false,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.all(p.ink),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? AppColors.redOrange : p.sage,
        ),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
    );
  }
}
