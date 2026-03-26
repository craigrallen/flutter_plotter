import 'package:latlong2/latlong.dart';
import 'geo.dart';

/// Bearing from current position to next waypoint in degrees (0-360).
double bearingToWaypoint(LatLng current, LatLng waypoint) {
  return initialBearing(current, waypoint);
}

/// Distance from current position to next waypoint in nautical miles.
double distanceToWaypointNm(LatLng current, LatLng waypoint) {
  return haversineDistanceNm(current, waypoint);
}

/// ETA to next waypoint based on SOG.
/// Returns null if SOG is too low to compute meaningful ETA.
/// Returns Duration.
Duration? etaToWaypoint(LatLng current, LatLng waypoint, double sogKnots) {
  if (sogKnots < 0.1) return null;
  final distNm = distanceToWaypointNm(current, waypoint);
  final hours = distNm / sogKnots;
  return Duration(seconds: (hours * 3600).round());
}

/// Total route distance from a given leg index to the end, in nautical miles.
double remainingRouteDistanceNm(
  LatLng current,
  List<LatLng> waypoints,
  int nextWpIndex,
) {
  if (waypoints.isEmpty || nextWpIndex >= waypoints.length) return 0;

  var total = haversineDistanceNm(current, waypoints[nextWpIndex]);
  for (var i = nextWpIndex; i < waypoints.length - 1; i++) {
    total += haversineDistanceNm(waypoints[i], waypoints[i + 1]);
  }
  return total;
}
