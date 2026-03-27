import 'package:latlong2/latlong.dart';
import '../../data/models/auto_route.dart';
import '../../data/models/vessel_profile.dart';
import 'route_options.dart';

abstract class RouteEngine {
  String get id;
  String get name;
  String get description;

  Future<AutoRoute?> calculateRoute(
    LatLng start,
    LatLng end,
    VesselProfile vessel,
    RouteOptions options, {
    void Function(double progress)? onProgress,
  });
}
