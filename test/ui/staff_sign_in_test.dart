import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hazardradarai/models/user_profile.dart';
import 'package:hazardradarai/theme/app_theme.dart';
import 'package:hazardradarai/ui/settings/staff_sign_in.dart';

const _scout = UserProfile(uid: 'google-uid-1', role: 'CITIZEN', tier: 2, accountStatus: 'ACTIVE');
const _admin = UserProfile(uid: 'google-uid-1', role: 'ADMIN', tier: 5, accountStatus: 'ACTIVE');

Widget _app(Future<UserProfile?> Function() onCheck) => MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: SingleChildScrollView(
          child: StaffSignInSection(
            profile: _scout,
            isEmailSession: false,
            googleEmail: 'staff@example.com',
            onCheckAccess: onCheck,
            onSignIn: (_, _) async => _scout,
            onSignOut: () async {},
          ),
        ),
      ),
    );

void main() {
  testWidgets('a Google account sees its account ID instead of the password form', (tester) async {
    await tester.pumpWidget(_app(() async => _scout));

    expect(find.text('Account ID: google-uid-1'), findsOneWidget);
    expect(find.text('Sign in as staff'), findsNothing);

    await tester.tap(find.text('Check staff access'));
    await tester.pump();
    expect(find.textContaining('No staff role on this account yet'), findsOneWidget);
  });

  testWidgets('checking access after an admin set the role reports that staff access is on', (tester) async {
    await tester.pumpWidget(_app(() async => _admin));

    await tester.tap(find.text('Check staff access'));
    await tester.pump();
    expect(find.text('Staff access is on. Open the Dispatch tab.'), findsOneWidget);
  });
}
