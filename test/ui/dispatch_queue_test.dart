import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hazardradarai/models/incident.dart';
import 'package:hazardradarai/models/user_profile.dart';
import 'package:hazardradarai/services/dispatch_repository.dart';
import 'package:hazardradarai/services/user_admin_repository.dart';
import 'package:hazardradarai/theme/app_theme.dart';
import 'package:hazardradarai/ui/dispatch/dispatch_screen.dart';

Incident _i(String id, String risk, {String status = 'ACTIVE', DateTime? at, String visibility = 'PUBLIC', int votes = 0}) =>
    Incident(
      id: id,
      category: 'Pothole',
      riskLevel: risk,
      aiSummary: 'Summary $id',
      latitude: 10.3,
      longitude: 123.9,
      netVotes: votes,
      reporterUid: 'rep',
      status: status,
      visibility: visibility,
      createdAt: at,
    );

class _Repo implements DispatchRepository {
  _Repo(this.items);

  final List<Incident> items;
  final calls = <String>[];

  @override
  Stream<List<Incident>> watchQueue({int limit = 300}) => Stream.value(items);

  @override
  Future<({int resolved, int quarantined})> closedCounts() async => (resolved: 18, quarantined: 1);

  @override
  Future<void> startWork(Incident incident, {String? crew}) async => calls.add('start ${incident.id} $crew');

  @override
  Future<void> resolve(Incident incident, {required String note, required String staffUid}) async =>
      calls.add('resolve ${incident.id} $note $staffUid');

  @override
  Future<void> setCrew(Incident incident, String crew) async => calls.add('crew ${incident.id} $crew');

  @override
  Future<void> overrideTriage(Incident incident, {required String category, required String riskLevel}) async =>
      calls.add('override ${incident.id} $category $riskLevel');
}

const _dispatcher = UserProfile(uid: 'disp', role: 'DISPATCHER', tier: 4, accountStatus: 'ACTIVE');

class _Users implements UserAdminRepository {
  @override
  Stream<List<UserProfile>> watchUsers({int limit = 200}) => Stream.value(const [
        UserProfile(uid: 'rep', role: 'CITIZEN', tier: 2, accountStatus: 'WARNED', displayName: 'Bob Santos'),
        _dispatcher,
      ]);

  @override
  Future<void> setRole(String uid, RoleOption option) async {}

  @override
  Future<void> setStatus(String uid, String status, {DateTime? until}) async {}

  @override
  Future<void> setRateLimitOverride(String uid, bool value) async {}

  @override
  Future<int> quarantinedReports(String uid) async => 0;
}

Future<_Repo> _pump(
  WidgetTester tester,
  List<Incident> items, {
  UserProfile profile = _dispatcher,
  UserAdminRepository? users,
}) async {
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final repo = _Repo(items);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: DispatchScreen(profile: profile, dispatch: repo, users: users)),
    ),
  );
  await tester.pumpAndSettle();
  return repo;
}

void reporterTests() {
  testWidgets('staff see who reported each ticket; a dispatcher opens a read-only user page', (tester) async {
    await _pump(tester, [_i('a', 'High')], users: _Users());

    expect(find.text('Reported by Bob Santos · Civic Scout · WARNED'), findsOneWidget);
    expect(find.text('rep'), findsNothing);

    await tester.tap(find.text('Reported by Bob Santos · Civic Scout · WARNED'));
    await tester.pumpAndSettle();
    expect(find.text('Only admins can change accounts. Ask an admin to act on this user.'), findsOneWidget);
  });

  testWidgets('without profiles the ticket shows the reporter level only', (tester) async {
    await _pump(tester, [_i('a', 'High')]);
    expect(find.text('Reported by a Commuter Observer'), findsOneWidget);
  });
}

void main() {
  reporterTests();

  group('DispatchPolicy', () {
    test('sorts High to Low, then oldest first', () {
      final sorted = DispatchPolicy.sortQueue([
        _i('low', 'Low', at: DateTime(2026, 1, 1)),
        _i('high-new', 'High', at: DateTime(2026, 3, 1)),
        _i('high-old', 'High', at: DateTime(2026, 2, 1)),
        _i('med', 'Medium', at: DateTime(2026, 1, 1)),
      ]);
      expect(sorted.map((i) => i.id), ['high-old', 'high-new', 'med', 'low']);
    });

    test('only the next status step is allowed', () {
      expect(DispatchPolicy.nextStatus('ACTIVE'), 'IN_PROGRESS');
      expect(DispatchPolicy.nextStatus('IN_PROGRESS'), 'RESOLVED');
      expect(DispatchPolicy.nextStatus('RESOLVED'), isNull);
    });

    test('notes must be 1 to 300 characters and crews up to 60', () {
      expect(() => DispatchPolicy.validNote('  '), throwsA(isA<DispatchFailed>()));
      expect(() => DispatchPolicy.validNote('x' * 301), throwsA(isA<DispatchFailed>()));
      expect(DispatchPolicy.validNote(' Patched '), 'Patched');
      expect(() => DispatchPolicy.validCrew('x' * 61), throwsA(isA<DispatchFailed>()));
    });
  });

  testWidgets('shows counts and hides quarantined tickets', (tester) async {
    await _pump(tester, [
      _i('a', 'High'),
      _i('b', 'Medium', status: 'IN_PROGRESS'),
      _i('q', 'High', visibility: 'QUARANTINED'),
    ]);

    expect(find.text('18'), findsOneWidget);
    expect(find.text('Summary a'), findsOneWidget);
    expect(find.text('Summary q'), findsNothing);
    expect(find.text('Start work'), findsOneWidget);
    expect(find.text('Resolve'), findsOneWidget);
  });

  testWidgets('start work asks for a crew, then saves', (tester) async {
    final repo = await _pump(tester, [_i('a', 'High')]);

    await tester.tap(find.text('Start work'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'DPWH Crew 4');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(repo.calls, ['start a DPWH Crew 4']);
    expect(find.text('Marked in progress.'), findsOneWidget);
  });

  testWidgets('resolving needs a note and passes the staff uid', (tester) async {
    final repo = await _pump(tester, [_i('b', 'Low', status: 'IN_PROGRESS')]);

    await tester.tap(find.text('Resolve').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Resolve').last);
    await tester.pumpAndSettle();
    expect(find.text('Write a short resolution note.'), findsOneWidget);
    expect(repo.calls, isEmpty);

    await tester.enterText(find.byType(TextField), 'Patched by crew B');
    await tester.tap(find.text('Resolve').last);
    await tester.pumpAndSettle();

    expect(repo.calls, ['resolve b Patched by crew B disp']);
  });

  testWidgets('the AI rating can be overridden', (tester) async {
    final repo = await _pump(tester, [_i('a', 'Low')]);

    await tester.tap(find.text('Override AI'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Low').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('High').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(repo.calls, ['override a Pothole High']);
  });

  testWidgets('the risk filter narrows the queue', (tester) async {
    await _pump(tester, [_i('a', 'High'), _i('m', 'Medium')]);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Medium'));
    await tester.pumpAndSettle();

    expect(find.text('Summary m'), findsOneWidget);
    expect(find.text('Summary a'), findsNothing);
  });

  testWidgets('paginates open tickets 5 per page', (tester) async {
    await _pump(tester, [for (var i = 1; i <= 6; i++) _i('t$i', 'High', at: DateTime(2026, 1, i))]);

    expect(find.text('Page 1 of 2 (1–5 of 6)'), findsOneWidget);
    expect(find.text('Summary t1'), findsOneWidget);
    expect(find.text('Summary t6'), findsNothing);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    expect(find.text('Page 2 of 2 (6–6 of 6)'), findsOneWidget);
    expect(find.text('Summary t1'), findsNothing);
    expect(find.text('Summary t6'), findsOneWidget);
  });

  testWidgets('a verified ticket shows the green Verified badge and green vote count', (tester) async {
    await _pump(tester, [_i('v', 'Medium', votes: 4)]);

    expect(find.text('Verified'), findsOneWidget);
    expect(find.textContaining('+4 votes'), findsOneWidget);
  });
}
