import 'dart:math' as math;
import 'package:latlong2/latlong.dart';

/// Shared geographic utility functions — use these instead of per-file implementations.

/// Haversine distance in nautical miles.
double haversineNm(double lat1, double lng1, double lat2, double lng2) {
  const R = 3440.065; // Earth radius in nm
  final dLat = (lat2 - lat1) * math.pi / 180;
  final dLng = (lng2 - lng1) * math.pi / 180;
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(lat1 * math.pi / 180) *
          math.cos(lat2 * math.pi / 180) *
          math.sin(dLng / 2) *
          math.sin(dLng / 2);
  return R * 2 * math.asin(math.sqrt(a));
}

/// Haversine distance between LatLng points in nautical miles.
double haversineLatLngNm(LatLng a, LatLng b) =>
    haversineNm(a.latitude, a.longitude, b.latitude, b.longitude);

/// Initial bearing (degrees) from point a to point b.
double bearingDeg(LatLng from, LatLng to) {
  final lat1 = from.latitude * math.pi / 180;
  final lat2 = to.latitude * math.pi / 180;
  final dLng = (to.longitude - from.longitude) * math.pi / 180;
  final y = math.sin(dLng) * math.cos(lat2);
  final x = math.cos(lat1) * math.sin(lat2) -
      math.sin(lat1) * math.cos(lat2) * math.cos(dLng);
  return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
}

/// Destination point given origin, bearing (degrees), distance (nm).
LatLng destinationPoint(LatLng origin, double bearingDeg, double distNm) {
  const R = 6371000.0;
  final d = distNm * 1852.0;
  final lat1 = origin.latitude * math.pi / 180;
  final lng1 = origin.longitude * math.pi / 180;
  final brng = bearingDeg * math.pi / 180;
  final lat2 = math.asin(math.sin(lat1) * math.cos(d / R) +
      math.cos(lat1) * math.sin(d / R) * math.cos(brng));
  final lng2 = lng1 +
      math.atan2(math.sin(brng) * math.sin(d / R) * math.cos(lat1),
          math.cos(d / R) - math.sin(lat1) * math.sin(lat2));
  return LatLng(lat2 * 180 / math.pi, lng2 * 180 / math.pi);
}

/// Wrap angle to 0-360.
double wrapDeg(double deg) => ((deg % 360) + 360) % 360;

/// Convert degrees to radians.
double toRad(double deg) => deg * math.pi / 180;

/// Convert radians to degrees.
double toDeg(double rad) => rad * 180 / math.pi;
