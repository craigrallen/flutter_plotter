import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../../data/providers/vessel_provider.dart';

// ---------------------------------------------------------------------------
// Models
// ---------------------------------------------------------------------------

class _GridPoint {
  const _GridPoint({
    required this.lat,
    required this.lng,
    required this.velocity,
    required this.direction,
    required this.waveHeight,
  });
  final double lat;
  final double lng;
  final double velocity;   // m/s
  final double direction;  // degrees
  final double waveHeight; // m
}

// ---------------------------------------------------------------------------
// API fetch
// ---------------------------------------------------------------------------

Future<Map<int, List<_GridPoint>>> _fetchGrid({
  required double lat,
  required double lng,
  required double rangeLatLng,
  int forecastHours = 48,
}) async {
  // Build grid of lat/lng points at 0.5 degree steps
  final step = 0.5;
  final latMin = lat - rangeLatLng;
  final latMax = lat + rangeLatLng;
  final lngMin = lng - rangeLatLng;
  final lngMax = lng + rangeLatLng;

  // We fetch a few representative points and blend
  final lats = <double>[];
  final lngs = <double>[];
  for (var la = latMin; la <= latMax; la += step) {
    for (var lo = lngMin; lo <= lngMax; lo += step) {
      lats.add(double.parse(la.toStringAsFixed(4)));
      lngs.add(double.parse(lo.toStringAsFixed(4)));
    }
  }

  // Open-Meteo Marine supports a grid via latitude_grid / longitude_grid
  // but as a simpler approach we fetch a single lat/lng that covers the area
  // For now, fetch a representative grid of up to 4 corners + center
  final sampleLats = [latMin, lat, latMax];
  final sampleLngs = [lngMin, lng, lngMax];

  final Map<int, List<_GridPoint>> result = {};

  for (final sla in sampleLats) {
    for (final slo in sampleLngs) {
      final uri = Uri.parse(
        'https://marine-api.open-meteo.com/v1/marine'
        '?latitude=$sla&longitude=$slo'
        '&hourly=ocean_current_velocity,ocean_current_direction,wave_height'
        '&forecast_days=3',
      );
      try {
        final res = await http.get(uri).timeout(const Duration(seconds: 15));
        if (res.statusCode != 200) continue;
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final hourly = data['hourly'] as Map<String, dynamic>;
        final times = (hourly['time'] as List).cast<String>();
        final vels = (hourly['ocean_current_velocity'] as List)
            .map((e) => (e as num?)?.toDouble() ?? 0.0)
            .toList();
        final dirs = (hourly['ocean_current_direction'] as List)
            .map((e) => (e as num?)?.toDouble() ?? 0.0)
            .toList();
        final waves = (hourly['wave_height'] as List)
            .map((e) => (e as num?)?.toDouble() ?? 0.0)
            .toList();

        for (var i = 0; i < times.length && i <= forecastHours; i++) {
          result.putIfAbsent(i, () => []).add(_GridPoint(
            lat: sla,
            lng: slo,
            velocity: vels[i],
            direction: dirs[i],
            waveHeight: waves[i],
          ));
        }
      } catch (_) {
        continue;
      }
    }
  }

  return result;
}

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class OceanCurrentScreen extends ConsumerStatefulWidget {
  const OceanCurrentScreen({super.key});

  @override
  ConsumerState<OceanCurrentScreen> createState() =>
      _OceanCurrentScreenState();
}

class _OceanCurrentScreenState extends ConsumerState<OceanCurrentScreen> {
  bool _loading = false;
  String? _error;
  Map<int, List<_GridPoint>>? _gridData;
  int _forecastHour = 0;
  bool _showWaveHeatmap = false;
  final _mapController = MapController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetch());
  }

  Future<void> _fetch() async {
    final vessel = ref.read(vesselProvider);
    final pos = vessel.position ?? const LatLng(57.7, 11.9);
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _fetchGrid(
        lat: pos.latitude,
        lng: pos.longitude,
        rangeLatLng: 1.5,
      );
      setState(() {
        _gridData = data;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    
    final vessel = ref.watch(vesselProvider);
    final center = vessel.position ?? const LatLng(57.7, 11.9);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ocean Currents'),
        actions: [
          IconButton(
            icon: Icon(_showWaveHeatmap ? Icons.water : Icons.air),
            tooltip: _showWaveHeatmap ? 'Show currents' : 'Show waves',
            onPressed: () =>
                setState(() => _showWaveHeatmap = !_showWaveHeatmap),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetch,
          ),
        ],
      ),
      body: Column(
        children: [
          // Stats bar
          if (_gridData != null) _StatsBar(
            points: _gridData![_forecastHour] ?? [],
            showWaves: _showWaveHeatmap,
          ),
          // Map
          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: center,
                    initialZoom: 8,
                  ),
                  children: [
                    TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.floatilla.app'),
                    TileLayer(urlTemplate: 'https://tiles.openseamap.org/seamark/{z}/{x}/{y}.png', userAgentPackageName: 'com.floatilla.app'),
                    if (_gridData != null && !_loading)
                      MarkerLayer(
                        markers: _buildMarkers(
                          _gridData![_forecastHour] ?? [],
                          _showWaveHeatmap,
                        ),
                      ),
                  ],
                ),
                if (_loading)
                  const Center(child: CircularProgressIndicator()),
                if (_error != null)
                  Center(
                    child: Container(
                      margin: const EdgeInsets.all(24),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.error_outline, color: Colors.red),
                          const SizedBox(height: 8),
                          Text(
                            _error!,
                            style: const TextStyle(color: Colors.white),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton(
                              onPressed: _fetch, child: const Text('Retry')),
                        ],
                      ),
                    ),
                  ),
                // Legend
                Positioned(
                  left: 12,
                  bottom: 60,
                  child: _CurrentLegend(showWaves: _showWaveHeatmap),
                ),
              ],
            ),
          ),
          // Time slider
          if (_gridData != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(Icons.access_time, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        'Forecast: +${_forecastHour}h',
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                  Slider(
                    value: _forecastHour.toDouble(),
                    min: 0,
                    max: 47,
                    divisions: 47,
                    onChanged: (v) =>
                        setState(() => _forecastHour = v.round()),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  List<Marker> _buildMarkers(List<_GridPoint> points, bool showWaves) {
    return points.map((pt) {
      if (showWaves) {
        return Marker(
          point: LatLng(pt.lat, pt.lng),
          width: 48,
          height: 48,
          child: _WaveCircle(height: pt.waveHeight),
        );
      } else {
        return Marker(
          point: LatLng(pt.lat, pt.lng),
          width: 40,
          height: 40,
          child: _CurrentArrow(
            velocity: pt.velocity,
            direction: pt.direction,
          ),
        );
      }
    }).toList();
  }
}

// ---------------------------------------------------------------------------
// Stats bar
// ---------------------------------------------------------------------------

class _StatsBar extends StatelessWidget {
  const _StatsBar({required this.points, required this.showWaves});
  final List<_GridPoint> points;
  final bool showWaves;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) return const SizedBox.shrink();

    if (showWaves) {
      final maxWave = points.map((p) => p.waveHeight).reduce(math.max);
      final avgWave =
          points.map((p) => p.waveHeight).reduce((a, b) => a + b) /
              points.length;
      return Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _InfoPair('Max wave', '${maxWave.toStringAsFixed(1)} m'),
            _InfoPair('Avg wave', '${avgWave.toStringAsFixed(1)} m'),
          ],
        ),
      );
    }

    final maxVel = points.map((p) => p.velocity).reduce(math.max);
    final maxPt = points.firstWhere((p) => p.velocity == maxVel);
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _InfoPair('Max current', '${(maxVel * 1.94384).toStringAsFixed(2)} kn'),
          _InfoPair('Strongest dir', '${maxPt.direction.round()}°'),
        ],
      ),
    );
  }
}

class _InfoPair extends StatelessWidget {
  const _InfoPair(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label,
            style: const TextStyle(fontSize: 11, color: Colors.grey)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Current arrow widget
// ---------------------------------------------------------------------------

class _CurrentArrow extends StatelessWidget {
  const _CurrentArrow({required this.velocity, required this.direction});
  final double velocity;
  final double direction;

  Color get _color {
    final kn = velocity * 1.94384;
    if (kn < 0.5) return Colors.blue;
    if (kn < 1.5) return Colors.green;
    if (kn < 3.0) return Colors.yellow.shade700;
    return Colors.red;
  }

  double get _scale => (velocity * 1.94384).clamp(0.3, 2.0);

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: direction * math.pi / 180.0,
      child: Icon(
        Icons.navigation,
        color: _color,
        size: 20 * _scale,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Wave circle widget
// ---------------------------------------------------------------------------

class _WaveCircle extends StatelessWidget {
  const _WaveCircle({required this.height});
  final double height;

  Color get _color {
    if (height < 0.5) return Colors.blue.withValues(alpha: 0.4);
    if (height < 1.5) return Colors.green.withValues(alpha: 0.5);
    if (height < 3.0) return Colors.orange.withValues(alpha: 0.5);
    return Colors.red.withValues(alpha: 0.6);
  }

  @override
  Widget build(BuildContext context) {
    final r = (height * 8 + 6).clamp(6.0, 30.0);
    return Container(
      width: r * 2,
      height: r * 2,
      decoration: BoxDecoration(
        color: _color,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          height.toStringAsFixed(1),
          style: const TextStyle(
              fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Legend
// ---------------------------------------------------------------------------

class _CurrentLegend extends StatelessWidget {
  const _CurrentLegend({required this.showWaves});
  final bool showWaves;

  @override
  Widget build(BuildContext context) {
    final items = showWaves
        ? const [
            ('< 0.5 m', Colors.blue),
            ('0.5-1.5 m', Colors.green),
            ('1.5-3 m', Colors.orange),
            ('> 3 m', Colors.red),
          ]
        : const [
            ('< 0.5 kn', Colors.blue),
            ('0.5-1.5 kn', Colors.green),
            ('1.5-3 kn', Colors.yellow),
            ('> 3 kn', Colors.red),
          ];

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: items.map((item) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: item.$2,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 4),
              Text(item.$1,
                  style:
                      const TextStyle(fontSize: 11, color: Colors.white)),
            ],
          );
        }).toList(),
      ),
    );
  }
}
