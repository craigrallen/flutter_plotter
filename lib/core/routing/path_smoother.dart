import 'dart:math';
import 'package:latlong2/latlong.dart';

/// Ramer-Douglas-Peucker algorithm to simplify a polyline.
/// [tolerance] is in degrees (~0.0001 degrees ≈ 10m).
List<LatLng> smoothPath(List<LatLng> points, {double tolerance = 0.0001}) {
  if (points.length <= 2) return List.of(points);

  // Find the point with the maximum distance from the line segment
  double maxDist = 0;
  int maxIndex = 0;

  final start = points.first;
  final end = points.last;

  for (var i = 1; i < points.length - 1; i++) {
    final d = _perpendicularDistance(points[i], start, end);
    if (d > maxDist) {
      maxDist = d;
      maxIndex = i;
    }
  }

  if (maxDist > tolerance) {
    final left = smoothPath(points.sublist(0, maxIndex + 1), tolerance: tolerance);
    final right = smoothPath(points.sublist(maxIndex), tolerance: tolerance);
    return [...left.sublist(0, left.length - 1), ...right];
  } else {
    return [start, end];
  }
}

double _perpendicularDistance(LatLng point, LatLng lineStart, LatLng lineEnd) {
  final dx = lineEnd.longitude - lineStart.longitude;
  final dy = lineEnd.latitude - lineStart.latitude;

  if (dx == 0 && dy == 0) {
    // lineStart == lineEnd
    final px = point.longitude - lineStart.longitude;
    final py = point.latitude - lineStart.latitude;
    return sqrt(px * px + py * py);
  }

  final t = ((point.longitude - lineStart.longitude) * dx +
          (point.latitude - lineStart.latitude) * dy) /
      (dx * dx + dy * dy);

  final clampedT = t.clamp(0.0, 1.0);
  final nearestLon = lineStart.longitude + clampedT * dx;
  final nearestLat = lineStart.latitude + clampedT * dy;

  final px = point.longitude - nearestLon;
  final py = point.latitude - nearestLat;
  return sqrt(px * px + py * py);
}
