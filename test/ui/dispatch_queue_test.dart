import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hazardradarai/models/incident.dart';
import 'package:hazardradarai/models/user_profile.dart';
import 'package:hazardradarai/services/dispatch_repository.dart';
import 'package:hazardradarai/theme/app_theme.dart';
import 'package:hazardradarai/ui/dispatch/dispatch_screen.dart';

Incident _i(String id, String risk, {String status = 'ACTIVE', DateTime? at, String visibility = 'PUBLIC'}) =>
    Incident(
      id: id,
      category: 'Pothole',
      riskLevel: risk,
      aiSummary: 'Summary $id',
      latitude: 10.3,
      longitude: 123.9,
      netVotes: 0,
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

Future<_Repo> _pump(WidgetTester tester, List<Incident> items, {UserProfile profile = _dispatcher}) async {
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final repo = _Repo(items);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: DispatchScreen(profile: profile, dispatch: repo)),
    ),
  );
  await tester.pumpAndSettle();
  return repo;
}

void main() {
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
}
