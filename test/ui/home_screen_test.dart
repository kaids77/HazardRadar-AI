import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:hazardradarai/geo/philippine_day.dart';
import 'package:hazardradarai/models/incident.dart';
import 'package:hazardradarai/models/report.dart';
import 'package:hazardradarai/models/user_profile.dart';
import 'package:hazardradarai/services/app_settings.dart';
import 'package:hazardradarai/services/auth_service.dart';
import 'package:hazardradarai/services/incident_repository.dart';
import 'package:hazardradarai/services/location_service.dart';
import 'package:hazardradarai/services/my_reports_repository.dart';
import 'package:hazardradarai/services/photo_service.dart';
import 'package:hazardradarai/services/profile_repository.dart';
import 'package:hazardradarai/services/report_repository.dart';
import 'package:hazardradarai/services/report_service.dart';
import 'package:hazardradarai/services/session_service.dart';
import 'package:hazardradarai/services/triage_service.dart';
import 'package:hazardradarai/services/vote_repository.dart';
import 'package:hazardradarai/ui/home/home_screen.dart';
import 'package:hazardradarai/ui/home/home_services.dart';

class _OkAuth implements AuthService {
  @override
  Future<String> ensureSignedIn() async => 'uid-abc';
}

class _FailingAuth implements AuthService {
  @override
  Future<String> ensureSignedIn() async => throw StateError('offline');
}

class _ProfileRepo implements ProfileRepository {
  _ProfileRepo([this.profile]);

  final UserProfile Function(String uid)? profile;

  @override
  Future<UserProfile> getOrCreateProfile(String uid) async =>
      profile?.call(uid) ??
      UserProfile(
        uid: uid,
        role: 'CITIZEN',
        tier: 1,
        accountStatus: 'ACTIVE',
      );

  @override
  Future<UserProfile> upgradeToCivicScout(String uid) async => UserProfile(
        uid: uid,
        role: 'CITIZEN',
        tier: 2,
        accountStatus: 'ACTIVE',
      );

  @override
  Future<UserProfile> applyEarnedLevel(String uid) => getOrCreateProfile(uid);

  @override
  Future<void> setFocusBadge(String uid, String badge) async {}

  @override
  Future<void> setDisplayName(String uid, String name) async {}
}

class _NoIncidents implements IncidentRepository {
  @override
  Stream<List<Incident>> watchActivePublic({int limit = 150}) =>
      Stream.value(const <Incident>[]);

  @override
  Future<Uint8List?> loadPhoto(String incidentId) async => null;
}

class _NoVotes implements VoteRepository {
  @override
  Future<int> cast({required String incidentId, required String uid, required int value}) async => value;

  @override
  Future<void> flag({required String incidentId, required String uid}) async {}
}

class _FixedLocation implements LocationProvider {
  @override
  Future<LatLng> currentOrFallback() async => GeolocatorLocationService.fallbackCenter;

  @override
  Future<LatLng?> current() async => GeolocatorLocationService.fallbackCenter;

  @override
  Future<LocationFix?> currentFix() async => const LocationFix(GeolocatorLocationService.fallbackCenter);

  @override
  Stream<LocationFix> watchFix() => const Stream.empty();
}

class _NoPhotos implements PhotoCapture {
  @override
  Future<CompressedPhoto?> takePhoto() async => null;
}

class _NoRepo implements ReportRepository {
  @override
  Future<String> create(NewReport report) async => 'id';
}

class _MyReports implements MyReportsRepository {
  @override
  Stream<List<Incident>> watchMine(String uid, {int limit = 50}) => Stream.value(const <Incident>[]);
}

Widget _app(SessionService session) => MaterialApp(
      home: HomeScreen(
        services: HomeServices(
          session: session,
          incidents: _NoIncidents(),
          location: _FixedLocation(),
          reports: ReportService(
            auth: _OkAuth(),
            triage: const KeywordTriageService(),
            repository: _NoRepo(),
          ),
          photos: _NoPhotos(),
          votes: _NoVotes(),
          myReports: _MyReports(),
          settings: AppSettings(MemorySettingsStore()),
        ),
      ),
    );

void main() {
  testWidgets('shows a loading indicator, then the guest name in the app bar', (tester) async {
    final session = SessionService(auth: _OkAuth(), profiles: _ProfileRepo());
    await tester.pumpWidget(_app(session));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pump();
    await tester.pump();

    expect(find.text('Guest'), findsOneWidget);
    expect(find.text('Report hazard'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('shows a retry action when sign-in fails', (tester) async {
    final session = SessionService(auth: _FailingAuth(), profiles: _ProfileRepo());
    await tester.pumpWidget(_app(session));
    await tester.pumpAndSettle();

    expect(find.text('Retry'), findsOneWidget);
    expect(find.textContaining('Could not connect'), findsOneWidget);
  });

  testWidgets('a guest at the daily limit is offered Google sign-in instead of the camera', (tester) async {
    final session = SessionService(
      auth: _OkAuth(),
      profiles: _ProfileRepo(
        (uid) => UserProfile(
          uid: uid,
          role: 'CITIZEN',
          tier: 1,
          accountStatus: 'ACTIVE',
          reportDay: philippineDay(DateTime.now()),
          reportCount: 3,
        ),
      ),
    );
    await tester.pumpWidget(_app(session));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    await tester.tap(find.text('Report hazard'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.textContaining('Guests can file 3 reports a day'), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('Send report'), findsNothing);
  });

  testWidgets('a warned account sees the moderator warning', (tester) async {
    final session = SessionService(
      auth: _OkAuth(),
      profiles: _ProfileRepo((uid) => UserProfile(uid: uid, role: 'CITIZEN', tier: 2, accountStatus: 'WARNED')),
    );
    await tester.pumpWidget(_app(session));
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('warning from a moderator'), findsOneWidget);
  });
}
