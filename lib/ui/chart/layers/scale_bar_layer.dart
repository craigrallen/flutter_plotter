import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import '../../../core/nav/geo.dart';

/// Displays a scale bar in the bottom-left of the map.
class ScaleBarLayer extends StatelessWidget {
  final MapCamera camera;

  const ScaleBarLayer({super.key, required this.camera});

  @override
  Widget build(BuildContext context) {
    final scaleInfo = _computeScale();
    if (scaleInfo == null) return const SizedBox.shrink();

    return Positioned(
      left: 16,
      bottom: 16,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: scaleInfo.widthPx,
              height: 3,
              color: Colors.black87,
            ),
            const SizedBox(height: 2),
            Text(
              scaleInfo.label,
              style: const TextStyle(fontSize: 10, color: Colors.black87),
            ),
          ],
        ),
      ),
    );
  }

  _ScaleInfo? _computeScale() {
    final centre = camera.center;
    // Measure how many metres 100 px represents at current zoom.
    final pixelOrigin = camera.project(centre);
    final rightPoint = camera.unproject(
      Point<double>(pixelOrigin.x + 100, pixelOrigin.y),
    );
    final metresPer100px = haversineDistanceM(centre, rightPoint);
    if (metresPer100px <= 0) return null;

    // Pick a nice round distance.
    const niceDistances = [
      5000000, 2000000, 1000000, 500000, 200000, 100000, 50000, 20000, 10000, //
      5000, 2000, 1000, 500, 200, 100, 50, 20, 10, 5, 2, 1,
    ];

    for (final d in niceDistances) {
      final px = d / metresPer100px * 100;
      if (px >= 50 && px <= 200) {
        return _ScaleInfo(
          widthPx: px,
          label: d >= 1000 ? '${d ~/ 1000} km' : '$d m',
        );
      }
    }
    return null;
  }
}

class _ScaleInfo {
  final double widthPx;
  final String label;
  const _ScaleInfo({required this.widthPx, required this.label});
}
