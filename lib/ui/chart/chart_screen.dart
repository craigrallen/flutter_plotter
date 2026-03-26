import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../../data/models/vessel_state.dart';
import '../../data/providers/chart_tile_provider.dart';
import '../../data/providers/vessel_provider.dart';
import 'layers/vessel_layer.dart';
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

  @override
  Widget build(BuildContext context) {
    final vessel = ref.watch(vesselProvider);
    final courseUp = ref.watch(courseUpProvider);

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
              VesselLayer(mapRotation: mapRotation),
            ],
          ),
          // Scale bar overlay.
          Builder(
            builder: (context) {
              return ScaleBarLayer(camera: _mapController.camera);
            },
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
