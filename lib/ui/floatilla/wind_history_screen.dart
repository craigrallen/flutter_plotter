import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart' hide Path;

import '../../data/providers/signalk_provider.dart';
import '../../data/providers/vessel_provider.dart';

// ---------------------------------------------------------------------------
// Wind observation model
// ---------------------------------------------------------------------------

class _WindObs {
  const _WindObs({
    required this.time,
    required this.tws,
    required this.twd,
    required this.aws,
    required this.awa,
    required this.position,
  });
  final DateTime time;
  final double tws;
  final double twd;
  final double aws;
  final double awa;
  final LatLng? position;
}

// ---------------------------------------------------------------------------
// Buffer provider — stores last 30 observations (one per minute)
// ---------------------------------------------------------------------------

class _WindBufferNotifier extends StateNotifier<List<_WindObs>> {
  _WindBufferNotifier() : super([]);

  void addObservation(_WindObs obs) {
    final updated = [...state, obs];
    if (updated.length > 30) {
      state = updated.sublist(updated.length - 30);
    } else {
      state = updated;
    }
  }

  void clear() => state = [];
}

final _windBufferProvider =
    StateNotifierProvider<_WindBufferNotifier, List<_WindObs>>(
  (ref) => _WindBufferNotifier(),
);

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class WindHistoryScreen extends ConsumerStatefulWidget {
  const WindHistoryScreen({super.key});

  @override
  ConsumerState<WindHistoryScreen> createState() => _WindHistoryScreenState();
}

class _WindHistoryScreenState extends ConsumerState<WindHistoryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  Timer? _sampleTimer;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    // Sample wind every 60 seconds
    _sampleTimer = Timer.periodic(const Duration(seconds: 60), (_) => _sample());
    // Take an immediate first sample
    WidgetsBinding.instance.addPostFrameCallback((_) => _sample());
  }

  void _sample() {
    final env = ref.read(signalKEnvironmentProvider);
    final vessel = ref.read(vesselProvider);
    final tws = env.windSpeedTrue ?? 0.0;
    final twd = env.windAngleTrueGround ?? env.windAngleTrueWater ?? 0.0;
    final aws = env.windSpeedApparent ?? 0.0;
    final awa = env.windAngleApparent ?? 0.0;
    ref.read(_windBufferProvider.notifier).addObservation(
          _WindObs(
            time: DateTime.now(),
            tws: tws,
            twd: twd,
            aws: aws,
            awa: awa,
            position: vessel.position,
          ),
        );
  }

  @override
  void dispose() {
    _sampleTimer?.cancel();
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Wind History'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(icon: Icon(Icons.timeline), text: 'Trail'),
            Tab(icon: Icon(Icons.radar), text: 'Wind Rose'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: const [
          _WindTrailTab(),
          _WindRoseTab(),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tab 1: Wind Trail
// ---------------------------------------------------------------------------

class _WindTrailTab extends ConsumerWidget {
  const _WindTrailTab();

  Color _dotColor(double tws) {
    if (tws < 5) return Colors.blue;
    if (tws < 12) return Colors.green;
    if (tws < 20) return Colors.yellow.shade700;
    if (tws < 30) return Colors.orange;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final observations = ref.watch(_windBufferProvider);
    final env = ref.watch(signalKEnvironmentProvider);
    final vessel = ref.watch(vesselProvider);
    // Use standard OSM tiles
    final mapController = MapController();

    final center = vessel.position ?? const LatLng(57.7, 11.9);

    return Column(
      children: [
        // Current wind display
        Container(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _WindStat('TWS',
                  '${(env.windSpeedTrue ?? 0).toStringAsFixed(1)} kn'),
              _WindStat('TWD',
                  '${(env.windAngleTrueGround ?? env.windAngleTrueWater ?? 0).round()}°'),
              _WindStat('AWA',
                  '${(env.windAngleApparent ?? 0).round()}°'),
              _WindStat('AWS',
                  '${(env.windSpeedApparent ?? 0).toStringAsFixed(1)} kn'),
            ],
          ),
        ),
        Expanded(
          child: Stack(
            children: [
              FlutterMap(
                mapController: mapController,
                options: MapOptions(
                  initialCenter: center,
                  initialZoom: 12,
                ),
                children: [
                  TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.floatilla.app'),
                  TileLayer(urlTemplate: 'https://tiles.openseamap.org/seamark/{z}/{x}/{y}.png', userAgentPackageName: 'com.floatilla.app'),
                  CircleLayer(
                    circles: observations.asMap().entries.map((e) {
                      final idx = e.key;
                      final obs = e.value;
                      final age = idx / math.max(observations.length - 1, 1);
                      final radius = 4.0 + obs.tws * 0.3;
                      final color = _dotColor(obs.tws)
                          .withValues(alpha: 0.3 + age * 0.7);
                      return CircleMarker(
                        point: obs.position ?? center,
                        radius: radius,
                        color: color,
                        borderColor: color,
                        borderStrokeWidth: 0,
                      );
                    }).toList(),
                  ),
                  if (vessel.position != null)
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: vessel.position!,
                          child: const Icon(Icons.directions_boat,
                              color: Colors.white, size: 24),
                        ),
                      ],
                    ),
                ],
              ),
              // Legend
              Positioned(
                right: 12,
                bottom: 12,
                child: _WindSpeedLegend(),
              ),
              if (observations.isEmpty)
                const Center(
                  child: Text(
                    'Collecting wind data...',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _WindStat extends StatelessWidget {
  const _WindStat(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 11, color: Colors.grey)),
        Text(value,
            style: const TextStyle(
                fontSize: 16, fontWeight: FontWeight.bold)),
      ],
    );
  }
}

class _WindSpeedLegend extends StatelessWidget {
  final _speeds = const [
    ('< 5 kn', Colors.blue),
    ('5-12 kn', Colors.green),
    ('12-20 kn', Colors.yellow),
    ('20-30 kn', Colors.orange),
    ('> 30 kn', Colors.red),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: _speeds.map((s) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                      color: s.$2, shape: BoxShape.circle)),
              const SizedBox(width: 4),
              Text(s.$1,
                  style: const TextStyle(
                      fontSize: 11, color: Colors.white)),
            ],
          );
        }).toList(),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tab 2: Wind Rose
// ---------------------------------------------------------------------------

class _WindRoseTab extends ConsumerWidget {
  const _WindRoseTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final observations = ref.watch(_windBufferProvider);

    if (observations.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.air, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('No wind data yet. Check back in a few minutes.'),
          ],
        ),
      );
    }

    // Build 36 sectors
    final sectors = List.generate(36, (_) => <double>[]);
    for (final obs in observations) {
      final sector = (obs.twd / 10).floor() % 36;
      sectors[sector].add(obs.tws);
    }

    final sectorFreq = sectors.map((s) => s.length / observations.length).toList();
    final sectorAvgSpeed =
        sectors.map((s) => s.isEmpty ? 0.0 : s.reduce((a, b) => a + b) / s.length).toList();

    // Stats
    final avgTws =
        observations.map((o) => o.tws).reduce((a, b) => a + b) / observations.length;
    final maxTws = observations.map((o) => o.tws).reduce(math.max);

    // Prevailing direction: sector with most frequency
    int prevSector = 0;
    for (var i = 1; i < 36; i++) {
      if (sectorFreq[i] > sectorFreq[prevSector]) prevSector = i;
    }
    final prevDir = prevSector * 10;

    // Point-of-sail distribution
    final running = observations.where((o) => o.awa.abs() > 135).length;
    final reaching = observations
        .where((o) => o.awa.abs() >= 60 && o.awa.abs() <= 135)
        .length;
    final beating = observations.where((o) => o.awa.abs() < 60).length;
    final total = observations.length;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          SizedBox(
            width: double.infinity,
            height: 300,
            child: CustomPaint(
              painter: _WindRosePainter(
                sectorFreq: sectorFreq,
                sectorAvgSpeed: sectorAvgSpeed,
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Stats cards
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _StatChip(Icons.explore, 'Prevailing', '$prevDir°'),
              _StatChip(Icons.air, 'Avg TWS',
                  '${avgTws.toStringAsFixed(1)} kn'),
              _StatChip(Icons.trending_up, 'Max TWS',
                  '${maxTws.toStringAsFixed(1)} kn'),
              _StatChip(Icons.directions_boat, 'Running',
                  '${(running / total * 100).round()}%'),
              _StatChip(Icons.compare_arrows, 'Reaching',
                  '${(reaching / total * 100).round()}%'),
              _StatChip(Icons.arrow_upward, 'Beating',
                  '${(beating / total * 100).round()}%'),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip(this.icon, this.label, this.value);
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16),
            const SizedBox(width: 6),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style:
                        const TextStyle(fontSize: 11, color: Colors.grey)),
                Text(value,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Wind rose painter
// ---------------------------------------------------------------------------

class _WindRosePainter extends CustomPainter {
  _WindRosePainter({
    required this.sectorFreq,
    required this.sectorAvgSpeed,
  });

  final List<double> sectorFreq;
  final List<double> sectorAvgSpeed;

  Color _sectorColor(double avgSpeed) {
    if (avgSpeed < 5) return Colors.blue;
    if (avgSpeed < 12) return Colors.green;
    if (avgSpeed < 20) return Colors.yellow.shade700;
    if (avgSpeed < 30) return Colors.orange;
    return Colors.red;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxR = math.min(size.width, size.height) / 2 - 20;
    final maxFreq = sectorFreq.reduce(math.max);
    if (maxFreq == 0) return;

    const sectorAngle = math.pi * 2 / 36;

    // Background rings
    final ringPaint = Paint()
      ..color = Colors.grey.withValues(alpha: 0.2)
      ..style = PaintingStyle.stroke;
    for (var i = 1; i <= 4; i++) {
      canvas.drawCircle(center, maxR * i / 4, ringPaint);
    }

    // Sectors
    for (var i = 0; i < 36; i++) {
      final freq = sectorFreq[i];
      if (freq == 0) continue;
      final r = maxR * freq / maxFreq;
      final startAngle = i * sectorAngle - sectorAngle / 2 - math.pi / 2;
      final paint = Paint()
        ..color = _sectorColor(sectorAvgSpeed[i]).withValues(alpha: 0.7)
        ..style = PaintingStyle.fill;
      final borderPaint = Paint()
        ..color = _sectorColor(sectorAvgSpeed[i])
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;

      final path = ui.Path()
        ..moveTo(center.dx, center.dy)
        ..arcTo(
          Rect.fromCircle(center: center, radius: r),
          startAngle,
          sectorAngle,
          false,
        )
        ..close();
      canvas.drawPath(path, paint);
      canvas.drawPath(path, borderPaint);
    }

    // Cardinal labels
    final labels = ['N', 'E', 'S', 'W'];
    final angles = [0.0, math.pi / 2, math.pi, math.pi * 1.5];
    final tp = TextPainter(textDirection: ui.TextDirection.ltr);
    for (var i = 0; i < 4; i++) {
      final x = center.dx + (maxR + 12) * math.sin(angles[i]);
      final y = center.dy - (maxR + 12) * math.cos(angles[i]);
      tp.text = TextSpan(
        text: labels[i],
        style: const TextStyle(
            fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey),
      );
      tp.layout();
      tp.paint(canvas, Offset(x - tp.width / 2, y - tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant _WindRosePainter old) =>
      old.sectorFreq != sectorFreq;
}
