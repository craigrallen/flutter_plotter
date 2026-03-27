import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:latlong2/latlong.dart';
import '../../../data/models/auto_route.dart';
import '../../../data/models/vessel_profile.dart';
import '../route_engine.dart';
import '../route_options.dart';
import '../astar.dart';
import '../path_smoother.dart';
import '../../nav/geo.dart';

class OpenSeaEngine extends RouteEngine {
  @override
  String get id => 'opensea';

  @override
  String get name => 'OpenSeaMap Depth';

  @override
  String get description =>
      'Crowd-sourced depth data from OpenSeaMap. Best for coastal areas with '
      'good coverage.';

  static const _tileUrl = 'https://tiles.openseamap.org/depth';
  static const _zoom = 14;
  static const _tileSize = 256;

  @override
  Future<AutoRoute?> calculateRoute(
    LatLng start,
    LatLng end,
    VesselProfile vessel,
    RouteOptions options, {
    void Function(double progress)? onProgress,
  }) async {
    onProgress?.call(0.0);

    // 1. Compute bounding box with margin
    final minLat = min(start.latitude, end.latitude) - 0.01;
    final maxLat = max(start.latitude, end.latitude) + 0.01;
    final minLon = min(start.longitude, end.longitude) - 0.01;
    final maxLon = max(start.longitude, end.longitude) + 0.01;

    // 2. Determine tile range at zoom 14
    final (minTileX, minTileY) = _latLngToTile(maxLat, minLon, _zoom);
    final (maxTileX, maxTileY) = _latLngToTile(minLat, maxLon, _zoom);

    final tilesX = maxTileX - minTileX + 1;
    final tilesY = maxTileY - minTileY + 1;

    if (tilesX * tilesY > 100) {
      return AutoRoute(
        waypoints: [start, end],
        distanceNm: haversineDistanceNm(start, end),
        warnings: [
          'Route too long for depth grid routing (${tilesX * tilesY} tiles). '
              'Using direct line.',
          _crowdSourceWarning,
        ],
        engineUsed: id,
        calculatedAt: DateTime.now(),
      );
    }

    onProgress?.call(0.1);

    // 3. Download tiles and build depth grid
    final gridWidth = tilesX * _tileSize;
    final gridHeight = tilesY * _tileSize;
    final depthData = List.generate(
      gridHeight,
      (_) => List.filled(gridWidth, const GridCell(null)),
    );

    int tilesLoaded = 0;
    final totalTiles = tilesX * tilesY;

    for (var ty = minTileY; ty <= maxTileY; ty++) {
      for (var tx = minTileX; tx <= maxTileX; tx++) {
        final tileDepths = await _fetchTileDepths(tx, ty, _zoom);
        final offsetX = (tx - minTileX) * _tileSize;
        final offsetY = (ty - minTileY) * _tileSize;

        if (tileDepths != null) {
          for (var py = 0; py < _tileSize; py++) {
            for (var px = 0; px < _tileSize; px++) {
              depthData[offsetY + py][offsetX + px] = tileDepths[py][px];
            }
          }
        }

        tilesLoaded++;
        onProgress?.call(0.1 + 0.5 * tilesLoaded / totalTiles);
      }
    }

    // 4. Compute grid geo-parameters
    final topLeft = _tileToLatLng(minTileX, minTileY, _zoom);
    final bottomRight = _tileToLatLng(maxTileX + 1, maxTileY + 1, _zoom);

    final latStep = (bottomRight.latitude - topLeft.latitude) / gridHeight;
    final lonStep = (bottomRight.longitude - topLeft.longitude) / gridWidth;

    final grid = DepthGrid(
      cells: depthData,
      origin: topLeft,
      latStep: latStep,
      lonStep: lonStep,
    );

    onProgress?.call(0.6);

    // 5. Run A*
    final path = astarSearch(
      grid,
      start,
      end,
      vessel,
      safetyMargin: options.safetyMargin,
      preferDeepWater: options.preferDeepWater,
      onProgress: (p) => onProgress?.call(0.6 + 0.3 * p),
    );

    if (path == null || path.length < 2) {
      // Fallback: direct line
      return AutoRoute(
        waypoints: [start, end],
        distanceNm: haversineDistanceNm(start, end),
        warnings: [
          'No safe route found through depth data. Using direct line.',
          _crowdSourceWarning,
        ],
        engineUsed: id,
        calculatedAt: DateTime.now(),
      );
    }

    // 6. Smooth path
    final smoothed = smoothPath(path);

    onProgress?.call(0.95);

    // 7. Calculate distance and depth margins
    double totalDist = 0;
    final margins = <double>[];
    for (var i = 0; i < smoothed.length; i++) {
      if (i > 0) {
        totalDist += haversineDistanceNm(smoothed[i - 1], smoothed[i]);
      }
      // Look up depth at each waypoint
      final (r, c) = grid.latLngToCell(smoothed[i]);
      final cell = grid.cellAt(r, c);
      final depth = cell?.depth ?? 0.0;
      margins.add(depth - vessel.draft);
    }

    onProgress?.call(1.0);

    return AutoRoute(
      waypoints: smoothed,
      distanceNm: totalDist,
      warnings: [_crowdSourceWarning],
      engineUsed: id,
      calculatedAt: DateTime.now(),
      depthMargins: margins,
    );
  }

  static const _crowdSourceWarning =
      'Based on crowd-sourced OpenSeaMap depth data. '
      'Not suitable for safety-critical navigation.';

  /// Fetch a depth tile and decode pixel depths.
  Future<List<List<GridCell>>?> _fetchTileDepths(
      int x, int y, int z) async {
    try {
      final url = '$_tileUrl/$z/$x/$y.png';
      final response = await http.get(Uri.parse(url)).timeout(
            const Duration(seconds: 10),
          );

      if (response.statusCode != 200) return null;

      final image = img.decodePng(response.bodyBytes);
      if (image == null) return null;

      final grid = List.generate(_tileSize, (py) {
        return List.generate(_tileSize, (px) {
          final pixel = image.getPixel(px, py);
          final r = pixel.r.toInt();
          final g = pixel.g.toInt();
          final b = pixel.b.toInt();
          final a = pixel.a.toInt();

          // Transparent or white = no data (land or unknown)
          if (a < 128 || (r > 250 && g > 250 && b > 250)) {
            return const GridCell(null);
          }

          final depth = _decodeDepth(r);
          return GridCell(depth);
        });
      });

      return grid;
    } catch (_) {
      return null;
    }
  }

  /// Decode depth from red channel value.
  /// Empirical mapping from OpenSeaMap depth tile encoding.
  static double _decodeDepth(int red) {
    if (red >= 200) {
      // 200-255 maps to 0-10m
      return (255 - red) / 55.0 * 10.0;
    } else if (red >= 100) {
      // 100-199 maps to 10-30m
      return 10.0 + (199 - red) / 99.0 * 20.0;
    } else {
      // 0-99 maps to 30-100m
      return 30.0 + (99 - red) / 99.0 * 70.0;
    }
  }

  /// Convert lat/lng to TMS tile coordinates.
  static (int, int) _latLngToTile(double lat, double lon, int zoom) {
    final n = pow(2, zoom).toDouble();
    final x = ((lon + 180) / 360 * n).floor();
    final latRad = lat * pi / 180;
    final y = ((1 - log(tan(latRad) + 1 / cos(latRad)) / pi) / 2 * n).floor();
    return (x, y);
  }

  /// Convert TMS tile coordinates back to lat/lng (top-left corner of tile).
  static LatLng _tileToLatLng(int x, int y, int zoom) {
    final n = pow(2, zoom).toDouble();
    final lon = x / n * 360 - 180;
    final latRad = atan(sinh(pi * (1 - 2 * y / n)));
    final lat = latRad * 180 / pi;
    return LatLng(lat, lon);
  }

  static double sinh(double x) => (exp(x) - exp(-x)) / 2;
}
