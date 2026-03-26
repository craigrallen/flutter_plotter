import 'dart:math';
import 'package:latlong2/latlong.dart';
import 'geo.dart';

/// Cross-track error: perpendicular distance from current position
/// to the great-circle path between two waypoints.
/// Returns distance in nautical miles. Positive = right of track,
/// negative = left of track.
double crossTrackErrorNm(LatLng from, LatLng to, LatLng current) {
  final distFromNm = haversineDistanceNm(from, current);
  final bearingFromToCurrent = initialBearing(from, current) * pi / 180;
  final bearingFromToNext = initialBearing(from, to) * pi / 180;

  // Angular distance from 'from' to 'current' in radians on unit sphere
  final angularDist = distFromNm * 1852 / 6371000.0;

  // XTE = asin(sin(d) * sin(bearing_diff))
  final xte = asin(sin(angularDist) * sin(bearingFromToCurrent - bearingFromToNext));

  // Convert radians to nautical miles
  return xte * 6371000.0 / 1852;
}

/// Absolute cross-track error in nautical miles.
double crossTrackErrorAbsNm(LatLng from, LatLng to, LatLng current) {
  return crossTrackErrorNm(from, to, current).abs();
}
