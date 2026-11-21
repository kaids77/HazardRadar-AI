import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:hazardradarai/models/incident.dart';
import 'package:hazardradarai/ui/map/pin_clusters.dart';
import 'package:hazardradarai/ui/map/proximity_alert.dart';

Incident _at(String id, double lat, double lon, {String risk = 'Low'}) => Incident(
      id: id,
      category: 'Pothole',
      riskLevel: risk,
      aiSummary: 's',
      latitude: lat,
      longitude: lon,
      netVotes: 0,
      status: 'ACTIVE',
    );

void main() {
  group('clusterPins', () {
    // About 20 m apart in Mandaue, plus one in Cebu City about 4 km away.
    final pins = [
      _at('a', 10.32360, 123.93220),
      _at('b', 10.32375, 123.93230, risk: 'High'),
      _at('c', 10.32350, 123.93210, risk: 'Medium'),
      _at('far', 10.2950, 123.9000),
    ];

    test('groups close pins and keeps distant ones apart at city zoom', () {
      final clusters = clusterPins(pins, zoom: 13);
      expect(clusters, hasLength(2));
      final group = clusters.firstWhere((c) => !c.isSingle);
      expect(group.members.map((i) => i.id), unorderedEquals(['a', 'b', 'c']));
      expect(group.topRisk, 'High');
      expect(group.center.latitude, closeTo(10.32362, 0.0001));
    });

    test('shows every pin on its own from the cluster max zoom', () {
      expect(clusterPins(pins, zoom: clusterMaxZoom).every((c) => c.isSingle), isTrue);
      expect(clusterPins(pins, zoom: 18), hasLength(4));
    });

    test('puts everything in one cluster when zoomed out to the whole country', () {
      final clusters = clusterPins(pins, zoom: 5);
      expect(clusters, hasLength(1));
      expect(clusters.single.members, hasLength(4));
    });

    test('returns nothing for no pins', () {
      expect(clusterPins(const [], zoom: 12), isEmpty);
    });
  });

  group('nearestUnwarnedHigh', () {
    const me = LatLng(10.3236, 123.9322);
    // 0.0005 degrees of latitude is about 55 m; 0.002 is about 220 m.
    final near = _at('near', 10.3241, 123.9322, risk: 'High');
    final nearer = _at('nearer', 10.3238, 123.9322, risk: 'High');
    final medium = _at('medium', 10.3237, 123.9322, risk: 'Medium');
    final far = _at('far', 10.3256, 123.9322, risk: 'High');

    test('picks the closest High hazard within 100 m', () {
      final hit = nearestUnwarnedHigh(me, [near, nearer, medium, far], {});
      expect(hit?.incident.id, 'nearer');
      expect(hit!.meters, lessThan(30));
    });

    test('skips hazards already announced this session', () {
      expect(nearestUnwarnedHigh(me, [near, nearer], {'nearer'})?.incident.id, 'near');
      expect(nearestUnwarnedHigh(me, [near, nearer], {'near', 'nearer'}), isNull);
    });

    test('ignores Medium and Low hazards and High ones beyond 100 m', () {
      expect(nearestUnwarnedHigh(me, [medium, far], {}), isNull);
    });
  });
}
