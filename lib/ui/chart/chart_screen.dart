import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../../core/nmea/nmea_stream.dart';
import '../../data/models/ais_target.dart';
import '../../data/models/vessel_state.dart';
import '../../data/models/waypoint.dart';
import '../../data/providers/ais_provider.dart';
import '../../data/providers/anchor_provider.dart';
import '../../data/providers/chart_tile_provider.dart';
import '../../data/providers/nmea_config_provider.dart';
import '../../data/providers/route_provider.dart';
import '../../data/providers/settings_provider.dart';
import '../../data/providers/vessel_provider.dart';
import '../../data/providers/weather_provider.dart';
import '../anchor/anchor_screen.dart';
import '../instruments/instrument_panel.dart';
import '../instruments/instrument_strip.dart';
import '../shared/spacing.dart';
import 'layers/anchor_layer.dart';
import 'layers/tide_layer.dart';
import 'layers/vessel_layer.dart';
import 'layers/ais_layer.dart';
import 'layers/route_layer.dart';
import 'layers/scale_bar_layer.dart';
import 'layers/weather_layer.dart';

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
  bool _instrumentsVisible = false;
  bool _cpaAlarmFlash = false;
  Timer? _flashTimer;

  // Tile providers.
  final _baseLayer = OsmBaseProvider();
  final _seaLayer = OpenSeaMapProvider();

  @override
  void dispose() {
    _flashTimer?.cancel();
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
    HapticFeedback.mediumImpact();
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

  /// Check if any AIS target exceeds alarm thresholds.
  void _checkCpaAlarm() {
    final settings = ref.read(appSettingsProvider);
    final targets = ref.read(aisProvider);
    final vessel = ref.read(vesselProvider);
    if (vessel.position == null) return;

    bool alarm = false;
    for (final target in targets.values) {
      if (target.isStale) continue;
      final cpa = target.computeCpa(
        vessel.position!,
        vessel.sog ?? 0,
        vessel.cog ?? 0,
      );
      if (cpa.tcpaMinutes > 0 &&
          cpa.tcpaMinutes < settings.cpaAlarmTimeMinutes &&
          cpa.cpaNm < settings.cpaAlarmDistanceNm) {
        alarm = true;
        break;
      }
    }

    if (alarm && !_cpaAlarmFlash) {
      HapticFeedback.vibrate();
      SystemSound.play(SystemSoundType.alert);
      _startFlash();
    } else if (!alarm && _cpaAlarmFlash) {
      _stopFlash();
    }
  }

  void _startFlash() {
    setState(() => _cpaAlarmFlash = true);
    _flashTimer?.cancel();
    _flashTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!mounted) return;
      setState(() => _cpaAlarmFlash = !_cpaAlarmFlash);
    });
  }

  void _stopFlash() {
    _flashTimer?.cancel();
    _flashTimer = null;
    if (mounted) setState(() => _cpaAlarmFlash = false);
  }

  @override
  Widget build(BuildContext context) {
    final vessel = ref.watch(vesselProvider);
    final courseUp = ref.watch(courseUpProvider);
    final navData = ref.watch(routeNavProvider);
    final settings = ref.watch(appSettingsProvider);
    final connState = ref.watch(nmeaConnectionStateProvider);

    final connectionState = connState.when(
      data: (s) => s,
      loading: () => NmeaConnectionState.disconnected,
      error: (_, _) => NmeaConnectionState.disconnected,
    );

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

    // Check CPA alarm on AIS updates
    ref.listen<Map<int, AisTarget>>(aisProvider, (_, _) => _checkCpaAlarm());

    final orientation = MediaQuery.of(context).orientation;
    final isLandscape = orientation == Orientation.landscape;
    final safePadding = MediaQuery.of(context).padding;

    return Scaffold(
      body: OrientationBuilder(
        builder: (context, orientation) {
          return Row(
            children: [
              // Main chart area
              Expanded(child: _buildChartStack(
                context,
                vessel: vessel,
                courseUp: courseUp,
                navData: navData,
                settings: settings,
                connectionState: connectionState,
                mapRotation: mapRotation,
                safePadding: safePadding,
                isLandscape: isLandscape,
              )),
              // Landscape phone: instrument strip on right
              if (isLandscape) const InstrumentStrip(),
            ],
          );
        },
      ),
    );
  }

  Widget _buildChartStack(
    BuildContext context, {
    required VesselState vessel,
    required bool courseUp,
    required RouteNavData? navData,
    required AppSettings settings,
    required NmeaConnectionState connectionState,
    required double mapRotation,
    required EdgeInsets safePadding,
    required bool isLandscape,
  }) {
    return Stack(
      children: [
        // Map — full bleed, no SafeArea
        RepaintBoundary(
          child: FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter:
                  vessel.position ?? const LatLng(57.7089, 11.9746),
              initialZoom: 13,
              initialRotation: mapRotation,
              onLongPress: _onLongPress,
              onPositionChanged: (pos, hasGesture) {
                if (hasGesture) {
                  setState(() => _followVessel = false);
                }
              },
            ),
            children: [
              _baseLayer.tileLayer,
              _seaLayer.tileLayer,
              const RepaintBoundary(child: WeatherLayer()),
              const RepaintBoundary(child: TideLayer()),
              RepaintBoundary(child: RouteLayer(mapRotation: mapRotation)),
              const RepaintBoundary(child: AnchorLayer()),
              RepaintBoundary(child: AisLayer(mapRotation: mapRotation)),
              RepaintBoundary(child: VesselLayer(mapRotation: mapRotation)),
            ],
          ),
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
            bottom: _instrumentsVisible
                ? 220 + safePadding.bottom
                : Spacing.md + safePadding.bottom,
            left: Spacing.md + safePadding.left,
            right: 80 + safePadding.right,
            child: _RouteNavOverlay(navData: navData),
          ),

        // Top-right controls inside SafeArea
        Positioned(
          top: safePadding.top + Spacing.sm,
          right: safePadding.right + Spacing.sm,
          child: Column(
            children: [
              // Connection status dot
              SizedBox(
                width: Spacing.minTapTarget,
                height: Spacing.minTapTarget,
                child: Center(
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.black.withValues(alpha: 0.5),
                    ),
                    child: Center(
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color:
                              connectionState == NmeaConnectionState.connected
                                  ? Colors.green
                                  : connectionState ==
                                              NmeaConnectionState.connecting ||
                                          connectionState ==
                                              NmeaConnectionState.reconnecting
                                      ? Colors.amber
                                      : Colors.red,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // Night mode toggle
              SizedBox(
                width: Spacing.minTapTarget,
                height: Spacing.minTapTarget,
                child: FloatingActionButton.small(
                  heroTag: 'nightMode',
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    ref.read(appSettingsProvider.notifier).toggleNightMode();
                  },
                  child: Icon(
                    settings.nightMode
                        ? Icons.dark_mode
                        : Icons.dark_mode_outlined,
                  ),
                ),
              ),
              const SizedBox(height: Spacing.sm),
              // Course-up toggle
              SizedBox(
                width: Spacing.minTapTarget,
                height: Spacing.minTapTarget,
                child: FloatingActionButton.small(
                  heroTag: 'courseUp',
                  onPressed: () {
                    HapticFeedback.selectionClick();
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
              const SizedBox(height: Spacing.sm),
              // Weather overlay toggle
              SizedBox(
                width: Spacing.minTapTarget,
                height: Spacing.minTapTarget,
                child: _WeatherToggleButton(ref: ref),
              ),
            ],
          ),
        ),

        // Instrument panel toggle (bottom center) — hide in landscape
        if (!isLandscape)
          Positioned(
            bottom: _instrumentsVisible
                ? 200 + safePadding.bottom
                : Spacing.sm + safePadding.bottom,
            left: 0,
            right: 0,
            child: Center(
              child: GestureDetector(
                onTap: () =>
                    setState(() => _instrumentsVisible = !_instrumentsVisible),
                onVerticalDragEnd: (details) {
                  if (details.primaryVelocity != null) {
                    if (details.primaryVelocity! < 0) {
                      setState(() => _instrumentsVisible = true);
                    } else {
                      setState(() => _instrumentsVisible = false);
                    }
                  }
                },
                child: Container(
                  width: Spacing.minTapTarget * 2,
                  height: Spacing.minTapTarget,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    _instrumentsVisible
                        ? Icons.keyboard_arrow_down
                        : Icons.keyboard_arrow_up,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ),
          ),

        // Slide-up instrument panel — hide in landscape
        if (_instrumentsVisible && !isLandscape)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              top: false,
              child: GestureDetector(
                onVerticalDragEnd: (details) {
                  if (details.primaryVelocity != null &&
                      details.primaryVelocity! > 0) {
                    setState(() => _instrumentsVisible = false);
                  }
                },
                child: const InstrumentPanel(),
              ),
            ),
          ),

        // CPA alarm red flash overlay
        if (_cpaAlarmFlash)
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                color: Colors.red.withValues(alpha: 0.25),
              ),
            ),
          ),

        // FAB area — inside SafeArea padding
        Positioned(
          bottom: safePadding.bottom + Spacing.md,
          right: safePadding.right + Spacing.md,
          child: _buildFab(context, ref),
        ),
      ],
    );
  }

  Widget _buildFab(BuildContext context, WidgetRef ref) {
    final anchor = ref.watch(anchorProvider);

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (anchor.isActive) ...[
            // Release anchor button.
            SizedBox(
              width: Spacing.minTapTarget,
              height: Spacing.minTapTarget,
              child: FloatingActionButton.small(
                heroTag: 'releaseAnchor',
                backgroundColor: Colors.red,
                onPressed: () {
                  HapticFeedback.selectionClick();
                  ref.read(anchorProvider.notifier).releaseAnchor();
                },
                child: const Icon(Icons.clear, color: Colors.white),
              ),
            ),
            const SizedBox(height: Spacing.sm),
            // Anchor info button.
            SizedBox(
              width: Spacing.minTapTarget,
              height: Spacing.minTapTarget,
              child: FloatingActionButton.small(
                heroTag: 'anchorInfo',
                onPressed: () {
                  HapticFeedback.selectionClick();
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const AnchorScreen()),
                  );
                },
                child: const Icon(Icons.anchor),
              ),
            ),
            const SizedBox(height: Spacing.sm),
          ] else ...[
            SizedBox(
              width: Spacing.minTapTarget,
              height: Spacing.minTapTarget,
              child: FloatingActionButton.small(
                heroTag: 'setAnchor',
                onPressed: () {
                  HapticFeedback.heavyImpact();
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const AnchorScreen()),
                  );
                },
                child: const Icon(Icons.anchor),
              ),
            ),
            const SizedBox(height: Spacing.sm),
          ],
          if (!_followVessel)
            SizedBox(
              width: Spacing.minTapTarget,
              height: Spacing.minTapTarget,
              child: FloatingActionButton(
                heroTag: 'centreVessel',
                onPressed: () {
                  HapticFeedback.selectionClick();
                  _centreOnVessel();
                },
                child: const Icon(Icons.my_location),
              ),
            ),
        ],
      ),
    );
  }
}

/// Weather overlay toggle button: cycles Off → Wind → Waves → Off.
class _WeatherToggleButton extends StatelessWidget {
  final WidgetRef ref;

  const _WeatherToggleButton({required this.ref});

  @override
  Widget build(BuildContext context) {
    final overlay = ref.watch(weatherOverlayProvider);

    IconData icon;
    switch (overlay) {
      case WeatherOverlay.wind:
        icon = Icons.air;
      case WeatherOverlay.waves:
        icon = Icons.waves;
      case WeatherOverlay.off:
        icon = Icons.cloud_off;
    }

    return FloatingActionButton.small(
      heroTag: 'weatherToggle',
      onPressed: () {
        HapticFeedback.selectionClick();
        final next = WeatherOverlay.values[
            (overlay.index + 1) % WeatherOverlay.values.length];
        ref.read(weatherOverlayProvider.notifier).state = next;
      },
      child: Icon(icon),
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
              fontSize: 12,
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
