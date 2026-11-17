import 'package:flutter_test/flutter_test.dart';

import 'package:hazardradarai/models/incident.dart';

void main() {
  Map<String, Object?> valid() => {
        'category': 'Electrical',
        'riskLevel': 'High',
        'aiSummary': 'Sparking wire.',
        'latitude': 14.6091,
        'longitude': 120.9890,
        'netVotes': 2,
      };

  test('parses a complete document', () {
    final incident = Incident.tryFromFirestore('abc', valid());

    expect(incident, isNotNull);
    expect(incident!.id, 'abc');
    expect(incident.riskLevel, 'High');
    expect(incident.latitude, closeTo(14.6091, 1e-9));
    expect(incident.netVotes, 2);
  });

  test('accepts integer coordinates and defaults missing votes to zero', () {
    final data = valid()
      ..['latitude'] = 14
      ..remove('netVotes');

    final incident = Incident.tryFromFirestore('abc', data);

    expect(incident!.latitude, 14.0);
    expect(incident.netVotes, 0);
  });

  test('skips documents with missing or malformed fields', () {
    final missingCategory = valid()..remove('category');
    expect(Incident.tryFromFirestore('a', missingCategory), isNull);

    final stringLatitude = valid()..['latitude'] = '14.6';
    expect(Incident.tryFromFirestore('b', stringLatitude), isNull);
  });

  test('skips coordinates outside the valid range', () {
    final badLatitude = valid()..['latitude'] = 95;
    expect(Incident.tryFromFirestore('c', badLatitude), isNull);

    final badLongitude = valid()..['longitude'] = -181;
    expect(Incident.tryFromFirestore('d', badLongitude), isNull);
  });
}
