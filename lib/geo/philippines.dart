import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// Approximate bounding box of the Philippines. The map cannot pan outside it,
/// and reports cannot be filed from outside it.
final LatLngBounds philippinesBounds = LatLngBounds(
  const LatLng(4.5, 116.7),
  const LatLng(21.3, 127.0),
);
