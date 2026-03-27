import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/models/ais_target.dart';
import '../data/models/vessel_state.dart';
import 'flutter_plotter_plugin.dart';
import 'plugin_context.dart';

/// Central registry for all plugins.
class PluginRegistry {
  final List<FlutterPlotterPlugin> _plugins = [];

  List<FlutterPlotterPlugin> get plugins => List.unmodifiable(_plugins);

  /// Register and initialise a plugin.
  Future<void> register(FlutterPlotterPlugin plugin, PluginContext context) async {
    if (_plugins.any((p) => p.id == plugin.id)) return;
    await plugin.onInit(context);
    _plugins.add(plugin);
  }

  /// Unregister and dispose a plugin by ID.
  Future<void> unregister(String pluginId) async {
    final idx = _plugins.indexWhere((p) => p.id == pluginId);
    if (idx == -1) return;
    await _plugins[idx].onDispose();
    _plugins.removeAt(idx);
  }

  /// Collect chart layer widgets from all plugins.
  List<Widget> getChartLayers(MapController mapController, WidgetRef ref) {
    final layers = <Widget>[];
    for (final plugin in _plugins) {
      final layer = plugin.buildChartLayer(mapController, ref);
      if (layer != null) layers.add(layer);
    }
    return layers;
  }

  /// Collect instrument tiles from all plugins.
  List<Widget> getInstrumentTiles(WidgetRef ref) {
    final tiles = <Widget>[];
    for (final plugin in _plugins) {
      final tile = plugin.buildInstrumentTile(ref);
      if (tile != null) tiles.add(tile);
    }
    return tiles;
  }

  /// Broadcast vessel state update to all plugins.
  void broadcastVesselState(VesselState state) {
    for (final plugin in _plugins) {
      plugin.onVesselStateUpdate(state);
    }
  }

  /// Broadcast Signal K delta to all plugins.
  void broadcastSignalKDelta(dynamic delta) {
    for (final plugin in _plugins) {
      plugin.onSignalKDelta(delta);
    }
  }

  /// Broadcast AIS target update to all plugins.
  void broadcastAisTarget(AisTarget target) {
    for (final plugin in _plugins) {
      plugin.onAisTargetUpdate(target);
    }
  }

  /// Dispose all plugins.
  Future<void> disposeAll() async {
    for (final plugin in _plugins) {
      await plugin.onDispose();
    }
    _plugins.clear();
  }
}

/// Global plugin registry provider.
final pluginRegistryProvider = Provider<PluginRegistry>((ref) {
  final registry = PluginRegistry();
  ref.onDispose(() => registry.disposeAll());
  return registry;
});
