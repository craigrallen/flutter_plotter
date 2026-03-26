import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../../data/models/vessel_state.dart';
import '../../data/models/waypoint.dart';
import '../../data/providers/chart_tile_provider.dart';
import '../../data/providers/route_provider.dart';
import '../../data/providers/vessel_provider.dart';
import 'layers/vessel_layer.dart';
import 'layers/ais_layer.dart';
import 'layers/route_layer.dart';
import 'layers/scale_bar_layer.dart';

/// Whether course-up mode is active (map rotates to match COG).
final courseUpProvider = StateProvider<bool>((ref) => false);

class ChartScreen extends ConsumerStatefulWidget {
  const ChartScreen({super.key});

  @override
  ConsumerState<ChartScreen> createState() => _ChartScreenState();
}

class _ChartScreenState extends ConsumerState<ChartScreen> {
  final _mapController = MapController();
  bool _followVessel = true;

  // Tile providers.
  final _baseLayer = OsmBaseProvider();
  final _seaLayer = OpenSeaMapProvider();

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  void _centreOnVessel() {
    final pos = ref.read(vesselProvider).position;
    if (pos != null) {
      _mapController.move(pos, _mapController.camera.zoom);
      setState(() => _followVessel = true);
    }
  }

  void _onLongPress(TapPosition tapPos, LatLng position) {
    _showAddWaypointDialog(position);
  }

  void _showAddWaypointDialog(LatLng position) {
    final nameController = TextEditingController(
      text: 'WP${ref.read(waypointsProvider).length + 1}',
    );

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Waypoint'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Name'),
              autofocus: true,
            ),
            const SizedBox(height: 8),
            Text(
              '${position.latitude.toStringAsFixed(5)}, '
              '${position.longitude.toStringAsFixed(5)}',
              style: Theme.of(ctx).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final name = nameController.text.trim();
              if (name.isEmpty) return;
              ref.read(waypointsProvider.notifier).add(Waypoint(
                    name: name,
                    position: position,
                    createdAt: DateTime.now(),
                  ));
              Navigator.pop(ctx);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vessel = ref.watch(vesselProvider);
    final courseUp = ref.watch(courseUpProvider);
    final navData = ref.watch(routeNavProvider);

    // Auto-follow: when enabled, keep map centred on vessel.
    final mapRotation = courseUp ? -(vessel.cog ?? 0) : 0.0;

    ref.listen<VesselState>(vesselProvider, (_, next) {
      if (_followVessel && next.position != null) {
        _mapController.move(next.position!, _mapController.camera.zoom);
      }
      if (courseUp) {
        _mapController.rotate(-(next.cog ?? 0));
      }
    });

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: vessel.position ?? const LatLng(57.7089, 11.9746),
              initialZoom: 13,
              initialRotation: mapRotation,
              onLongPress: _onLongPress,
              onPositionChanged: (pos, hasGesture) {
                if (hasGesture) {
                  // User manually panned — stop auto-follow.
                  setState(() => _followVessel = false);
                }
              },
            ),
            children: [
              _baseLayer.tileLayer,
              _seaLayer.tileLayer,
              RouteLayer(mapRotation: mapRotation),
              AisLayer(mapRotation: mapRotation),
              VesselLayer(mapRotation: mapRotation),
            ],
          ),
          // Scale bar overlay.
          Builder(
            builder: (context) {
              return ScaleBarLayer(camera: _mapController.camera);
            },
          ),
          // Route navigation overlay (XTE, bearing, distance, ETA).
          if (navData != null)
            Positioned(
              bottom: 16,
              left: 16,
              right: 80,
              child: _RouteNavOverlay(navData: navData),
            ),
          // Course-up toggle.
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            right: 8,
            child: FloatingActionButton.small(
              heroTag: 'courseUp',
              onPressed: () {
                final toggled = !ref.read(courseUpProvider);
                ref.read(courseUpProvider.notifier).state = toggled;
                if (!toggled) {
                  _mapController.rotate(0);
                }
              },
              child: Icon(
                courseUp ? Icons.navigation : Icons.navigation_outlined,
              ),
            ),
          ),
        ],
      ),
      // Centre-on-vessel FAB.
      floatingActionButton: _followVessel
          ? null
          : FloatingActionButton(
              heroTag: 'centreVessel',
              onPressed: _centreOnVessel,
              child: const Icon(Icons.my_location),
            ),
    );
  }
}

class _RouteNavOverlay extends StatelessWidget {
  final RouteNavData navData;

  const _RouteNavOverlay({required this.navData});

  @override
  Widget build(BuildContext context) {
    final xteDir = navData.xteNm >= 0 ? 'R' : 'L';
    final xteAbs = navData.xteNm.abs();

    String etaStr;
    if (navData.etaToNext != null) {
      final d = navData.etaToNext!;
      if (d.inHours > 0) {
        etaStr = '${d.inHours}h ${d.inMinutes.remainder(60)}m';
      } else {
        etaStr = '${d.inMinutes}m';
      }
    } else {
      etaStr = '--';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          _navItem('BRG', '${navData.bearingToNextDeg.toStringAsFixed(0)}°'),
          _navItem('DST', '${navData.distanceToNextNm.toStringAsFixed(2)} nm'),
          _navItem('XTE', '${xteAbs.toStringAsFixed(2)} $xteDir'),
          _navItem('ETA', etaStr),
        ],
      ),
    );
  }

  Widget _navItem(String label, String value) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
