import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hazardradarai/models/incident.dart';
import 'package:hazardradarai/models/user_profile.dart';
import 'package:hazardradarai/services/moderation_repository.dart';
import 'package:hazardradarai/theme/app_theme.dart';
import 'package:hazardradarai/ui/dispatch/quarantine_screen.dart';

const _q = Incident(
  id: 'spam01',
  category: 'Other',
  riskLevel: 'Low',
  aiSummary: 'Photo of shoes.',
  latitude: 10.3,
  longitude: 123.9,
  netVotes: -4,
  visibility: 'QUARANTINED',
  note: 'lol',
);

class _Repo implements ModerationRepository {
  final calls = <String>[];

  @override
  Stream<List<Incident>> watchQuarantined({int limit = 100}) => Stream.value(const [_q]);

  @override
  Future<void> restore(Incident incident) async => calls.add('restore ${incident.id}');

  @override
  Future<int> purge(Incident incident) async {
    calls.add('purge ${incident.id}');
    return 3;
  }

  @override
  Future<StorageEstimate> storage() async =>
      StorageEstimate.compute(photoBytesSum: 100 * 96 * 1024, withBytes: 100, total: 100);
}

Future<_Repo> _pump(WidgetTester tester, UserProfile profile) async {
  tester.view.physicalSize = const Size(900, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final repo = _Repo();
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: QuarantineScreen(profile: profile, moderation: repo)),
    ),
  );
  await tester.pumpAndSettle();
  return repo;
}

const _admin = UserProfile(uid: 'a', role: 'ADMIN', tier: 5, accountStatus: 'ACTIVE');
const _dispatcher = UserProfile(uid: 'd', role: 'DISPATCHER', tier: 4, accountStatus: 'ACTIVE');

void main() {
  group('StorageEstimate', () {
    test('counts Base64 overhead and per-report overhead', () {
      final e = StorageEstimate.compute(photoBytesSum: 3 * 90000, withBytes: 3, total: 3);
      expect(e.usedBytes, (270000 * 4 / 3).round() + 3 * StorageEstimate.perReportOverheadBytes);
      expect(e.averagePhotoBytes, 90000);
    });

    test('estimates older reports at the average and reports uploads left', () {
      final e = StorageEstimate.compute(photoBytesSum: 100000, withBytes: 1, total: 4);
      expect(e.reports, 4);
      expect(e.usedBytes, (400000 * 4 / 3).round() + 4 * StorageEstimate.perReportOverheadBytes);
      expect(e.uploadsRemaining, greaterThan(7000));
      expect(StorageEstimate.compute(photoBytesSum: 0, withBytes: 0, total: 0).averagePhotoBytes,
          StorageEstimate.fallbackPhotoBytes);
    });
  });

  testWidgets('dispatchers can restore but not purge', (tester) async {
    final repo = await _pump(tester, _dispatcher);

    expect(find.text('Quarantined reports (1)'), findsOneWidget);
    expect(find.textContaining('of 1,024 MB'), findsOneWidget);
    expect(find.text('Permanently purge'), findsNothing);

    await tester.tap(find.text('Restore and verify'));
    await tester.pumpAndSettle();
    expect(repo.calls, ['restore spam01']);
  });

  testWidgets('admins purge after confirming', (tester) async {
    final repo = await _pump(tester, _admin);

    await tester.tap(find.text('Permanently purge'));
    await tester.pumpAndSettle();
    expect(find.text('Permanently purge HZD-SPAM01?'), findsOneWidget);
    await tester.tap(find.text('Purge'));
    await tester.pumpAndSettle();

    expect(repo.calls, ['purge spam01']);
    expect(find.text('Purged. Storage freed.'), findsOneWidget);
  });
}
