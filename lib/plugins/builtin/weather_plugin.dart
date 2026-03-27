import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../ui/chart/layers/weather_layer.dart';
import '../flutter_plotter_plugin.dart';

class WeatherPlugin extends FlutterPlotterPlugin {
  @override
  String get id => 'builtin.weather';
  @override
  String get name => 'Weather Overlay';
  @override
  String get description => 'Wind barbs and wave height overlay on the chart';
  @override
  String get version => '1.0.0';

  @override
  Widget? buildChartLayer(MapController mapController, WidgetRef ref) {
    return const WeatherLayer();
  }
}
