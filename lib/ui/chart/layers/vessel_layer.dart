import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

    return MarkerLayer(
      markers: [
        Marker(
          point: pos,
          width: 40,
          height: 40,
          child: Transform.rotate(
            // Rotate arrow by COG, compensate for map rotation so icon
            // always points in the correct geographic direction.
            angle: cogRad - mapRotation * pi / 180,
            child: const _VesselArrow(),
          ),
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
    final path = Path()
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
