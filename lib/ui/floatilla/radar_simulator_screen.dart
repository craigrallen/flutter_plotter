import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../../data/providers/vessel_provider.dart';
import '../../data/providers/signalk_provider.dart';

/// Synthetic radar overlay — generates a PPI-style radar display from AIS + chart data.
/// Not real radar — a situational awareness tool showing nearby AIS targets
/// as they would appear on a ship's radar, relative to own vessel.
class RadarSimulatorScreen extends ConsumerStatefulWidget {
  const RadarSimulatorScreen({super.key});

  @override
  ConsumerState<RadarSimulatorScreen> createState() =>
      _RadarSimulatorScreenState();
}

class _RadarSimulatorScreenState extends ConsumerState<RadarSimulatorScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sweepController;
  double _rangeNm = 3.0;
  bool _northUp = false;
  bool _showLabels = true;
  static const _ranges = [0.5, 1.0, 2.0, 3.0, 6.0, 12.0, 24.0];

  @override
  void initState() {
    super.initState();
    _sweepController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
  }

  @override
  void dispose() {
    _sweepController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vessel = ref.watch(vesselProvider);
    final skState = ref.watch(signalKProvider);
    final aisTargets = skState.otherVessels;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: const Color(0xFF001100),
        foregroundColor: const Color(0xFF00FF44),
        title: const Text('Radar', style: TextStyle(color: Color(0xFF00FF44))),
        actions: [
          // Range selector
          PopupMenuButton<double>(
            icon: Text('${_rangeNm.toStringAsFixed(
                _rangeNm < 1 ? 1 : 0)} nm',
                style: const TextStyle(color: Color(0xFF00FF44), fontSize: 13)),
            color: const Color(0xFF001100),
            onSelected: (v) => setState(() => _rangeNm = v),
            itemBuilder: (_) => _ranges
                .map((r) => PopupMenuItem(
                      value: r,
                      child: Text('${r.toStringAsFixed(r < 1 ? 1 : 0)} nm',
                          style:
                              const TextStyle(color: Color(0xFF00FF44))),
                    ))
                .toList(),
          ),
          // North-up toggle
          IconButton(
            icon: Icon(_northUp ? Icons.north : Icons.navigation,
                color: const Color(0xFF00FF44)),
            tooltip: _northUp ? 'North-up' : 'Head-up',
            onPressed: () => setState(() => _northUp = !_northUp),
          ),
          // Labels toggle
          IconButton(
            icon: Icon(
                _showLabels ? Icons.label : Icons.label_off,
                color: const Color(0xFF00FF44)),
            onPressed: () => setState(() => _showLabels = !_showLabels),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (ctx, constraints) {
                final size = min(constraints.maxWidth, constraints.maxHeight);
                return Center(
                  child: SizedBox(
                    width: size,
                    height: size,
                    child: AnimatedBuilder(
                      animation: _sweepController,
                      builder: (_, __) => CustomPaint(
                        painter: _RadarPainter(
                          sweepAngle:
                              _sweepController.value * 2 * pi,
                          rangeNm: _rangeNm,
                          ownPos: vessel.position,
                          ownHeading: vessel.cog ?? 0,
                          northUp: _northUp,
                          showLabels: _showLabels,
                          aisTargets: aisTargets.values
                              .where((t) => t.position != null)
                              .toList(),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          _buildStatusBar(vessel, aisTargets.length),
        ],
      ),
    );
  }

  Widget _buildStatusBar(dynamic vessel, int targetCount) {
    return Container(
      color: const Color(0xFF001100),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          _RadarStat(
              label: 'HDG',
              value:
                  '${(vessel.cog ?? 0).toStringAsFixed(0)}°'),
          const SizedBox(width: 20),
          _RadarStat(
              label: 'SOG',
              value:
                  '${(vessel.sog ?? 0).toStringAsFixed(1)} kn'),
          const SizedBox(width: 20),
          _RadarStat(label: 'TGTS', value: '$targetCount'),
          const SizedBox(width: 20),
          _RadarStat(
              label: 'RNG',
              value:
                  '${_rangeNm.toStringAsFixed(_rangeNm < 1 ? 1 : 0)} nm'),
          const Spacer(),
          Text(
            _northUp ? 'N-UP' : 'H-UP',
            style: const TextStyle(
                color: Color(0xFF00FF44), fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _RadarStat extends StatelessWidget {
  final String label;
  final String value;

  const _RadarStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                color: Color(0xFF005500), fontSize: 10)),
        Text(value,
            style: const TextStyle(
                color: Color(0xFF00FF44),
                fontSize: 13,
                fontFamily: 'monospace')),
      ],
    );
  }
}

class _RadarPainter extends CustomPainter {
  final double sweepAngle;
  final double rangeNm;
  final LatLng? ownPos;
  final double ownHeading;
  final bool northUp;
  final bool showLabels;
  final List<dynamic> aisTargets;

  static const _nmToM = 1852.0;

  _RadarPainter({
    required this.sweepAngle,
    required this.rangeNm,
    required this.ownPos,
    required this.ownHeading,
    required this.northUp,
    required this.showLabels,
    required this.aisTargets,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 2;

    // Background
    canvas.drawCircle(center, radius,
        Paint()..color = const Color(0xFF001800));

    // Range rings
    final ringPaint = Paint()
      ..color = const Color(0xFF003300)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;
    for (int i = 1; i <= 4; i++) {
      canvas.drawCircle(center, radius * i / 4, ringPaint);
    }

    // Cross-hair
    final crossPaint = Paint()
      ..color = const Color(0xFF003300)
      ..strokeWidth = 0.5;
    canvas.drawLine(
        Offset(center.dx, center.dy - radius),
        Offset(center.dx, center.dy + radius),
        crossPaint);
    canvas.drawLine(
        Offset(center.dx - radius, center.dy),
        Offset(center.dx + radius, center.dy),
        crossPaint);

    // Sweep sector (trailing glow)
    final sweepPaint = Paint()
      ..shader = SweepGradient(
        center: Alignment.center,
        startAngle: sweepAngle - 1.2,
        endAngle: sweepAngle,
        colors: const [
          Colors.transparent,
          Color(0x3300FF44),
          Color(0x8800FF44),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius, sweepPaint);

    // Sweep line
    final sweepLinePaint = Paint()
      ..color = const Color(0xFF00FF44)
      ..strokeWidth = 1.5;
    canvas.drawLine(
        center,
        Offset(
          center.dx + cos(sweepAngle - pi / 2) * radius,
          center.dy + sin(sweepAngle - pi / 2) * radius,
        ),
        sweepLinePaint);

    // Own vessel marker
    final ownPaint = Paint()..color = const Color(0xFF00FF44);
    canvas.drawCircle(center, 4, ownPaint);

    // AIS targets
    if (ownPos != null) {
      for (final target in aisTargets) {
        _paintTarget(canvas, center, radius, target);
      }
    }

    // Range labels
    final labelPainter = TextPainter(textDirection: TextDirection.ltr);
    for (int i = 1; i <= 4; i++) {
      final labelNm = rangeNm * i / 4;
      labelPainter.text = TextSpan(
        text: '${labelNm.toStringAsFixed(labelNm < 1 ? 1 : 0)}',
        style: const TextStyle(color: Color(0xFF005500), fontSize: 9),
      );
      labelPainter.layout();
      labelPainter.paint(
          canvas,
          Offset(center.dx + 3,
              center.dy - radius * i / 4 - labelPainter.height));
    }

    // Outer ring clip
    canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = Colors.black
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4);
  }

  void _paintTarget(Canvas canvas, Offset center, double radius, dynamic t) {
    if (t.position == null || ownPos == null) return;

    // Bearing + distance to target
    final dLat = t.position!.latitude - ownPos!.latitude;
    final dLng = t.position!.longitude - ownPos!.longitude;

    // Approx distance in nm
    final distM = sqrt(pow(dLat * 111320, 2) +
        pow(dLng * 111320 * cos(ownPos!.latitude * pi / 180), 2));
    final distNm = distM / _nmToM;
    if (distNm > rangeNm) return;

    // Bearing to target (degrees from north)
    double bearing = atan2(
          dLng * cos(ownPos!.latitude * pi / 180),
          dLat,
        ) *
        180 /
        pi;
    if (!northUp) {
      // Head-up: rotate by own heading
      bearing -= ownHeading;
    }
    final bearingRad = bearing * pi / 180;

    // Position on screen
    final fraction = distNm / rangeNm;
    final x = center.dx + sin(bearingRad) * radius * fraction;
    final y = center.dy - cos(bearingRad) * radius * fraction;

    // Target blip (radar-style: bright centre, fainter echo)
    final blipPaint = Paint()..color = const Color(0xFF00FF44);
    final echoPaint = Paint()
      ..color = const Color(0x5500FF44)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    canvas.drawCircle(Offset(x, y), 3, blipPaint);
    canvas.drawCircle(Offset(x, y), 8, echoPaint);

    // Heading vector (if moving)
    if (t.sog != null && t.sog > 0.5 && t.cog != null) {
      double cog = t.cog! - (northUp ? 0 : ownHeading);
      final cogRad = cog * pi / 180;
      final vecLen =
          (t.sog as double) / rangeNm * radius * 0.08; // 5-min vector
      canvas.drawLine(
          Offset(x, y),
          Offset(x + sin(cogRad) * vecLen, y - cos(cogRad) * vecLen),
          blipPaint..strokeWidth = 1.5);
    }

    // Label
    if (showLabels && t.name != null && (t.name as String).isNotEmpty) {
      final tp = TextPainter(textDirection: TextDirection.ltr);
      tp.text = TextSpan(
        text: t.name,
        style: const TextStyle(color: Color(0xFF00CC33), fontSize: 9),
      );
      tp.layout();
      tp.paint(canvas, Offset(x + 5, y - 5));
    }

    // CPA warning ring
    if (t.cpaDistNm != null && (t.cpaDistNm as double) < 0.5 &&
        t.tcpaMinutes != null && (t.tcpaMinutes as double) < 30) {
      canvas.drawCircle(
          Offset(x, y),
          12,
          Paint()
            ..color = const Color(0xFFFF4400)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5);
    }
  }

  @override
  bool shouldRepaint(_RadarPainter old) => true;
}
