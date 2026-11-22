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
    this.direct,
  });

  final List<LatLng> path;
  final int distanceMeters;
  final int durationSeconds;

  /// Closest the route comes to a High or Medium hazard, or null when none were nearby.
  final int? clearanceMeters;

  /// The shortest route, when it is a different route from this one. The map draws it
  /// red when it passes a hazard, next to this route in green.
  final DetourRoute? direct;

  static const int maxPoints = 5000;

  /// Must match SAFE_METERS in proxy/src/detour.js.
  static const int unsafeBelowMeters = 30;

  /// True when the route keeps at least [unsafeBelowMeters] from every High or Medium hazard.
  bool get isSafe => clearanceMeters == null || clearanceMeters! >= unsafeBelowMeters;

  /// True when this route is a meaningfully safer alternative to the direct route,
  /// even if it still passes within [unsafeBelowMeters] of a hazard.
  bool get isSaferThanDirect {
    final d = direct;
    if (d == null) return false;
    final mine = clearanceMeters;
    final theirs = d.clearanceMeters;
    if (mine == null) return true; // no hazards near this route
    if (theirs == null) return false; // no hazards near direct either
    return mine > theirs; // this route keeps farther from hazards
  }

  /// The shortest route, only when it passes closer to a hazard than this route.
  /// The map draws it red next to this route in green.
  DetourRoute? get riskyDirect {
    final d = direct;
    if (d == null) return null;
    if (!d.isSafe && (isSafe || isSaferThanDirect)) return d;
    return null;
  }

  /// Parses the proxy `/detour` response. Returns null for anything malformed or outside the Philippines.
  static DetourRoute? tryFromJson(Object? json) => _parse(json, withDirect: true);

  static DetourRoute? _parse(Object? json, {required bool withDirect}) {
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
      // A malformed extra route is dropped; the safe route still shows.
      direct: withDirect ? _parse(json['direct'], withDirect: false) : null,
    );
  }

  /// "1.3 km · 18 min walk · stays 140 m from High and Medium hazards". When the route
  /// still passes close to a hazard (no way around it was found), it says so plainly.
  /// When a safer alternative was found, it notes that the green route avoids the hazard.
  String get summary {
    final km = distanceMeters >= 1000 ? '${(distanceMeters / 1000).toStringAsFixed(1)} km' : '$distanceMeters m';
    final minutes = (durationSeconds / 60).ceil();
    final clearance = clearanceMeters;
    final hasAlternative = riskyDirect != null;
    final String away;
    if (clearance == null) {
      away = 'no High or Medium hazards nearby';
    } else if (clearance < unsafeBelowMeters) {
      if (hasAlternative) {
        final directDist = direct?.clearanceMeters;
        final directText = directDist != null ? 'within $directDist m of' : 'near';
        away = 'Warning: direct route passes $directText a High or Medium hazard. '
            'Green route keeps $clearance m away.';
      } else {
        away = 'Warning: passes within $clearance m of a High or Medium hazard. No safer route found.';
      }
    } else {
      if (hasAlternative) {
        away = 'stays $clearance m from High and Medium hazards (direct route passes closer)';
      } else {
        away = 'stays $clearance m from High and Medium hazards';
      }
    }
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

  /// The proxy may ask the router up to five times (direct, then four rounds of
  /// detours around a hazard), each with an 8 s limit, so the default 8 s is too short.
  static const Duration timeout = Duration(seconds: 45);

  final ProxyClient _proxy;

  @override
  Future<DetourRoute> route({required LatLng from, required LatLng to, required List<Incident> hazards}) async {
    final relevant = [for (final h in hazards) if (h.riskLevel == 'High' || h.riskLevel == 'Medium') h];
    // Nearest to the middle of the trip, so hazards near the destination are not crowded out.
    final middle = LatLng((from.latitude + to.latitude) / 2, (from.longitude + to.longitude) / 2);
    final nearest = nearestIncidents(relevant, middle, limit: maxHazards);
    final Object? json;
    try {
      json = await _proxy.postJson('detour', {
        'from': {'lat': from.latitude, 'lon': from.longitude},
        'to': {'lat': to.latitude, 'lon': to.longitude},
        'hazards': [
          for (final h in nearest) {'lat': h.latitude, 'lon': h.longitude, 'riskLevel': h.riskLevel},
        ],
      }, timeout: timeout);
    } on ProxyException catch (error) {
      throw DetourUnavailable(switch (error.reason) {
        'status 400' => 'Pick a destination within 10 km.',
        'status 429' => 'Too many route requests. Wait a minute and try again.',
        'timeout' => 'The route took too long to plan. Try a closer destination.',
        _ => 'The route service is not reachable. Avoid the red pins and stay on main roads.',
      });
    }
    final route = DetourRoute.tryFromJson(json);
    if (route == null) throw const DetourUnavailable('No walking route was found.');
    return route;
  }
}
