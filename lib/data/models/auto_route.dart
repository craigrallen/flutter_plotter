import 'package:latlong2/latlong.dart';

class AutoRoute {
  final List<LatLng> waypoints;
  final double distanceNm;
  final List<String> warnings;
  final String engineUsed;
  final DateTime calculatedAt;
  final List<double> depthMargins;

  const AutoRoute({
    required this.waypoints,
    required this.distanceNm,
    this.warnings = const [],
    required this.engineUsed,
    required this.calculatedAt,
    this.depthMargins = const [],
  });
}
