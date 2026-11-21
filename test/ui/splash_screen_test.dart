import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hazardradarai/ui/splash/splash_screen.dart';

void main() {
  const shortDisplay = Duration(milliseconds: 200);
  const shortFade = Duration(milliseconds: 100);

  Widget app() => MaterialApp(
        home: SplashScreen(
          nextBuilder: (_) => const Scaffold(body: Text('NEXT_SCREEN')),
          displayDuration: shortDisplay,
          transitionDuration: shortFade,
        ),
      );

  testWidgets('shows the wordmark and tagline', (tester) async {
    await tester.pumpWidget(app());

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
