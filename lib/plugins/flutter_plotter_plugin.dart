import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/models/ais_target.dart';
import '../data/models/vessel_state.dart';
import 'plugin_context.dart';

/// Abstract base class for FlutterPlotter plugins.
///
/// Plugins can provide chart layers, instrument tiles, and react to
/// vessel state / AIS / Signal K updates.
abstract class FlutterPlotterPlugin {
  /// Unique plugin identifier.
  String get id;

  /// Human-readable name.
  String get name;

  /// Short description of what this plugin does.
  String get description;

  /// Semantic version string.
  String get version;

  /// Called when the plugin is registered. Use to set up state.
  Future<void> onInit(PluginContext context) async {}

  /// Called when the plugin is unregistered. Use to clean up.
  Future<void> onDispose() async {}

  /// Return a widget to render as a chart layer, or null.
  Widget? buildChartLayer(MapController mapController, WidgetRef ref) => null;

  /// Return a widget to render as an instrument tile, or null.
  Widget? buildInstrumentTile(WidgetRef ref) => null;

  /// Called on each vessel state update.
  void onVesselStateUpdate(VesselState state) {}

  /// Called on each Signal K delta message.
  void onSignalKDelta(dynamic delta) {}

  /// Called when an AIS target is updated.
  void onAisTargetUpdate(AisTarget target) {}
}
