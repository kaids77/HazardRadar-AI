const String _alphabet = '0123456789bcdefghjkmnpqrstuvwxyz';

/// Encodes a coordinate as a geohash of [precision] characters (1 to 12).
/// Six characters is a cell of about 1.2 km by 0.6 km, enough to group nearby reports.
String encodeGeohash(double latitude, double longitude, {int precision = 6}) {
  if (precision < 1 || precision > 12) {
    throw RangeError.range(precision, 1, 12, 'precision');
  }
  if (latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180) {
    throw ArgumentError('Coordinate is out of range: $latitude, $longitude');
  }

  var latMin = -90.0, latMax = 90.0;
  var lonMin = -180.0, lonMax = 180.0;
  final out = StringBuffer();
  var evenBit = true;
  var bit = 0;
  var index = 0;

  while (out.length < precision) {
    if (evenBit) {
      final mid = (lonMin + lonMax) / 2;
      if (longitude >= mid) {
        index = (index << 1) | 1;
        lonMin = mid;
      } else {
        index <<= 1;
        lonMax = mid;
      }
    } else {
      final mid = (latMin + latMax) / 2;
      if (latitude >= mid) {
        index = (index << 1) | 1;
        latMin = mid;
      } else {
        index <<= 1;
        latMax = mid;
      }
    }
    evenBit = !evenBit;
    if (++bit == 5) {
      out.write(_alphabet[index]);
      bit = 0;
      index = 0;
    }
  }
  return out.toString();
}
