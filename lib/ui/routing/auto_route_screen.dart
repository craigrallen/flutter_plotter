import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../../core/routing/route_options.dart';
import '../../data/models/auto_route.dart';
import '../../data/models/route_model.dart';
import '../../data/models/waypoint.dart';
import '../../data/providers/route_engine_provider.dart';
import '../../data/providers/route_provider.dart';
import '../../data/providers/routing_api_provider.dart';
import '../../data/providers/vessel_profile_provider.dart';
import '../../data/providers/vessel_provider.dart';
import '../settings/vessel_profile_editor.dart';

/// Provider to hold the current auto-route preview (null when not previewing).
final autoRoutePreviewProvider = StateProvider<AutoRoute?>((ref) => null);

class AutoRouteScreen extends ConsumerStatefulWidget {
  final LatLng? destination;

  const AutoRouteScreen({super.key, this.destination});

  @override
  ConsumerState<AutoRouteScreen> createState() => _AutoRouteScreenState();
}

class _AutoRouteScreenState extends ConsumerState<AutoRouteScreen> {
  LatLng? _start;
  LatLng? _destination;
  RouteOptions _options = const RouteOptions();
  bool _calculating = false;
  double _progress = 0;
  AutoRoute? _result;

  @override
  void initState() {
    super.initState();
    _destination = widget.destination;
    final vessel = ref.read(vesselProvider);
    _start = vessel.position;
  }

  @override
  void dispose() {
    // Clear preview on dispose
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(autoRoutePreviewProvider.notifier).state = null;
    });
    super.dispose();
  }

  Future<void> _calculate() async {
    if (_start == null || _destination == null) return;

    final engine = ref.read(currentRouteEngineProvider);
    final vessel = ref.read(vesselProfileProvider);

    if (engine.id == 'enc') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('ENC routing not yet available (Coming soon)')),
      );
      return;
    }

    if (engine.id == 'api') {
      final routingApiConfig = ref.read(routingApiProvider);
      if (routingApiConfig.orsApiKey.isEmpty &&
          routingApiConfig.navionicsApiKey.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'No API key configured. Add one in Settings → API Routing.')),
        );
        return;
      }
    }

    setState(() {
      _calculating = true;
      _progress = 0;
      _result = null;
    });

    try {
      final result = await engine.calculateRoute(
        _start!,
        _destination!,
        vessel,
        _options,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );

      if (mounted) {
        setState(() {
          _calculating = false;
          _result = result;
        });
        // Set preview
        ref.read(autoRoutePreviewProvider.notifier).state = result;
      }
    } catch (e) {
      if (mounted) {
        setState(() => _calculating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Routing failed: $e')),
        );
      }
    }
  }

  Future<void> _acceptRoute() async {
    if (_result == null) return;

    // Convert AutoRoute waypoints to saved waypoints + route
    final waypoints = <Waypoint>[];
    for (var i = 0; i < _result!.waypoints.length; i++) {
      final saved = await ref.read(waypointsProvider.notifier).add(
            Waypoint(
              name: i == 0
                  ? 'Start'
                  : i == _result!.waypoints.length - 1
                      ? 'Destination'
                      : 'WP$i',
              position: _result!.waypoints[i],
              createdAt: DateTime.now(),
            ),
          );
      waypoints.add(saved);
    }

    final route = await ref.read(routesProvider.notifier).add(
          RouteModel(
            name:
                'Auto-route (${_result!.engineUsed}) ${DateTime.now().toString().substring(0, 16)}',
            waypoints: waypoints,
            createdAt: DateTime.now(),
          ),
        );

    // Activate the new route
    await ref.read(routesProvider.notifier).setActive(route.id!);

    // Clear preview
    ref.read(autoRoutePreviewProvider.notifier).state = null;

    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                'Route saved: ${_result!.distanceNm.toStringAsFixed(1)} nm')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(vesselProfileProvider);
    final engines = ref.watch(allRouteEnginesProvider);
    final selectedId = ref.watch(selectedEngineIdProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Auto-Route')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Start point
          ListTile(
            leading: const Icon(Icons.trip_origin),
            title: Text(_start != null
                ? '${_start!.latitude.toStringAsFixed(5)}, ${_start!.longitude.toStringAsFixed(5)}'
                : 'Current position unavailable'),
            subtitle: const Text('Start'),
          ),

          // End point
          ListTile(
            leading: const Icon(Icons.flag),
            title: Text(_destination != null
                ? '${_destination!.latitude.toStringAsFixed(5)}, ${_destination!.longitude.toStringAsFixed(5)}'
                : 'Tap on chart to set destination'),
            subtitle: const Text('Destination'),
          ),

          const Divider(height: 24),

          // Engine selector
          Text('Routing Engine',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: selectedId,
            decoration: const InputDecoration(border: OutlineInputBorder()),
            items: engines.map((e) {
              final enabled = e.id != 'enc';
              return DropdownMenuItem(
                value: e.id,
                enabled: enabled,
                child: Text(
                  e.id == 'enc' ? '${e.name} (Coming soon)' : e.name,
                  style: enabled
                      ? null
                      : TextStyle(color: Theme.of(context).disabledColor),
                ),
              );
            }).toList(),
            onChanged: (v) {
              if (v != null) {
                ref.read(selectedEngineIdProvider.notifier).select(v);
              }
            },
          ),

          const SizedBox(height: 16),

          // Vessel profile summary
          Card(
            child: ListTile(
              leading: const Icon(Icons.sailing),
              title: Text(profile.name),
              subtitle: Text(
                  'Draft ${profile.draft}m · Air draft ${profile.airDraft}m'),
              trailing: const Icon(Icons.edit),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const VesselProfileEditor()),
                );
              },
            ),
          ),

          const SizedBox(height: 16),

          // Options
          Text('Options', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),

          Row(
            children: [
              const Text('Safety Margin'),
              Expanded(
                child: Slider(
                  value: _options.safetyMargin,
                  min: 0,
                  max: 2,
                  divisions: 20,
                  label: '${_options.safetyMargin.toStringAsFixed(1)}m',
                  onChanged: (v) {
                    setState(
                        () => _options = _options.copyWith(safetyMargin: v));
                  },
                ),
              ),
              Text('${_options.safetyMargin.toStringAsFixed(1)}m'),
            ],
          ),

          CheckboxListTile(
            title: const Text('Avoid Shallows'),
            value: _options.avoidShallows,
            onChanged: (v) {
              setState(
                  () => _options = _options.copyWith(avoidShallows: v));
            },
          ),
          CheckboxListTile(
            title: const Text('Avoid Bridges'),
            value: _options.avoidBridges,
            onChanged: (v) {
              setState(
                  () => _options = _options.copyWith(avoidBridges: v));
            },
          ),
          CheckboxListTile(
            title: const Text('Prefer Deep Water'),
            value: _options.preferDeepWater,
            onChanged: (v) {
              setState(
                  () => _options = _options.copyWith(preferDeepWater: v));
            },
          ),

          const SizedBox(height: 16),

          // Calculate button
          if (_calculating) ...[
            LinearProgressIndicator(value: _progress > 0 ? _progress : null),
            const SizedBox(height: 8),
            Text('Calculating route... ${(_progress * 100).toInt()}%',
                textAlign: TextAlign.center),
          ] else
            FilledButton.icon(
              onPressed:
                  _start != null && _destination != null ? _calculate : null,
              icon: const Icon(Icons.route),
              label: const Text('Calculate Route'),
            ),

          // Result
          if (_result != null) ...[
            const Divider(height: 32),
            Text('Route Preview',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_result!.distanceNm.toStringAsFixed(1)} nm · '
                      '${_result!.waypoints.length} waypoints',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    // Warnings
                    for (final w in _result!.warnings)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.warning_amber,
                                size: 16, color: Colors.orange),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(w,
                                  style: Theme.of(context).textTheme.bodySmall),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _acceptRoute,
              icon: const Icon(Icons.check),
              label: const Text('Accept & Save Route'),
            ),
          ],
        ],
      ),
    );
  }
}
