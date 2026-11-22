import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hazardradarai/models/transparency_entry.dart';
import 'package:hazardradarai/theme/app_theme.dart';
import 'package:hazardradarai/ui/reports/transparency_section.dart';

final _entries = [
  TransparencyEntry(
    incidentId: 'abc123zz',
    category: 'Pothole',
    riskLevel: 'Medium',
    kind: TransparencyEntry.kindResolved,
    crew: 'DPWH Patch Crew 4',
    resolutionNote: 'Patched by City Engineering Team B',
    at: DateTime.utc(2026, 11, 20, 1),
  ),
  const TransparencyEntry(
    incidentId: 'def456zz',
    category: 'Other',
    riskLevel: 'Low',
    kind: TransparencyEntry.kindQuarantined,
    reason: TransparencyEntry.reasonCommunityVotes,
  ),
  const TransparencyEntry(
    incidentId: 'ghi789zz',
    category: 'Electrical',
    riskLevel: 'High',
    kind: TransparencyEntry.kindPurged,
  ),
];

Future<void> _pump(WidgetTester tester, List<TransparencyEntry> entries) async {
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: SingleChildScrollView(
          child: TransparencySection(
            entries: Stream.value(entries),
            counts: Future.value((resolved: 12, quarantined: 3)),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows resolved reports with the crew and note, and quarantined reports with the reason',
      (tester) async {
    await _pump(tester, _entries);

    expect(find.text('Report transparency'), findsOneWidget);
    expect(find.text('Resolved (12)'), findsOneWidget);
    expect(find.text('Quarantined (3)'), findsOneWidget);
    expect(find.text('Crew: DPWH Patch Crew 4'), findsOneWidget);
    expect(find.text('City note: Patched by City Engineering Team B'), findsOneWidget);
    expect(find.text('Community votes: marked fixed or fake'), findsOneWidget);
    expect(find.text('Removed as spam'), findsOneWidget);
    expect(find.text('Pothole · HZD-ABC123'), findsOneWidget);
  });

  testWidgets('the chips filter resolved and moderated entries', (tester) async {
    await _pump(tester, _entries);

    await tester.tap(find.text('Resolved (12)'));
    await tester.pumpAndSettle();
    expect(find.text('Crew: DPWH Patch Crew 4'), findsOneWidget);
    expect(find.text('Community votes: marked fixed or fake'), findsNothing);

    await tester.tap(find.text('Quarantined (3)'));
    await tester.pumpAndSettle();
    expect(find.text('Crew: DPWH Patch Crew 4'), findsNothing);
    expect(find.text('Removed as spam'), findsOneWidget);
  });

  testWidgets('an empty log says so', (tester) async {
    await _pump(tester, const []);
    expect(find.text('No resolved or quarantined reports yet.'), findsOneWidget);
  });
}
