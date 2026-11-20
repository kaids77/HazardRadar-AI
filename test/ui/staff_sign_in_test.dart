import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hazardradarai/models/user_profile.dart';
import 'package:hazardradarai/services/staff_auth.dart';
import 'package:hazardradarai/theme/app_theme.dart';
import 'package:hazardradarai/ui/common/feedback.dart';
import 'package:hazardradarai/ui/settings/staff_sign_in.dart';

const _scout = UserProfile(
  uid: 'google-uid-1',
  role: 'CITIZEN',
  tier: 2,
  accountStatus: 'ACTIVE',
  displayName: 'Charlie M',
);
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
  testWidgets('a Google account sees its name and email, never the uid, instead of the password form',
      (tester) async {
    await tester.pumpWidget(_app(() async => _scout));

    expect(find.text('Charlie M'), findsOneWidget);
    expect(find.text('staff@example.com'), findsOneWidget);
    expect(find.textContaining('google-uid-1'), findsNothing);
    expect(find.text('Sign in as staff'), findsNothing);

    await tester.tap(find.text('Check staff access'));
    await tester.pump();
    expect(find.textContaining('Ask an admin to give Charlie M'), findsOneWidget);
    // A missing role is a red-orange error block, not plain text.
    expect(tester.widget<FeedbackMessage>(find.byType(FeedbackMessage)).tone, FeedbackTone.error);
  });

  testWidgets('a Google account can sign out from Settings', (tester) async {
    var signedOut = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: StaffSignInSection(
              profile: _scout,
              isEmailSession: false,
              googleEmail: 'staff@example.com',
              onCheckAccess: () async => _scout,
              onSignIn: (_, _) async => _scout,
              onSignOut: () async => signedOut = true,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Sign out'));
    await tester.pump();
    expect(signedOut, isTrue);
  });

  testWidgets('checking access after an admin set the role reports that staff access is on', (tester) async {
    await tester.pumpWidget(_app(() async => _admin));

    await tester.tap(find.text('Check staff access'));
    await tester.pump();
    expect(find.text('Staff access is on. Open the Dispatch tab.'), findsOneWidget);
    // Success is the green block.
    expect(tester.widget<FeedbackMessage>(find.byType(FeedbackMessage)).tone, FeedbackTone.success);
  });

  testWidgets('a guest sees Sign in with Google as well as the staff email form', (tester) async {
    var google = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: StaffSignInSection(
              profile: const UserProfile(uid: 'g', role: 'CITIZEN', tier: 1, accountStatus: 'ACTIVE'),
              isEmailSession: false,
              onSignIn: (_, _) async => throw const StaffSignInFailed('Wrong email or password.'),
              onGoogleSignIn: () async => google = true,
              onSignOut: () async {},
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Sign in with Google'));
    await tester.pump();
    expect(google, isTrue);

    await tester.tap(find.text('Sign in as staff'));
    await tester.pump();
    expect(find.text('Wrong email or password.'), findsOneWidget);
    expect(tester.widget<FeedbackMessage>(find.byType(FeedbackMessage)).tone, FeedbackTone.error);
  });
}
