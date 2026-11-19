import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hazardradarai/models/incident.dart';
import 'package:hazardradarai/models/user_profile.dart';
import 'package:hazardradarai/services/app_settings.dart';
import 'package:hazardradarai/services/my_reports_repository.dart';
import 'package:hazardradarai/theme/app_theme.dart';
import 'package:hazardradarai/ui/reports/my_reports_screen.dart';
import 'package:hazardradarai/ui/settings/settings_screen.dart';

Incident _incident(String id, String status, {bool ai = true, String? note}) => Incident(
      id: id,
      category: 'Pothole',
      riskLevel: 'Medium',
      aiSummary: 'Hole in lane.',
      latitude: 10.3,
      longitude: 123.9,
      netVotes: 0,
      status: status,
      aiProcessed: ai,
      resolutionNote: note,
    );

class _Repo implements MyReportsRepository {
  _Repo(this.items);

  final List<Incident> items;

  @override
  Stream<List<Incident>> watchMine(String uid, {int limit = 50}) => Stream.value(items);
}

class _CountingRepo implements MyReportsRepository {
  int subscriptions = 0;

  @override
  Stream<List<Incident>> watchMine(String uid, {int limit = 50}) {
    subscriptions++;
    return Stream.value(const []);
  }
}

UserProfile _profile({int tier = 2, int ctp = 120, int total = 10, int resolved = 9}) => UserProfile(
      uid: 'u',
      role: 'CITIZEN',
      tier: tier,
      accountStatus: 'ACTIVE',
      ctp: ctp,
      reportsTotal: total,
      reportsResolved: resolved,
    );

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(MaterialApp(theme: AppTheme.light(), home: Scaffold(body: child)));
  await tester.pump();
}

void main() {
  final reports = [
    _incident('aaaaaa1', 'ACTIVE', ai: false),
    _incident('bbbbbb2', 'IN_PROGRESS'),
    _incident('cccccc3', 'RESOLVED', note: 'Patched by crew B.'),
  ];

  testWidgets('a scout sees level, points, progress, and stats', (tester) async {
    await _pump(tester, MyReportsScreen(profile: _profile(), reports: _Repo(reports)));

    expect(find.text('Civic Scout'), findsOneWidget);
    expect(find.text('120'), findsOneWidget);
    expect(find.text('120 / 250 to Neighborhood Sentinel'), findsOneWidget);
    expect(find.text('90%'), findsOneWidget);
    expect(find.text('Guest profile'), findsNothing);
  });

  testWidgets('a guest sees the sign-in card', (tester) async {
    var tapped = false;
    await _pump(
      tester,
      MyReportsScreen(profile: _profile(tier: 1, ctp: 0), reports: _Repo(const []), onSignIn: () => tapped = true),
    );

    expect(find.text('Guest profile'), findsOneWidget);
    expect(find.text('You have not filed a report yet.'), findsOneWidget);
    await tester.tap(find.text('Sign in with Google'));
    expect(tapped, isTrue);
  });

  testWidgets('history shows status, pending AI review, and the city note; filters work', (tester) async {
    await _pump(tester, MyReportsScreen(profile: _profile(), reports: _Repo(reports)));

    expect(find.text('Pending AI review'), findsOneWidget);
    expect(find.text('City note: Patched by crew B.'), findsOneWidget);
    expect(find.text('All (3)'), findsOneWidget);

    await tester.tap(find.text('Resolved (1)'));
    await tester.pump();

    expect(find.text('Pothole · HZD-CCCCCC'), findsOneWidget);
    expect(find.text('Pothole · HZD-AAAAAA'), findsNothing);
  });

  testWidgets('a Sentinel without a badge picks one', (tester) async {
    String? picked;
    await _pump(
      tester,
      MyReportsScreen(
        profile: UserProfile(uid: 'u', role: 'VERIFIER', tier: 3, accountStatus: 'ACTIVE', ctp: 260),
        reports: _Repo(const []),
        onPickBadge: (badge) => picked = badge,
      ),
    );

    expect(find.text('Choose your focus badge'), findsOneWidget);
    await tester.tap(find.textContaining('Grid Guardian'));
    expect(picked, 'Grid Guardian');
  });

  testWidgets('pulling down reloads the profile and the list', (tester) async {
    var refreshed = 0;
    final repo = _CountingRepo();
    await _pump(
      tester,
      MyReportsScreen(profile: _profile(), reports: repo, onRefresh: () async => refreshed++),
    );
    expect(repo.subscriptions, 1);

    await tester.fling(find.text('My reports'), const Offset(0, 400), 1000);
    await tester.pumpAndSettle();

    expect(refreshed, 1);
    expect(repo.subscriptions, 2);
  });

  testWidgets('pulling down in Settings reloads the profile', (tester) async {
    var refreshed = 0;
    await _pump(
      tester,
      SettingsScreen(
        profile: _profile(),
        settings: AppSettings(MemorySettingsStore()),
        onRefresh: () async => refreshed++,
      ),
    );

    await tester.fling(find.text('Account'), const Offset(0, 400), 1000);
    await tester.pumpAndSettle();
    expect(refreshed, 1);
  });

  testWidgets('the data saver switch is saved', (tester) async {
    final store = MemorySettingsStore();
    final settings = AppSettings(store);
    await _pump(tester, SettingsScreen(profile: _profile(), settings: settings));

    await tester.tap(find.text('Data saver'));
    await tester.pump();

    expect(settings.dataSaver, isTrue);
    expect(store.values[AppSettings.dataSaverKey], isTrue);
  });
}
