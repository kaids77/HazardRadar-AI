import 'package:latlong2/latlong.dart';

import '../geo/philippines.dart';
import '../models/incident.dart';
import 'chat_service.dart';
import 'proxy_client.dart';

/// A walking route that keeps away from High and Medium hazards.
class DetourRoute {
  const DetourRoute({
    required this.path,
    required this.distanceMeters,
    required this.durationSeconds,
    this.clearanceMeters,
  });

  final List<LatLng> path;
  final int distanceMeters;
  final int durationSeconds;

  /// Closest the route comes to a High or Medium hazard, or null when none were nearby.
  final int? clearanceMeters;

  static const int maxPoints = 5000;

  /// Parses the proxy `/detour` response. Returns null for anything malformed or outside the Philippines.
  static DetourRoute? tryFromJson(Object? json) {
    if (json is! Map) return null;
    final raw = json['path'];
    final distance = json['distanceMeters'];
    final duration = json['durationSeconds'];
    final clearance = json['clearanceMeters'];
    if (raw is! List || raw.length < 2 || raw.length > maxPoints || distance is! num || duration is! num) return null;
    final path = <LatLng>[];
    for (final p in raw) {
      if (p is! List || p.length != 2 || p[0] is! num || p[1] is! num) return null;
      final point = LatLng((p[0] as num).toDouble(), (p[1] as num).toDouble());
      if (!philippinesBounds.contains(point)) return null;
      path.add(point);
    }
    return DetourRoute(
      path: path,
      distanceMeters: distance.round(),
      durationSeconds: duration.round(),
      clearanceMeters: clearance is num ? clearance.round() : null,
    );
  }

  /// "1.3 km · 18 min walk · stays 140 m from High and Medium hazards".
  String get summary {
    final km = distanceMeters >= 1000 ? '${(distanceMeters / 1000).toStringAsFixed(1)} km' : '$distanceMeters m';
    final minutes = (durationSeconds / 60).ceil();
    final away = clearanceMeters == null
        ? 'no High or Medium hazards nearby'
        : 'stays $clearanceMeters m from High and Medium hazards';
    return '$km · $minutes min walk · $away';
  }
}

class DetourUnavailable implements Exception {
  const DetourUnavailable(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract interface class DetourService {
  /// Throws [DetourUnavailable] with a user-facing message on failure.
  Future<DetourRoute> route({required LatLng from, required LatLng to, required List<Incident> hazards});
}

class ProxyDetourService implements DetourService {
  const ProxyDetourService(this._proxy);

  /// Must match MAX_HAZARDS in proxy/src/detour.js.
  static const int maxHazards = 50;

  final ProxyClient _proxy;

  @override
  Future<DetourRoute> route({required LatLng from, required LatLng to, required List<Incident> hazards}) async {
    final relevant = [for (final h in hazards) if (h.riskLevel == 'High' || h.riskLevel == 'Medium') h];
    final nearest = nearestIncidents(relevant, from, limit: maxHazards);
    final Object? json;
    try {
      json = await _proxy.postJson('detour', {
        'from': {'lat': from.latitude, 'lon': from.longitude},
        'to': {'lat': to.latitude, 'lon': to.longitude},
        'hazards': [
          for (final h in nearest) {'lat': h.latitude, 'lon': h.longitude, 'riskLevel': h.riskLevel},
        ],
      });
    } on ProxyException catch (error) {
      throw DetourUnavailable(
        error.reason == 'status 400'
            ? 'Pick a destination within 10 km.'
            : 'The route service is not reachable. Avoid the red pins and stay on main roads.',
      );
    }
    final route = DetourRoute.tryFromJson(json);
    if (route == null) throw const DetourUnavailable('No walking route was found.');
    return route;
  }
}
