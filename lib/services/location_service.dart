import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

/// A GPS reading with its accuracy radius in meters (null when unknown).
class LocationFix {
  const LocationFix(this.position, {this.accuracyMeters});

  final LatLng position;
  final double? accuracyMeters;
}

abstract interface class LocationProvider {
  /// The device position, or [GeolocatorLocationService.fallbackCenter] when location
  /// is unavailable. Never throws, so the map always has a center to show.
  Future<LatLng> currentOrFallback();

  /// The device position, or null when it cannot be read. Reports use this,
  /// because filing a hazard at the fallback center would put it in the wrong place.
  Future<LatLng?> current();

  /// Like [current], with the accuracy radius. Used by the report wizard.
  Future<LocationFix?> currentFix();

  /// Position updates while the commuter moves. Empty when location is unavailable.
  /// Never emits errors. Used by the map for the nearby-hazard alert.
  Stream<LocationFix> watchFix();
}

class GeolocatorLocationService implements LocationProvider {
  /// Mandaue City, Cebu (approximate city center). Used when GPS is unavailable.
  static const LatLng fallbackCenter = LatLng(10.3236, 123.9322);

  static const Duration _fixTimeout = Duration(seconds: 5);

  /// Latest reading from [currentFix] or [watchFix], used on Web when a second
  /// concurrent `getCurrentPosition` call times out while the stream is active.
  LocationFix? _lastFix;

  @override
  Future<LatLng> currentOrFallback() async => await current() ?? fallbackCenter;

  @override
  Future<LatLng?> current() async => (await currentFix())?.position;

  @override
  Future<LocationFix?> currentFix() async {
    try {
      if (!await _permitted()) return null;
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: _fixTimeout,
        ),
      );
      final fix = _toFix(position);
      _lastFix = fix;
      return fix;
    } catch (_) {
      return _lastFix;
    }
  }

  @override
  Stream<LocationFix> watchFix() async* {
    try {
      if (!await _permitted()) return;
    } catch (_) {
      return;
    }
    // Only report moves of 15 m or more, so a phone sitting still does not wake the map.
    yield* Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 15),
    ).map((position) {
      final fix = _toFix(position);
      _lastFix = fix;
      return fix;
    }).handleError((Object _) {});
  }

  static Future<bool> _permitted() async {
    if (!await Geolocator.isLocationServiceEnabled()) return false;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return permission != LocationPermission.denied && permission != LocationPermission.deniedForever;
  }

  static LocationFix _toFix(Position position) => LocationFix(
        LatLng(position.latitude, position.longitude),
        accuracyMeters: position.accuracy > 0 ? position.accuracy : null,
      );
}
