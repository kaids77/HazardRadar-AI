import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hazardradarai/models/user_profile.dart';
import 'package:hazardradarai/services/auth_service.dart';
import 'package:hazardradarai/services/profile_repository.dart';
import 'package:hazardradarai/services/session_service.dart';
import 'package:hazardradarai/ui/home/home_screen.dart';

class _OkAuth implements AuthService {
  @override
  Future<String> ensureSignedIn() async => 'uid-abc';
}

class _FailingAuth implements AuthService {
  @override
  Future<String> ensureSignedIn() async => throw StateError('offline');
}

class _ProfileRepo implements ProfileRepository {
  @override
  Future<UserProfile> getOrCreateProfile(String uid) async => UserProfile(
        uid: uid,
        role: 'CITIZEN',
        tier: 1,
        accountStatus: 'ACTIVE',
      );
}

void main() {
  testWidgets('shows a loading indicator, then the commuter profile', (tester) async {
    final session = SessionService(auth: _OkAuth(), profiles: _ProfileRepo());
    await tester.pumpWidget(MaterialApp(home: HomeScreen(session: session)));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pumpAndSettle();

    expect(find.text('Commuter Observer'), findsOneWidget);
    expect(find.text('uid: uid-abc'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('shows a retry action when sign-in fails', (tester) async {
    final session = SessionService(auth: _FailingAuth(), profiles: _ProfileRepo());
    await tester.pumpWidget(MaterialApp(home: HomeScreen(session: session)));
    await tester.pumpAndSettle();

    expect(find.text('Retry'), findsOneWidget);
    expect(find.textContaining('Could not connect'), findsOneWidget);
  });
}
