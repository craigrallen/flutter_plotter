import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../ui/chart/layers/route_layer.dart';
import '../flutter_plotter_plugin.dart';

class RoutePlugin extends FlutterPlotterPlugin {
  double _mapRotation = 0;

  @override
  String get id => 'builtin.route';
  @override
  String get name => 'Routes & Waypoints';
  @override
  String get description => 'Displays routes and waypoints on the chart';
  @override
  String get version => '1.0.0';

  void setMapRotation(double rotation) => _mapRotation = rotation;

  @override
  Widget? buildChartLayer(MapController mapController, WidgetRef ref) {
    return RepaintBoundary(child: RouteLayer(mapRotation: _mapRotation));
  }
}
