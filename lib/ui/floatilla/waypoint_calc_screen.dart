import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../data/providers/vessel_provider.dart';
import '../../data/providers/route_provider.dart';
import '../../data/models/waypoint.dart';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const double _kNmToMetres = 1852.0;
const double _kEarthRadiusNm = 3440.065; // nautical miles

// ---------------------------------------------------------------------------
// Math helpers
// ---------------------------------------------------------------------------

double _degToRad(double d) => d * math.pi / 180.0;
double _radToDeg(double r) => r * 180.0 / math.pi;

/// Direct problem: given start, bearing (deg true), distance (nm) → end.
LatLng _directProblem(LatLng start, double bearingDeg, double distNm) {
  final lat1 = _degToRad(start.latitude);
  final lon1 = _degToRad(start.longitude);
  final brng = _degToRad(bearingDeg);
  final d = distNm / _kEarthRadiusNm; // angular distance

  final lat2 = math.asin(
    math.sin(lat1) * math.cos(d) +
        math.cos(lat1) * math.sin(d) * math.cos(brng),
  );
  final lon2 = lon1 +
      math.atan2(
        math.sin(brng) * math.sin(d) * math.cos(lat1),
        math.cos(d) - math.sin(lat1) * math.sin(lat2),
      );

  return LatLng(_radToDeg(lat2), _radToDeg(lon2));
}

/// Inverse problem: given two points → bearing A→B (deg true) and distance (nm).
({double bearingAB, double bearingBA, double distNm}) _inverseProblem(
    LatLng a, LatLng b) {
  final lat1 = _degToRad(a.latitude);
  final lat2 = _degToRad(b.latitude);
  final dLat = lat2 - lat1;
  final dLon = _degToRad(b.longitude - a.longitude);

  final sinHalfDLat = math.sin(dLat / 2);
  final sinHalfDLon = math.sin(dLon / 2);
  final hav = sinHalfDLat * sinHalfDLat +
      math.cos(lat1) * math.cos(lat2) * sinHalfDLon * sinHalfDLon;
  final dist = 2 * math.asin(math.sqrt(hav)) * _kEarthRadiusNm;

  final y = math.sin(dLon) * math.cos(lat2);
  final x = math.cos(lat1) * math.sin(lat2) -
      math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
  final brngAB = (_radToDeg(math.atan2(y, x)) + 360) % 360;
  final brngBA = (brngAB + 180) % 360;
  return (bearingAB: brngAB, bearingBA: brngBA, distNm: dist);
}

/// Format decimal degrees as "DD° MM.mmm' H".
String _formatDM(double dd, bool isLat) {
  final sign = dd < 0 ? -1 : 1;
  final abs = dd.abs();
  final deg = abs.floor();
  final min = (abs - deg) * 60.0;
  final hemi = isLat ? (sign > 0 ? 'N' : 'S') : (sign > 0 ? 'E' : 'W');
  return "$deg° ${min.toStringAsFixed(3)}' $hemi";
}

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class WaypointCalcScreen extends ConsumerStatefulWidget {
  const WaypointCalcScreen({super.key});

  @override
  ConsumerState<WaypointCalcScreen> createState() =>
      _WaypointCalcScreenState();
}

class _WaypointCalcScreenState extends ConsumerState<WaypointCalcScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _mapController = MapController();

  // Mode A controllers
  final _aStartLat = TextEditingController();
  final _aStartLon = TextEditingController();
  final _aBearing = TextEditingController();
  final _aDist = TextEditingController();

  // Mode B controllers
  final _bALat = TextEditingController();
  final _bALon = TextEditingController();
  final _bBLat = TextEditingController();
  final _bBLon = TextEditingController();

  // Results
  LatLng? _resultA;
  ({double bearingAB, double bearingBA, double distNm})? _resultB;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _tabs.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tabs.dispose();
    _mapController.dispose();
    _aStartLat.dispose();
    _aStartLon.dispose();
    _aBearing.dispose();
    _aDist.dispose();
    _bALat.dispose();
    _bALon.dispose();
    _bBLat.dispose();
    _bBLon.dispose();
    super.dispose();
  }

  void _fillFromGps() {
    final pos = ref.read(vesselProvider).position;
    if (pos == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No GPS position available')),
      );
      return;
    }
    setState(() {
      _aStartLat.text = pos.latitude.toStringAsFixed(6);
      _aStartLon.text = pos.longitude.toStringAsFixed(6);
    });
  }

  void _calculateA() {
    final lat = double.tryParse(_aStartLat.text);
    final lon = double.tryParse(_aStartLon.text);
    final brng = double.tryParse(_aBearing.text);
    final dist = double.tryParse(_aDist.text);
    if (lat == null || lon == null || brng == null || dist == null) return;
    final result = _directProblem(LatLng(lat, lon), brng, dist);
    setState(() => _resultA = result);
    _mapController.move(result, 11);
  }

  void _calculateB() {
    final aLat = double.tryParse(_bALat.text);
    final aLon = double.tryParse(_bALon.text);
    final bLat = double.tryParse(_bBLat.text);
    final bLon = double.tryParse(_bBLon.text);
    if (aLat == null || aLon == null || bLat == null || bLon == null) return;
    final result = _inverseProblem(LatLng(aLat, aLon), LatLng(bLat, bLon));
    setState(() => _resultB = result);
    _mapController.move(
      LatLng((aLat + bLat) / 2, (aLon + bLon) / 2),
      10,
    );
  }

  void _swapB() {
    final tempLat = _bALat.text;
    final tempLon = _bALon.text;
    setState(() {
      _bALat.text = _bBLat.text;
      _bALon.text = _bBLon.text;
      _bBLat.text = tempLat;
      _bBLon.text = tempLon;
    });
    _calculateB();
  }

  void _copyCoords(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Coordinates copied'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _addToRoute(LatLng pos) {
    ref.read(waypointsProvider.notifier).add(Waypoint(
          name: 'WP-Calc',
          position: pos,
          createdAt: DateTime.now(),
        ));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Waypoint added to route')),
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Waypoint Calculator'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Bearing + Dist'),
            Tab(text: 'Two Points'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _buildModeA(context),
          _buildModeB(context),
        ],
      ),
    );
  }

  Widget _buildModeA(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Start Position',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _aStartLat,
                  decoration: const InputDecoration(
                    labelText: 'Start Latitude',
                    hintText: '57.7089',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true, signed: true),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _aStartLon,
                  decoration: const InputDecoration(
                    labelText: 'Start Longitude',
                    hintText: '11.9746',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true, signed: true),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _fillFromGps,
            icon: const Icon(Icons.my_location),
            label: const Text('Fill from GPS'),
          ),
          const SizedBox(height: 16),
          Text('Bearing and Distance',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _aBearing,
                  decoration: const InputDecoration(
                    labelText: 'Bearing (degrees)',
                    hintText: '270',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _aDist,
                  decoration: const InputDecoration(
                    labelText: 'Distance (nm)',
                    hintText: '10.0',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _calculateA,
              icon: const Icon(Icons.calculate),
              label: const Text('Calculate Destination'),
            ),
          ),
          if (_resultA != null) ...[
            const SizedBox(height: 20),
            _ResultCard(
              title: 'Destination',
              rows: [
                ('Decimal', '${_resultA!.latitude.toStringAsFixed(6)}, '
                    '${_resultA!.longitude.toStringAsFixed(6)}'),
                ('Lat', _formatDM(_resultA!.latitude, true)),
                ('Lon', _formatDM(_resultA!.longitude, false)),
              ],
              actions: [
                OutlinedButton.icon(
                  onPressed: () => _copyCoords(
                    '${_resultA!.latitude.toStringAsFixed(6)}, '
                    '${_resultA!.longitude.toStringAsFixed(6)}',
                  ),
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text('Copy'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: () => _addToRoute(_resultA!),
                  icon: const Icon(Icons.add_location, size: 16),
                  label: const Text('Add to Route'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildMap(
              points: [
                LatLng(double.tryParse(_aStartLat.text) ?? 0,
                    double.tryParse(_aStartLon.text) ?? 0),
                _resultA!,
              ],
              markers: [_resultA!],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildModeB(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Point A', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _bALat,
                  decoration: const InputDecoration(
                    labelText: 'Latitude',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true, signed: true),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _bALon,
                  decoration: const InputDecoration(
                    labelText: 'Longitude',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true, signed: true),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Center(
            child: OutlinedButton.icon(
              onPressed: _swapB,
              icon: const Icon(Icons.swap_vert),
              label: const Text('Swap A / B'),
            ),
          ),
          const SizedBox(height: 12),
          Text('Point B', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _bBLat,
                  decoration: const InputDecoration(
                    labelText: 'Latitude',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true, signed: true),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _bBLon,
                  decoration: const InputDecoration(
                    labelText: 'Longitude',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true, signed: true),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _calculateB,
              icon: const Icon(Icons.calculate),
              label: const Text('Calculate Bearing + Distance'),
            ),
          ),
          if (_resultB != null) ...[
            const SizedBox(height: 20),
            _ResultCard(
              title: 'Result',
              rows: [
                ('A to B', '${_resultB!.bearingAB.toStringAsFixed(1)}° T'),
                ('B to A', '${_resultB!.bearingBA.toStringAsFixed(1)}° T'),
                ('Distance', '${_resultB!.distNm.toStringAsFixed(3)} nm'),
                (
                  'Distance',
                  '${(_resultB!.distNm * _kNmToMetres / 1000).toStringAsFixed(2)} km'
                ),
              ],
              actions: const [],
            ),
            if (_bALat.text.isNotEmpty &&
                _bALon.text.isNotEmpty &&
                _bBLat.text.isNotEmpty &&
                _bBLon.text.isNotEmpty) ...[
              const SizedBox(height: 16),
              _buildMap(
                points: [
                  LatLng(double.tryParse(_bALat.text) ?? 0,
                      double.tryParse(_bALon.text) ?? 0),
                  LatLng(double.tryParse(_bBLat.text) ?? 0,
                      double.tryParse(_bBLon.text) ?? 0),
                ],
                markers: [
                  LatLng(double.tryParse(_bALat.text) ?? 0,
                      double.tryParse(_bALon.text) ?? 0),
                  LatLng(double.tryParse(_bBLat.text) ?? 0,
                      double.tryParse(_bBLon.text) ?? 0),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildMap({
    required List<LatLng> points,
    required List<LatLng> markers,
  }) {
    if (points.isEmpty) return const SizedBox.shrink();

    final center = LatLng(
      points.map((p) => p.latitude).reduce((a, b) => a + b) / points.length,
      points.map((p) => p.longitude).reduce((a, b) => a + b) / points.length,
    );

    return SizedBox(
      height: 220,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: center,
            initialZoom: 10,
          ),
          children: [
            TileLayer(
              urlTemplate:
                  'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.floatilla.app',
            ),
            if (points.length >= 2)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: points,
                    strokeWidth: 2.5,
                    color: Colors.blue,
                  ),
                ],
              ),
            MarkerLayer(
              markers: markers
                  .map(
                    (p) => Marker(
                      point: p,
                      width: 24,
                      height: 24,
                      child: const Icon(
                        Icons.location_on,
                        color: Colors.red,
                        size: 24,
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared result card widget
// ---------------------------------------------------------------------------

class _ResultCard extends StatelessWidget {
  final String title;
  final List<(String, String)> rows;
  final List<Widget> actions;

  const _ResultCard({
    required this.title,
    required this.rows,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      color: cs.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: cs.onPrimaryContainer,
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            for (final (label, value) in rows) ...[
              Row(
                children: [
                  SizedBox(
                    width: 72,
                    child: Text(
                      label,
                      style: TextStyle(
                        color: cs.onPrimaryContainer.withValues(alpha: 0.7),
                        fontSize: 12,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      value,
                      style: TextStyle(
                        color: cs.onPrimaryContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
            ],
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(children: actions),
            ],
          ],
        ),
      ),
    );
  }
}
