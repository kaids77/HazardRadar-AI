import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hazardradarai/models/transparency_entry.dart';

void main() {
  test('parses a resolved entry with its crew, note, and date', () {
    final entry = TransparencyEntry.tryFromFirestore('abc123xyz', {
      'category': 'Pothole',
      'riskLevel': 'Medium',
      'kind': 'RESOLVED',
      'reason': '',
      'crew': 'DPWH Patch Crew 4',
      'resolutionNote': 'Patched.',
      'at': Timestamp.fromMillisecondsSinceEpoch(1700000000000),
    })!;

    expect(entry.reference, 'HZD-ABC123');
    expect(entry.isResolved, isTrue);
    expect(entry.kindLabel, 'Resolved by city');
    expect(entry.crew, 'DPWH Patch Crew 4');
    expect(entry.at, DateTime.fromMillisecondsSinceEpoch(1700000000000));
  });

  test('quarantine reasons have plain labels; unknown or missing fields are handled', () {
    TransparencyEntry q(String reason, [String kind = 'QUARANTINED']) => TransparencyEntry.tryFromFirestore(
          'q1',
          {'category': 'Other', 'riskLevel': 'Low', 'kind': kind, 'reason': reason},
        )!;

    expect(q('COMMUNITY_VOTES').reasonLabel, 'Community votes: marked fixed or fake');
    expect(q('SENTINEL_FLAG').reasonLabel, 'Flagged as spam or duplicate by a Sentinel');
    expect(q('', 'PURGED').kindLabel, 'Removed as spam');
    expect(q('', 'RESTORED').isModeration, isTrue);
    expect(TransparencyEntry.tryFromFirestore('x', {'kind': 'RESOLVED'}), isNull);
  });

  test('new entry fields match the names the rules expect', () {
    expect(
      TransparencyEntry.fields(category: 'Pothole', riskLevel: 'High', kind: 'QUARANTINED', reason: 'SENTINEL_FLAG').keys,
      ['category', 'riskLevel', 'kind', 'reason', 'crew', 'resolutionNote'],
    );
  });

  test('the reporter credit is kept only on resolved entries of users who opted in', () {
    expect(TransparencyEntry.creditFor({'creditName': true, 'displayName': 'Bob Santos'}), 'Bob Santos');
    expect(TransparencyEntry.creditFor({'creditName': false, 'displayName': 'Bob Santos'}), isNull);
    expect(TransparencyEntry.creditFor({'displayName': 'Bob Santos'}), isNull);
    expect(TransparencyEntry.creditFor({'creditName': true}), isNull);
    expect(TransparencyEntry.creditFor(null), isNull);

    expect(
      TransparencyEntry.fields(category: 'Pothole', riskLevel: 'High', kind: 'RESOLVED', reporterName: 'Bob')['reporterName'],
      'Bob',
    );
    expect(
      TransparencyEntry.fields(category: 'Pothole', riskLevel: 'High', kind: 'PURGED', reporterName: 'Bob')
          .containsKey('reporterName'),
      isFalse,
    );
    final quarantined = TransparencyEntry.tryFromFirestore(
      'q1',
      {'category': 'Other', 'riskLevel': 'Low', 'kind': 'QUARANTINED', 'reporterName': 'Bob'},
    )!;
    expect(quarantined.reporterName, isNull);
  });
}
