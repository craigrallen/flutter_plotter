import 'dart:math';
import 'package:latlong2/latlong.dart';

const double _earthRadiusM = 6371000.0;
const double _nm = 1852.0;

/// Haversine distance between two points in metres.
double haversineDistanceM(LatLng a, LatLng b) {
  final dLat = _deg2rad(b.latitude - a.latitude);
  final dLon = _deg2rad(b.longitude - a.longitude);
  final sinDLat = sin(dLat / 2);
  final sinDLon = sin(dLon / 2);
  final h = sinDLat * sinDLat +
      cos(_deg2rad(a.latitude)) * cos(_deg2rad(b.latitude)) * sinDLon * sinDLon;
  return 2 * _earthRadiusM * asin(sqrt(h));
}

/// Haversine distance in nautical miles.
double haversineDistanceNm(LatLng a, LatLng b) =>
    haversineDistanceM(a, b) / _nm;

/// Initial bearing from [a] to [b] in degrees (0-360).
double initialBearing(LatLng a, LatLng b) {
  final dLon = _deg2rad(b.longitude - a.longitude);
  final lat1 = _deg2rad(a.latitude);
  final lat2 = _deg2rad(b.latitude);
  final y = sin(dLon) * cos(lat2);
  final x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon);
  return (_rad2deg(atan2(y, x)) + 360) % 360;
}

/// Destination point given start, bearing (degrees) and distance (metres).
LatLng destinationPoint(LatLng start, double bearingDeg, double distanceM) {
  final d = distanceM / _earthRadiusM;
  final brng = _deg2rad(bearingDeg);
  final lat1 = _deg2rad(start.latitude);
  final lon1 = _deg2rad(start.longitude);
  final lat2 = asin(sin(lat1) * cos(d) + cos(lat1) * sin(d) * cos(brng));
  final lon2 =
      lon1 + atan2(sin(brng) * sin(d) * cos(lat1), cos(d) - sin(lat1) * sin(lat2));
  return LatLng(_rad2deg(lat2), _rad2deg(lon2));
}

double _deg2rad(double deg) => deg * pi / 180;
double _rad2deg(double rad) => rad * 180 / pi;
