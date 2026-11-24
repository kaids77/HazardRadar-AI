import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hazardradarai/models/user_profile.dart';
import 'package:hazardradarai/services/app_settings.dart';
import 'package:hazardradarai/theme/app_theme.dart';
import 'package:hazardradarai/ui/settings/settings_screen.dart';

const _scout = UserProfile(uid: 'u', role: 'CITIZEN', tier: 2, accountStatus: 'ACTIVE', displayName: 'Charlie M');

Future<AppSettings> _pump(WidgetTester tester, {ThemeData? theme, ValueChanged<bool>? onCreditName}) async {
  final settings = AppSettings(MemorySettingsStore());
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.light(),
      home: Scaffold(
        body: SettingsScreen(
          profile: _scout,
          settings: settings,
          name: 'Charlie M',
          hasAccount: true,
          onAccount: () {},
          onEditName: () {},
          onChangePhoto: () {},
          onCreditName: onCreditName,
          staffSection: const Text('Staff section'),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return settings;
}

void main() {
  testWidgets('the reporter credit switch is off by default and hidden without a callback', (tester) async {
    await _pump(tester);
    expect(find.text('Show my name on my resolved reports'), findsNothing);

    final changes = <bool>[];
    await _pump(tester, onCreditName: changes.add);
    expect(find.text('Show my name on my resolved reports'), findsOneWidget);
    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile).first).value, isFalse);
    await tester.tap(find.text('Show my name on my resolved reports'));
    await tester.pumpAndSettle();
    expect(changes, [true]);
  });
  testWidgets('every section shows: account, appearance, data, and staff', (tester) async {
    await _pump(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('ACTIVE'), findsOneWidget);
    expect(find.text('Edit name'), findsOneWidget);
    expect(find.text('Change photo'), findsOneWidget);
    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('Light'), findsOneWidget);
    expect(find.text('Dark'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Staff section'), 200);
    expect(find.text('Data saver'), findsOneWidget);
  });

  testWidgets('picking Dark saves dark mode', (tester) async {
    final settings = await _pump(tester);
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(settings.themeMode, ThemeMode.dark);
  });

  testWidgets('button labels are drawn in a visible color in light and dark mode', (tester) async {
    for (final (theme, expected) in [(AppTheme.light(), AppColors.ink), (AppTheme.dark(), AppColors.cream)]) {
      await _pump(tester, theme: theme);
      for (final label in ['Edit name', 'Change photo', 'Level details', 'Light']) {
        final paragraph = tester.renderObject<RenderParagraph>(find.text(label));
        final color = paragraph.text.style?.color;
        expect(color, isNotNull, reason: label);
        expect(color!.a, greaterThan(0.9), reason: '$label alpha');
        if (label != 'Light') expect(color, expected, reason: label);
      }
    }
  });

  testWidgets('the dark theme builds the same screen without errors', (tester) async {
    await _pump(tester, theme: AppTheme.dark());
    expect(tester.takeException(), isNull);
    expect(find.text('Appearance'), findsOneWidget);
  });
}
