import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hazardradarai/models/user_profile.dart';
import 'package:hazardradarai/services/account_linker.dart';
import 'package:hazardradarai/services/session_service.dart';
import 'package:hazardradarai/ui/account/account_sheet.dart';

import '../services/session_service_test.dart';

UserProfile _profile(int tier) =>
    UserProfile(uid: 'guest', role: 'CITIZEN', tier: tier, accountStatus: 'ACTIVE');

SessionService _session(Future<String?> Function() link) => SessionService(
      auth: FakeAuthService('guest'),
      profiles: FakeProfileRepository(),
      linker: FakeLinker(link),
    );

/// Opens the sheet from a button and records what it resolves to.
Future<List<UserProfile?>> _open(WidgetTester tester, UserProfile profile, SessionService session) async {
  final results = <UserProfile?>[];
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async =>
                results.add(await showAccountSheet(context, profile: profile, session: session)),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return results;
}

void main() {
  testWidgets('a guest upgrades and the sheet returns the Civic Scout profile', (tester) async {
    final results = await _open(tester, _profile(1), _session(() async => 'guest'));

    expect(find.textContaining('Commuter Observer'), findsOneWidget);
    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();

    expect(results.single?.tier, 2);
    expect(find.text('Continue with Google'), findsNothing);
  });

  testWidgets('cancelling keeps the sheet open with no error', (tester) async {
    final results = await _open(tester, _profile(1), _session(() async => null));

    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();

    expect(results, isEmpty);
    expect(find.text('Continue with Google'), findsOneWidget);
  });

  testWidgets('shows the failure message from the linker', (tester) async {
    await _open(
      tester,
      _profile(1),
      _session(() async => throw const LinkFailed('No connection. Try again when you are online.')),
    );

    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();

    expect(find.text('No connection. Try again when you are online.'), findsOneWidget);
  });

  testWidgets('linked users see no upgrade button', (tester) async {
    await _open(tester, _profile(2), _session(() async => 'guest'));

    expect(find.text('Civic Scout'), findsOneWidget);
    expect(find.text('Continue with Google'), findsNothing);
  });
}
