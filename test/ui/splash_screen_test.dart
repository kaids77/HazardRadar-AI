import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hazardradarai/theme/app_theme.dart';
import 'package:hazardradarai/ui/common/app_logo.dart';
import 'package:hazardradarai/ui/splash/splash_screen.dart';

void main() {
  const shortDisplay = Duration(milliseconds: 200);
  const shortFade = Duration(milliseconds: 100);

  Widget app({ThemeData? theme}) => MaterialApp(
        theme: theme,
        home: SplashScreen(
          nextBuilder: (_) => const Scaffold(body: Text('NEXT_SCREEN')),
          displayDuration: shortDisplay,
          transitionDuration: shortFade,
        ),
      );

  testWidgets('shows the light logo, wordmark, and tagline', (tester) async {
    await tester.pumpWidget(app(theme: AppTheme.dark()));

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
    expect(scaffold.backgroundColor, AppColors.cream);
    expect(find.byType(AppLogo), findsOneWidget);
    expect(tester.widget<AppLogo>(find.byType(AppLogo)).forceLight, isTrue);
    expect(find.text(SplashScreen.wordmark), findsOneWidget);
    expect(find.text(SplashScreen.tagline), findsOneWidget);
    expect(find.text('NEXT_SCREEN'), findsNothing);

    // Let the pending advance timer finish so the test exits cleanly.
    await tester.pumpAndSettle();
  });

  testWidgets('moves to the next screen after the display duration',
      (tester) async {
    await tester.pumpWidget(app());

    await tester.pump(shortDisplay - const Duration(milliseconds: 10));
    expect(find.text('NEXT_SCREEN'), findsNothing);

    await tester.pumpAndSettle();
    expect(find.text('NEXT_SCREEN'), findsOneWidget);
    expect(find.text(SplashScreen.wordmark), findsNothing);
  });
}
