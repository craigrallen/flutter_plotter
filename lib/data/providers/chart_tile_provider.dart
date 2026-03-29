import 'package:flutter_map/flutter_map.dart';

/// Abstract chart tile provider — allows swapping tile sources.
abstract class ChartTileProvider {
  String get name;
  TileLayer get tileLayer;
}

/// OpenStreetMap base layer.
class OsmBaseProvider implements ChartTileProvider {
  @override
  String get name => 'OpenStreetMap';

  @override
  TileLayer get tileLayer => TileLayer(
        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
        userAgentPackageName: 'com.craigrallen.flutter_plotter',
        maxZoom: 19,
      );
}

/// CartoDB Dark Matter — night mode base layer.
class CartoDbDarkProvider implements ChartTileProvider {
  @override
  String get name => 'CartoDB Dark';

  @override
  TileLayer get tileLayer => TileLayer(
        urlTemplate:
            'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png',
        subdomains: const ['a', 'b', 'c', 'd'],
        userAgentPackageName: 'com.craigrallen.flutter_plotter',
        maxZoom: 19,
      );
}

/// OpenSeaMap nautical overlay.
class OpenSeaMapProvider implements ChartTileProvider {
  @override
  String get name => 'OpenSeaMap';

  @override
  TileLayer get tileLayer => TileLayer(
        urlTemplate: 'https://tiles.openseamap.org/seamark/{z}/{x}/{y}.png',
        userAgentPackageName: 'com.craigrallen.flutter_plotter',
        maxZoom: 18,
        // OpenSeaMap tiles are transparent overlays — no background needed.
      );
}
