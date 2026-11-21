import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:hazardradarai/geo/geohash.dart';
import 'package:hazardradarai/geo/philippines.dart';
import 'package:hazardradarai/services/location_service.dart';

void main() {
  test('encodes known reference points', () {
    // Reference values from the geohash specification and Wikipedia.
    expect(encodeGeohash(57.64911, 10.40744, precision: 11), 'u4pruydqqvj');
    expect(encodeGeohash(42.6, -5.6, precision: 5), 'ezs42');
  });

  test('defaults to six characters', () {
    expect(encodeGeohash(10.3236, 123.9322), hasLength(6));
  });

  test('rejects bad input', () {
    expect(() => encodeGeohash(91, 0), throwsArgumentError);
    expect(() => encodeGeohash(0, 181), throwsArgumentError);
    expect(() => encodeGeohash(0, 0, precision: 0), throwsRangeError);
    expect(() => encodeGeohash(0, 0, precision: 13), throwsRangeError);
  });

  test('Philippines bounds contain Cebu and exclude Singapore and Tokyo', () {
    expect(philippinesBounds.contains(GeolocatorLocationService.fallbackCenter), isTrue);
    expect(philippinesBounds.contains(const LatLng(1.35, 103.82)), isFalse);
    expect(philippinesBounds.contains(const LatLng(35.68, 139.69)), isFalse);
  });
}
