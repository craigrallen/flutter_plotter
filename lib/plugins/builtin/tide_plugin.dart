import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../ui/chart/layers/tide_layer.dart';
import '../flutter_plotter_plugin.dart';

class TidePlugin extends FlutterPlotterPlugin {
  @override
  String get id => 'builtin.tide';
  @override
  String get name => 'Tide Stations';
  @override
  String get description => 'Shows nearby tide stations and predictions';
  @override
  String get version => '1.0.0';

  @override
  Widget? buildChartLayer(MapController mapController, WidgetRef ref) {
    return const TideLayer();
  }
}
