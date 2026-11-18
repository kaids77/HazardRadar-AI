import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:hazardradarai/models/incident.dart';
import 'package:hazardradarai/models/user_profile.dart';
import 'package:hazardradarai/services/incident_repository.dart';
import 'package:hazardradarai/services/location_service.dart';
import 'package:hazardradarai/services/session_service.dart';
import 'package:hazardradarai/services/vote_repository.dart';
import 'package:hazardradarai/ui/account/account_sheet.dart';
import 'package:hazardradarai/ui/map/incident_sheet.dart';

import '../services/session_service_test.dart';

const _incident = Incident(
  id: 'inc-1',
  category: 'Electrical',
  riskLevel: 'High',
  aiSummary: 'Sparking wire near the walkway.',
  recommendedAction: 'Keep clear.',
  latitude: 10.3236,
  longitude: 123.9322,
  netVotes: 3,
  reporterUid: 'reporter',
);

class _Incidents implements IncidentRepository {
  @override
  Stream<List<Incident>> watchActivePublic({int limit = 150}) => const Stream.empty();

  @override
  Future<Uint8List?> loadPhoto(String incidentId) async => null;
}

class _Votes implements VoteRepository {
  final cast_ = <int>[];
  bool alreadyVoted = false;

  @override
  Future<void> cast({required String incidentId, required String uid, required int value}) async {
    if (alreadyVoted) throw const AlreadyVotedException();
    cast_.add(value);
  }
}

class _Location implements LocationProvider {
  _Location(this.position);

  final LatLng? position;

  @override
  Future<LatLng> currentOrFallback() async => position ?? GeolocatorLocationService.fallbackCenter;

  @override
  Future<LatLng?> current() async => position;

  @override
  Future<LocationFix?> currentFix() async => position == null ? null : LocationFix(position!);
}

UserProfile _profile(int tier, {String uid = 'me'}) =>
    UserProfile(uid: uid, role: 'CITIZEN', tier: tier, accountStatus: 'ACTIVE');

Future<_Votes> _open(
  WidgetTester tester, {
  required int tier,
  LatLng? position = const LatLng(10.3236, 123.9322),
  String uid = 'me',
  bool alreadyVoted = false,
  Future<UserProfile?> Function()? onUpgrade,
}) async {
  final votes = _Votes()..alreadyVoted = alreadyVoted;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: IncidentSheet(
          incident: _incident,
          profile: _profile(tier, uid: uid),
          incidents: _Incidents(),
          votes: votes,
          location: _Location(position),
          onUpgrade: onUpgrade,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return votes;
}

void main() {
  testWidgets('a guest who upgrades has the vote cast exactly once with the new weight', (tester) async {
    var prompts = 0;
    final votes = await _open(
      tester,
      tier: 1,
      onUpgrade: () async {
        prompts++;
        return _profile(2, uid: 'linked');
      },
    );

    await tester.tap(find.text('Still here'));
    await tester.pumpAndSettle();

    expect(prompts, 1);
    expect(votes.cast_, [1]);
    expect(find.text('Vote recorded.'), findsOneWidget);
  });

  testWidgets('a guest who stays a guest casts nothing', (tester) async {
    final votes = await _open(tester, tier: 1, onUpgrade: () async => null);

    await tester.tap(find.text('Still here'));
    await tester.pumpAndSettle();

    expect(votes.cast_, isEmpty);
    expect(find.text('Vote recorded.'), findsNothing);
  });

  testWidgets('the guest prompt shows the reason and can be dismissed', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AccountSheet(
            profile: _profile(1),
            session: SessionService(auth: FakeAuthService('me'), profiles: FakeProfileRepository()),
            reason: UpgradeReason.vote,
          ),
        ),
      ),
    );
    expect(find.textContaining('Voting needs a linked Google account'), findsOneWidget);
    expect(find.text('Continue as guest'), findsOneWidget);
  });

  testWidgets('an upgraded user still cannot vote on their own report', (tester) async {
    final votes = await _open(tester, tier: 1, onUpgrade: () async => _profile(2, uid: 'reporter'));

    await tester.tap(find.text('Fixed or fake'));
    await tester.pumpAndSettle();

    expect(votes.cast_, isEmpty);
    expect(find.text('You cannot vote on your own report.'), findsOneWidget);
  });

  testWidgets('shows the summary, verified badge, and distance', (tester) async {
    await _open(tester, tier: 2);

    expect(find.text('Electrical'), findsOneWidget);
    expect(find.text('Sparking wire near the walkway.'), findsOneWidget);
    expect(find.text('Verified hazard'), findsOneWidget);
    expect(find.text('0 m away'), findsOneWidget);
  });

  testWidgets('a tier 2 user votes with weight 1', (tester) async {
    final votes = await _open(tester, tier: 2);

    await tester.tap(find.text('Still here'));
    await tester.pumpAndSettle();

    expect(votes.cast_, [1]);
    expect(find.text('Vote recorded.'), findsOneWidget);
  });

  testWidgets('a tier 3 user casts a double negative vote', (tester) async {
    final votes = await _open(tester, tier: 3);

    await tester.tap(find.text('Fixed or fake'));
    await tester.pumpAndSettle();

    expect(votes.cast_, [-2]);
  });

  testWidgets('guests are told to sign in and nothing is sent', (tester) async {
    final votes = await _open(tester, tier: 1);

    await tester.tap(find.text('Still here'));
    await tester.pumpAndSettle();

    expect(find.text('Sign in with Google to vote on hazards.'), findsOneWidget);
    expect(votes.cast_, isEmpty);
  });

  testWidgets('voting is blocked beyond 200 m', (tester) async {
    final votes = await _open(tester, tier: 2, position: const LatLng(10.3336, 123.9322));

    await tester.tap(find.text('Still here'));
    await tester.pumpAndSettle();

    expect(find.text('Voting opens within 200 m of the hazard.'), findsOneWidget);
    expect(votes.cast_, isEmpty);
  });

  testWidgets('shows a notice when the user already voted', (tester) async {
    await _open(tester, tier: 2, alreadyVoted: true);

    await tester.tap(find.text('Still here'));
    await tester.pumpAndSettle();

    expect(find.text('You already voted on this report.'), findsOneWidget);
  });
}
