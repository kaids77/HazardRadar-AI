import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hazardradarai/models/incident.dart';
import 'package:hazardradarai/services/analytics.dart';
import 'package:hazardradarai/theme/app_theme.dart';
import 'package:hazardradarai/ui/dispatch/analytics_screen.dart';

// 10:00 in Manila on 18 Nov 2026.
final _now = DateTime.utc(2026, 11, 18, 2);

Incident _i(
  String id, {
  String category = 'Pothole',
  String risk = 'High',
  String status = 'ACTIVE',
  String visibility = 'PUBLIC',
  bool ai = true,
  String geohash = 'wdu3yz',
  DateTime? created,
  DateTime? resolved,
}) =>
    Incident(
      id: id,
      category: category,
      riskLevel: risk,
      aiSummary: 's',
      latitude: 10.3,
      longitude: 123.9,
      netVotes: 0,
      status: status,
      visibility: visibility,
      aiProcessed: ai,
      geohash: geohash,
      createdAt: created,
      resolvedAt: resolved,
    );

final _data = [
  _i('a', risk: 'High'),
  _i('b', risk: 'Medium', category: 'Flooding', geohash: 'wdu3zz'),
  _i('c', risk: 'Low', status: 'IN_PROGRESS', ai: false),
  _i('d',
      status: 'RESOLVED',
      created: DateTime.utc(2026, 11, 17, 20),
      resolved: DateTime.utc(2026, 11, 18, 0)), // 4 h, resolved today in Manila
  _i('e',
      status: 'RESOLVED',
      category: 'Electrical',
      created: DateTime.utc(2026, 11, 10),
      resolved: DateTime.utc(2026, 11, 10, 2)), // 2 h, an earlier day
  _i('q', visibility: 'QUARANTINED', category: 'Other'),
];

class _Repo implements AnalyticsRepository {
  @override
  Future<List<Incident>> recent({int limit = 500}) async => _data;
}

void main() {
  test('computes counts, rate, MTTR, categories, hotspots, and AI health', () {
    final a = CityAnalytics.compute(_data, _now);

    expect(a.total, 6);
    expect((a.activeHigh, a.activeMedium, a.activeLow), (1, 1, 0));
    expect(a.inProgress, 1);
    expect(a.resolved, 2);
    expect(a.resolvedToday, 1);
    expect(a.quarantined, 1);
    expect(a.resolutionRate, closeTo(2 / 5, 1e-9));
    expect(a.meanTimeToResolve, const Duration(hours: 3));
    expect(a.categoryCounts['Pothole'], 3);
    expect(a.categoryCounts['Lighting'], 0);
    expect(a.hotspots.first, (geohash: 'wdu3yz', count: 2));
    expect(a.aiProcessedShare, closeTo(5 / 6, 1e-9));
  });

  test('empty data gives zeros and no MTTR', () {
    final a = CityAnalytics.compute(const [], _now);
    expect(a.resolutionRate, 0);
    expect(a.meanTimeToResolve, isNull);
    expect(a.hotspots, isEmpty);
  });

  test('durations read naturally', () {
    expect(formatDuration(const Duration(minutes: 35)), '35 min');
    expect(formatDuration(const Duration(minutes: 252)), '4.2 h');
    expect(formatDuration(const Duration(days: 3)), '3.0 days');
  });

  testWidgets('shows the numbers', (tester) async {
    tester.view.physicalSize = const Size(900, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: AnalyticsScreen(analytics: _Repo(), clock: () => _now)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('40.0%'), findsOneWidget);
    expect(find.text('3.0 h'), findsOneWidget);
    expect(find.textContaining('1. wdu3yz · 2 open'), findsOneWidget);
    expect(find.textContaining('83% of reports classified by Radar AI'), findsOneWidget);
  });
}
