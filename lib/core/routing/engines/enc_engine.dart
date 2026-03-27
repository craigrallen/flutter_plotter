import 'package:latlong2/latlong.dart';
import '../../../data/models/auto_route.dart';
import '../../../data/models/vessel_profile.dart';
import '../route_engine.dart';
import '../route_options.dart';

class EncEngine extends RouteEngine {
  @override
  String get id => 'enc';

  @override
  String get name => 'ENC Charts (oeSENC)';

  @override
  String get description =>
      'Official chart depth data. Requires oeSENC charts.';

  @override
  Future<AutoRoute?> calculateRoute(
    LatLng start,
    LatLng end,
    VesselProfile vessel,
    RouteOptions options, {
    void Function(double progress)? onProgress,
  }) async {
    throw UnimplementedError(
        'ENC routing requires oeSENC integration (Phase 10)');
  }
}
