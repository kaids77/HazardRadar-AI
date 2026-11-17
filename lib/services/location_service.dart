import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

abstract interface class LocationProvider {
  /// The device position, or [fallbackCenter] when location is unavailable.
  /// Never throws, so the map always has a center to show.
  Future<LatLng> currentOrFallback();
}

class GeolocatorLocationService implements LocationProvider {
  /// Mandaue City, Cebu (approximate city center). Used when GPS is unavailable.
  static const LatLng fallbackCenter = LatLng(10.3236, 123.9322);

  @override
  Future<LatLng> currentOrFallback() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return fallbackCenter;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return fallbackCenter;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      return LatLng(position.latitude, position.longitude);
    } catch (_) {
      return fallbackCenter;
    }
  }
}
