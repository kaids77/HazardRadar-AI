import 'package:latlong2/latlong.dart';

import '../../models/incident.dart';

/// Radius for the "High-risk hazard nearby" alert.
const double nearbyAlertMeters = 100;

/// A High-risk hazard close to the commuter, with its distance in meters.
class NearbyHazard {
  const NearbyHazard(this.incident, this.meters);

  final Incident incident;
  final double meters;
}

const Distance _distance = Distance();

/// The closest High-risk hazard within [radiusMeters] of [me] that is not in [warned].
///
/// [warned] holds ids already shown this session, so each hazard alerts at most once.
NearbyHazard? nearestUnwarnedHigh(
  LatLng me,
  Iterable<Incident> incidents,
  Set<String> warned, {
  double radiusMeters = nearbyAlertMeters,
}) {
  NearbyHazard? best;
  for (final incident in incidents) {
    if (incident.riskLevel != 'High' || warned.contains(incident.id)) continue;
    final meters = _distance(me, LatLng(incident.latitude, incident.longitude));
    if (meters <= radiusMeters && (best == null || meters < best.meters)) best = NearbyHazard(incident, meters);
  }
  return best;
}
