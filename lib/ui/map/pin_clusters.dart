import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../../models/incident.dart';

/// Pins that share one grid cell at the current zoom. A single pin is a cluster of one.
class PinCluster {
  factory PinCluster(List<Incident> members) {
    assert(members.isNotEmpty);
    if (members.length == 1) {
      final single = members.first;
      return PinCluster._(members, LatLng(single.latitude, single.longitude), single.riskLevel);
    }
    var latSum = 0.0;
    var lonSum = 0.0;
    var bestRisk = members.first.riskLevel;
    var bestRank = _rank(bestRisk);
    for (var i = 0; i < members.length; i++) {
      final m = members[i];
      latSum += m.latitude;
      lonSum += m.longitude;
      if (bestRank > 0) {
        final r = _rank(m.riskLevel);
        if (r < bestRank) {
          bestRank = r;
          bestRisk = m.riskLevel;
        }
      }
    }
    final count = members.length;
    return PinCluster._(members, LatLng(latSum / count, lonSum / count), bestRisk);
  }

  const PinCluster._(this.members, this.center, this.topRisk);

  final List<Incident> members;
  final LatLng center;

  /// The most severe risk level among the members: High, then Medium, then Low.
  final String topRisk;

  bool get isSingle => members.length == 1;

  static int _rank(String risk) => switch (risk) { 'High' => 0, 'Medium' => 1, 'Low' => 2, _ => 3 };
}

/// From this zoom up, every pin is drawn on its own.
const double clusterMaxZoom = 16;

/// Cached normalized Web Mercator [0..1] coordinates per [Incident] instance so zooming
/// across levels never re-evaluates `sin` and `log` for already-loaded pins.
final Expando<(double, double)> _normalizedMercator = Expando<(double, double)>('normalizedMercator');

(double, double) _projectNormalized(Incident incident) {
  final cached = _normalizedMercator[incident];
  if (cached != null) return cached;
  final nx = (incident.longitude + 180.0) / 360.0;
  final sinLat = math.sin(incident.latitude * (math.pi / 180.0)).clamp(-0.9999, 0.9999);
  final ny = 0.5 - math.log((1.0 + sinLat) / (1.0 - sinLat)) / (4.0 * math.pi);
  final projected = (nx, ny);
  _normalizedMercator[incident] = projected;
  return projected;
}

/// Groups pins into square screen cells of [cellPixels] at the whole-number [zoom].
///
/// Uses the Web Mercator pixel grid, so cells line up with what the map draws. Runs in
/// O(n) with cached normalized projection and a map of cell keys.
List<PinCluster> clusterPins(List<Incident> incidents, {required double zoom, double cellPixels = 64}) {
  if (incidents.isEmpty) return const [];
  if (zoom >= clusterMaxZoom) return [for (final incident in incidents) PinCluster([incident])];
  final zoomInt = zoom.floor().clamp(0, 30);
  final cellsPerAxis = (256 * (1 << zoomInt)) / cellPixels;
  final cells = <(int, int), List<Incident>>{};
  for (var i = 0; i < incidents.length; i++) {
    final incident = incidents[i];
    final (nx, ny) = _projectNormalized(incident);
    final key = ((nx * cellsPerAxis).floor(), (ny * cellsPerAxis).floor());
    (cells[key] ??= []).add(incident);
  }
  return [for (final members in cells.values) PinCluster(members)];
}
