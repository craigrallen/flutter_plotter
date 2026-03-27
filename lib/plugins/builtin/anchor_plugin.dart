import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../ui/chart/layers/anchor_layer.dart';
import '../flutter_plotter_plugin.dart';

class AnchorPlugin extends FlutterPlotterPlugin {
  @override
  String get id => 'builtin.anchor';
  @override
  String get name => 'Anchor Watch';
  @override
  String get description => 'Anchor watch circle and drag alarm';
  @override
  String get version => '1.0.0';

  @override
  Widget? buildChartLayer(MapController mapController, WidgetRef ref) {
    return const AnchorLayer();
  }
}
