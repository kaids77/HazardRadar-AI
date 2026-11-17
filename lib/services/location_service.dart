import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

abstract interface class LocationProvider {
  /// The device position, or [fallbackCenter] when location is unavailable.
  /// Never throws, so the map always has a center to show.
  Future<LatLng> currentOrFallback();
}

class GeolocatorLocationService implements LocationProvider {
  /// Near the University of Santo Tomas, Manila, the project's demo corridor.
  static const LatLng fallbackCenter = LatLng(14.6091, 120.9890);

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
