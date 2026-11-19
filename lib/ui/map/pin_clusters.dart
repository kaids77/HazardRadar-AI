import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../../models/incident.dart';

/// Pins that share one grid cell at the current zoom. A single pin is a cluster of one.
class PinCluster {
  PinCluster(this.members)
      : assert(members.isNotEmpty),
        center = LatLng(
          members.map((i) => i.latitude).reduce((a, b) => a + b) / members.length,
          members.map((i) => i.longitude).reduce((a, b) => a + b) / members.length,
        );

  final List<Incident> members;
  final LatLng center;

  bool get isSingle => members.length == 1;

  /// The most severe risk level among the members: High, then Medium, then Low.
  String get topRisk => members.map((i) => i.riskLevel).reduce((a, b) => _rank(a) <= _rank(b) ? a : b);

  static int _rank(String risk) => switch (risk) { 'High' => 0, 'Medium' => 1, 'Low' => 2, _ => 3 };
}

/// From this zoom up, every pin is drawn on its own.
const double clusterMaxZoom = 16;

/// Groups pins into square screen cells of [cellPixels] at the whole-number [zoom].
///
/// Uses the Web Mercator pixel grid, so cells line up with what the map draws. Runs in
/// O(n) with a map of cell keys, which is fine for the few hundred pins the stream returns.
List<PinCluster> clusterPins(List<Incident> incidents, {required double zoom, double cellPixels = 64}) {
  if (zoom >= clusterMaxZoom) return [for (final incident in incidents) PinCluster([incident])];
  final worldPixels = 256 * math.pow(2, zoom.floor()).toDouble();
  final cells = <(int, int), List<Incident>>{};
  for (final incident in incidents) {
    final x = (incident.longitude + 180) / 360 * worldPixels;
    final sinLat = math.sin(incident.latitude * math.pi / 180).clamp(-0.9999, 0.9999);
    final y = (0.5 - math.log((1 + sinLat) / (1 - sinLat)) / (4 * math.pi)) * worldPixels;
    final key = ((x / cellPixels).floor(), (y / cellPixels).floor());
    (cells[key] ??= []).add(incident);
  }
  return [for (final members in cells.values) PinCluster(members)];
}
