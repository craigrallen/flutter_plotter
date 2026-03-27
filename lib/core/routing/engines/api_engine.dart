import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import '../../../data/models/auto_route.dart';
import '../../../data/models/vessel_profile.dart';
import '../../../data/providers/routing_api_provider.dart';
import '../route_engine.dart';
import '../route_options.dart';
import '../../nav/geo.dart';

class ApiEngine extends RouteEngine {
  final RoutingApiConfig _config;

  ApiEngine(this._config);

  @override
  String get id => 'api';

  @override
  String get name => 'Remote API';

  @override
  String get description => _config.useNavionics && _config.navionicsApiKey.isNotEmpty
      ? 'Navionics routing API with draft-aware pathfinding.'
      : 'OpenRouteService driving-boat profile.';

  @override
  Future<AutoRoute?> calculateRoute(
    LatLng start,
    LatLng end,
    VesselProfile vessel,
    RouteOptions options, {
    void Function(double progress)? onProgress,
  }) async {
    onProgress?.call(0.1);

    if (_config.useNavionics && _config.navionicsApiKey.isNotEmpty) {
      return _navionicsRoute(start, end, vessel, options, onProgress);
    }

    if (_config.orsApiKey.isNotEmpty) {
      return _orsRoute(start, end, vessel, options, onProgress);
    }

    return null; // no API key configured
  }

  Future<AutoRoute?> _orsRoute(
    LatLng start,
    LatLng end,
    VesselProfile vessel,
    RouteOptions options,
    void Function(double progress)? onProgress,
  ) async {
    try {
      final url = Uri.parse(
        'https://api.openrouteservice.org/v2/directions/driving-car'
        '?api_key=${_config.orsApiKey}'
        '&start=${start.longitude},${start.latitude}'
        '&end=${end.longitude},${end.latitude}',
      );

      onProgress?.call(0.3);

      final response = await http.get(url).timeout(
            const Duration(seconds: 30),
          );

      onProgress?.call(0.7);

      if (response.statusCode != 200) {
        return AutoRoute(
          waypoints: [start, end],
          distanceNm: haversineDistanceNm(start, end),
          warnings: [
            'API error (${response.statusCode}). Using direct line.',
          ],
          engineUsed: id,
          calculatedAt: DateTime.now(),
        );
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final features = json['features'] as List;
      if (features.isEmpty) {
        return AutoRoute(
          waypoints: [start, end],
          distanceNm: haversineDistanceNm(start, end),
          warnings: ['No route returned by API. Using direct line.'],
          engineUsed: id,
          calculatedAt: DateTime.now(),
        );
      }

      final geometry = features[0]['geometry'] as Map<String, dynamic>;
      final coords = geometry['coordinates'] as List;

      final waypoints = coords.map<LatLng>((c) {
        final coord = c as List;
        return LatLng(
          (coord[1] as num).toDouble(),
          (coord[0] as num).toDouble(),
        );
      }).toList();

      // Calculate total distance
      double totalDist = 0;
      for (var i = 1; i < waypoints.length; i++) {
        totalDist += haversineDistanceNm(waypoints[i - 1], waypoints[i]);
      }

      onProgress?.call(1.0);

      return AutoRoute(
        waypoints: waypoints,
        distanceNm: totalDist,
        warnings: [
          'OpenRouteService driving-car profile. '
              'Does not account for vessel draft or maritime hazards.',
        ],
        engineUsed: id,
        calculatedAt: DateTime.now(),
      );
    } catch (e) {
      return AutoRoute(
        waypoints: [start, end],
        distanceNm: haversineDistanceNm(start, end),
        warnings: ['API request failed: $e. Using direct line.'],
        engineUsed: id,
        calculatedAt: DateTime.now(),
      );
    }
  }

  /// Navionics routing — placeholder implementation.
  Future<AutoRoute?> _navionicsRoute(
    LatLng start,
    LatLng end,
    VesselProfile vessel,
    RouteOptions options,
    void Function(double progress)? onProgress,
  ) async {
    try {
      // Navionics API spec TBD — placeholder request structure
      final url = Uri.parse('https://api.navionics.com/v1/route');

      final body = jsonEncode({
        'start': {'lat': start.latitude, 'lon': start.longitude},
        'end': {'lat': end.latitude, 'lon': end.longitude},
        'draft': vessel.draft,
        'airDraft': vessel.airDraft,
        'beam': vessel.beam,
        'safetyMargin': options.safetyMargin,
      });

      onProgress?.call(0.3);

      final response = await http
          .post(
            url,
            headers: {
              'Authorization': 'Bearer ${_config.navionicsApiKey}',
              'Content-Type': 'application/json',
            },
            body: body,
          )
          .timeout(const Duration(seconds: 30));

      onProgress?.call(0.7);

      if (response.statusCode != 200) {
        return AutoRoute(
          waypoints: [start, end],
          distanceNm: haversineDistanceNm(start, end),
          warnings: [
            'Navionics API error (${response.statusCode}). Using direct line.',
          ],
          engineUsed: id,
          calculatedAt: DateTime.now(),
        );
      }

      // Parse response — placeholder structure
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final coords = json['waypoints'] as List;

      final waypoints = coords.map<LatLng>((c) {
        final coord = c as Map<String, dynamic>;
        return LatLng(
          (coord['lat'] as num).toDouble(),
          (coord['lon'] as num).toDouble(),
        );
      }).toList();

      double totalDist = 0;
      for (var i = 1; i < waypoints.length; i++) {
        totalDist += haversineDistanceNm(waypoints[i - 1], waypoints[i]);
      }

      onProgress?.call(1.0);

      return AutoRoute(
        waypoints: waypoints,
        distanceNm: totalDist,
        warnings: ['Navionics routing with draft-aware pathfinding.'],
        engineUsed: id,
        calculatedAt: DateTime.now(),
        depthMargins: json['depthMargins'] != null
            ? (json['depthMargins'] as List)
                .map<double>((d) => (d as num).toDouble())
                .toList()
            : [],
      );
    } catch (e) {
      return AutoRoute(
        waypoints: [start, end],
        distanceNm: haversineDistanceNm(start, end),
        warnings: ['Navionics API request failed: $e. Using direct line.'],
        engineUsed: id,
        calculatedAt: DateTime.now(),
      );
    }
  }
}
