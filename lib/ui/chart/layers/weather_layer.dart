import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/models/weather_forecast.dart';
import '../../../data/providers/weather_provider.dart';

/// Renders wind barbs or wave height overlay on the chart.
class WeatherLayer extends ConsumerWidget {
  const WeatherLayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overlay = ref.watch(weatherOverlayProvider);
    if (overlay == WeatherOverlay.off) return const SizedBox.shrink();

    final points = ref.watch(weatherPointsAtTimeProvider);
    if (points.isEmpty) return const SizedBox.shrink();

    if (overlay == WeatherOverlay.wind) {
      return _WindBarbLayer(points: points);
    } else {
      return _WaveHeightLayer(points: points);
    }
  }
}

class _WindBarbLayer extends StatelessWidget {
  final List<WeatherPoint> points;

  const _WindBarbLayer({required this.points});

  @override
  Widget build(BuildContext context) {
    final markers = points.map((p) => Marker(
          point: p.position,
          width: 60,
          height: 60,
          child: CustomPaint(
            size: const Size(60, 60),
            painter: _WindBarbPainter(
              speedKn: p.windSpeedKn,
              directionDeg: p.windDirectionDeg,
            ),
          ),
        ));
    return MarkerLayer(markers: markers.toList());
  }
}

class _WaveHeightLayer extends StatelessWidget {
  final List<WeatherPoint> points;

  const _WaveHeightLayer({required this.points});

  @override
  Widget build(BuildContext context) {
    final circles = points
        .where((p) => p.waveHeightM != null && p.waveHeightM! > 0)
        .map((p) {
      final h = p.waveHeightM!;
      final color = _waveColor(h);
      return CircleMarker(
        point: p.position,
        radius: 30,
        color: color.withValues(alpha: 0.35),
        borderColor: color.withValues(alpha: 0.6),
        borderStrokeWidth: 1,
      );
    });
    return CircleLayer(circles: circles.toList());
  }

  Color _waveColor(double heightM) {
    if (heightM < 0.5) return Colors.green;
    if (heightM < 1.0) return Colors.lightGreen;
    if (heightM < 2.0) return Colors.yellow;
    if (heightM < 3.0) return Colors.orange;
    return Colors.red;
  }
}

/// Standard meteorological wind barb painter.
/// Staff points into the wind direction. Barbs: pennant=50kt, full=10kt, half=5kt.
class _WindBarbPainter extends CustomPainter {
  final double speedKn;
  final double directionDeg;

  _WindBarbPainter({required this.speedKn, required this.directionDeg});

  @override
  void paint(Canvas canvas, Size size) {
    if (speedKn < 1) {
      // Calm: draw a circle.
      final paint = Paint()
        ..color = const Color(0xFF333333)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      canvas.drawCircle(
        Offset(size.width / 2, size.height / 2),
        6,
        paint,
      );
      return;
    }

    final cx = size.width / 2;
    final cy = size.height / 2;

    canvas.save();
    canvas.translate(cx, cy);
    // Rotate so staff points into the wind (from direction).
    canvas.rotate((directionDeg + 180) * pi / 180);

    final paint = Paint()
      ..color = const Color(0xFF333333)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    final fillPaint = Paint()
      ..color = const Color(0xFF333333)
      ..style = PaintingStyle.fill;

    final staffLen = 25.0;

    // Staff: vertical line from center downward.
    canvas.drawLine(Offset(0, 0), Offset(0, -staffLen), paint);

    // Decompose speed into pennants(50), full barbs(10), half barbs(5).
    var remaining = speedKn.round();
    int pennants = remaining ~/ 50;
    remaining -= pennants * 50;
    int fullBarbs = remaining ~/ 10;
    remaining -= fullBarbs * 10;
    int halfBarbs = remaining >= 3 ? 1 : 0; // 3kt threshold for half barb

    var y = -staffLen; // start from top of staff
    const barbLen = 12.0;
    const spacing = 4.0;

    // Draw pennants (filled triangles).
    for (int i = 0; i < pennants; i++) {
      final path = ui.Path()
        ..moveTo(0, y)
        ..lineTo(barbLen, y + spacing / 2)
        ..lineTo(0, y + spacing)
        ..close();
      canvas.drawPath(path, fillPaint);
      y += spacing;
    }

    // Gap after pennants if there are also barbs.
    if (pennants > 0 && (fullBarbs > 0 || halfBarbs > 0)) {
      y += spacing / 2;
    }

    // Draw full barbs.
    for (int i = 0; i < fullBarbs; i++) {
      canvas.drawLine(Offset(0, y), Offset(barbLen, y - spacing), paint);
      y += spacing;
    }

    // Draw half barb.
    if (halfBarbs > 0) {
      canvas.drawLine(Offset(0, y), Offset(barbLen / 2, y - spacing / 2), paint);
    }

    // Dot at center (wind origin).
    canvas.drawCircle(Offset.zero, 2.5, fillPaint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(_WindBarbPainter old) =>
      old.speedKn != speedKn || old.directionDeg != directionDeg;
}
