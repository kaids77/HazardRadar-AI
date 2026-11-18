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
}

class GeolocatorLocationService implements LocationProvider {
  /// Mandaue City, Cebu (approximate city center). Used when GPS is unavailable.
  static const LatLng fallbackCenter = LatLng(10.3236, 123.9322);

  @override
  Future<LatLng> currentOrFallback() async => await current() ?? fallbackCenter;

  @override
  Future<LatLng?> current() async => (await currentFix())?.position;

  @override
  Future<LocationFix?> currentFix() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      return LocationFix(
        LatLng(position.latitude, position.longitude),
        accuracyMeters: position.accuracy > 0 ? position.accuracy : null,
      );
    } catch (_) {
      return null;
    }
  }
}
