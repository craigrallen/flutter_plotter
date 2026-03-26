import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/nav/geo.dart';
import '../../../data/providers/vessel_provider.dart';

/// Renders the own-vessel icon on the chart.
/// Arrow rotates with COG, positioned at current GPS fix.
class VesselLayer extends ConsumerWidget {
  /// Extra rotation applied by course-up mode (the map rotation angle).
  final double mapRotation;

  const VesselLayer({super.key, this.mapRotation = 0});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vessel = ref.watch(vesselProvider);
    final pos = vessel.position;
    if (pos == null) return const SizedBox.shrink();

    final cogRad = (vessel.cog ?? 0) * pi / 180;

    // Compute accuracy ring radius in pixels.
    final accuracy = vessel.gpsAccuracy;
    double? ringRadiusPx;
    if (accuracy != null && accuracy > 0) {
      final camera = MapCamera.of(context);
      final centre = camera.project(pos);
      final offset = destinationPoint(pos, 90, accuracy);
      final edgePx = camera.project(offset);
      ringRadiusPx = (edgePx.x - centre.x).abs();
      if (ringRadiusPx < 20) ringRadiusPx = null; // too small to bother
    }

    return Stack(
      children: [
        if (ringRadiusPx != null)
          CircleLayer(
            circles: [
              CircleMarker(
                point: pos,
                radius: ringRadiusPx,
                useRadiusInMeter: false,
                color: Colors.blue.withValues(alpha: 0.1),
                borderColor: Colors.blue.withValues(alpha: 0.4),
                borderStrokeWidth: 1,
              ),
            ],
          ),
        MarkerLayer(
          markers: [
            Marker(
              point: pos,
              width: 40,
              height: 40,
              child: Transform.rotate(
                angle: cogRad - mapRotation * pi / 180,
                child: const _VesselArrow(),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _VesselArrow extends StatelessWidget {
  const _VesselArrow();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(40, 40),
      painter: _ArrowPainter(),
    );
  }
}

class _ArrowPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.blue
      ..style = PaintingStyle.fill;

    final outline = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final cx = size.width / 2;
    final cy = size.height / 2;

    // Arrow pointing up (north) — tip at top, base at bottom.
    final path = ui.Path()
      ..moveTo(cx, cy - 16) // tip
      ..lineTo(cx + 10, cy + 12) // bottom right
      ..lineTo(cx, cy + 6) // notch
      ..lineTo(cx - 10, cy + 12) // bottom left
      ..close();

    canvas.drawPath(path, paint);
    canvas.drawPath(path, outline);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
