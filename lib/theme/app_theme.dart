import 'package:flutter/material.dart';

/// Fixed colors from the approved design: cream, sage, and red-orange.
/// Low and Medium risk colors sit outside the palette on purpose (approved), so the
/// three risk levels stay easy to tell apart.
///
/// These never change with light or dark mode. Screens use [AppPalette] (through
/// `context.palette`) for the background, text, and panel colors that do change.
abstract final class AppColors {
  static const cream = Color(0xFFF3F7FA);
  static const sage = Color(0xFFD5E1E0);
  static const logoSage = Color(0xFF8AA3A0);
  static const redOrange = Color(0xFF111925);
  static const ink = Color(0xFF111925);

  // Crisp off-white text on the dark navy primary color.
  static const onRedOrange = cream;

  static const riskLow = Color(0xFF2F7A56);
  static const riskMedium = Color(0xFFC77700);
  static const riskHigh = Color(0xFFE73213);

  /// Reports a crew is working on. A flat ink-blue, with light text on top (about 9:1).
  static const inProgress = Color(0xFF2E4A62);
  static const onInProgress = cream;

  /// Success messages: a deeper green than [riskLow], so light text reaches about 5.6:1.
  static const success = Color(0xFF256446);
  static const onSuccess = cream;

  /// Error messages use high-risk red with dark text.
  static const error = Color(0xFFE73213);
  static const onError = Color(0xFF000000);

  /// Dark mode background and panel.
  static const darkPaper = Color(0xFF0F131E);
  static const darkSage = Color(0xFF1D2836);
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

/// Professional light and dark themes with rounded geometry, crisp outlines, and smooth transitions.
abstract final class AppTheme {
  static const BorderRadius radiusSm = BorderRadius.all(Radius.circular(10));
  static const BorderRadius radiusMd = BorderRadius.all(Radius.circular(14));
  static const BorderRadius radiusLg = BorderRadius.all(Radius.circular(20));
  static const BorderRadius radiusSheet = BorderRadius.vertical(top: Radius.circular(24));

  static ThemeData light() => _build(AppPalette.light, Brightness.light);

  static ThemeData dark() => _build(AppPalette.dark, Brightness.dark);

  static ThemeData _build(AppPalette p, Brightness brightness) {
    final isLight = brightness == Brightness.light;
    final base = isLight ? const ColorScheme.light() : const ColorScheme.dark();
    final primaryBg = isLight ? AppColors.ink : AppColors.cream;
    final onPrimaryFg = isLight ? AppColors.cream : AppColors.ink;
    final outlineColor = p.ink.withValues(alpha: isLight ? 0.18 : 0.24);
    final scheme = base.copyWith(
      primary: primaryBg,
      onPrimary: onPrimaryFg,
      primaryContainer: p.sage,
      onPrimaryContainer: p.ink,
      secondary: p.sage,
      onSecondary: p.ink,
      secondaryContainer: p.sage,
      onSecondaryContainer: p.ink,
      tertiary: p.sage,
      onTertiary: p.ink,
      tertiaryContainer: p.sage,
      onTertiaryContainer: p.ink,
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

    const buttonShape = RoundedRectangleBorder(borderRadius: radiusMd);
    final inputBorder = OutlineInputBorder(
      borderRadius: radiusMd,
      borderSide: BorderSide(color: p.ink.withValues(alpha: 0.35), width: 1.2),
    );
    final focusedInputBorder = OutlineInputBorder(
      borderRadius: radiusMd,
      borderSide: BorderSide(color: p.ink, width: 1.6),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      textTheme: textTheme,
      extensions: [p],
      scaffoldBackgroundColor: p.paper,
      canvasColor: p.paper,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: ZoomPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: ZoomPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.linux: ZoomPageTransitionsBuilder(),
        },
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: p.paper,
        foregroundColor: p.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        shape: Border(bottom: BorderSide(color: outlineColor)),
        titleTextStyle: TextStyle(fontFamily: 'DMSerifDisplay', fontSize: 22, color: p.ink),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: primaryBg),
      cardTheme: CardThemeData(
        color: p.sage,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: radiusLg,
          side: BorderSide(color: outlineColor),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.paper,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: radiusLg,
          side: BorderSide(color: outlineColor, width: 1.2),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.paper,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: radiusSheet,
          side: BorderSide(color: outlineColor, width: 1.2),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: p.paper,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: radiusMd,
          side: BorderSide(color: outlineColor),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: p.ink,
        contentTextStyle: TextStyle(color: p.paper),
        elevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: radiusMd),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.paper,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: inputBorder,
        enabledBorder: inputBorder,
        focusedBorder: focusedInputBorder,
        errorBorder: OutlineInputBorder(
          borderRadius: radiusMd,
          borderSide: const BorderSide(color: AppColors.error, width: 1.4),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: radiusMd,
          borderSide: const BorderSide(color: AppColors.error, width: 1.8),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: p.ink,
          shape: buttonShape,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: p.ink,
          side: BorderSide(color: p.ink.withValues(alpha: 0.45), width: 1.2),
          shape: buttonShape,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: primaryBg,
          foregroundColor: onPrimaryFg,
          shadowColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          shape: buttonShape,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: radiusMd),
        backgroundColor: primaryBg,
        foregroundColor: onPrimaryFg,
      ),
      dividerTheme: DividerThemeData(color: outlineColor, space: 1),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: p.paper,
        elevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        indicatorColor: p.sage,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: radiusMd,
          side: BorderSide(color: p.ink.withValues(alpha: 0.25)),
        ),
        labelTextStyle: WidgetStateProperty.all(TextStyle(color: p.ink, fontSize: 12, fontWeight: FontWeight.w600)),
        iconTheme: WidgetStateProperty.all(IconThemeData(color: p.ink)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: p.paper,
        selectedColor: primaryBg,
        secondarySelectedColor: primaryBg,
        color: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? primaryBg : p.paper,
        ),
        labelStyle: TextStyle(
          color: WidgetStateColor.resolveWith(
            (states) => states.contains(WidgetState.selected) ? onPrimaryFg : p.ink,
          ),
        ),
        secondaryLabelStyle: TextStyle(color: onPrimaryFg),
        side: BorderSide(color: p.ink.withValues(alpha: 0.35), width: 1.2),
        shape: const RoundedRectangleBorder(borderRadius: radiusSm),
        elevation: 0,
        pressElevation: 0,
        showCheckmark: false,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? onPrimaryFg : p.ink,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? primaryBg : p.sage,
        ),
        trackOutlineColor: WidgetStateProperty.all(p.ink.withValues(alpha: 0.25)),
      ),
    );
  }
}
