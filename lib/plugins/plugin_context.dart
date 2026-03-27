import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Context object passed to plugins during initialization.
/// Gives plugins safe access to the app's state and map controller.
class PluginContext {
  final WidgetRef ref;
  final MapController? mapController;

  const PluginContext({
    required this.ref,
    this.mapController,
  });
}
