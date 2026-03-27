import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/providers/anchor_provider.dart';

/// Renders the anchor watch circle and icon on the chart.
class AnchorLayer extends ConsumerStatefulWidget {
  const AnchorLayer({super.key});

  @override
  ConsumerState<AnchorLayer> createState() => _AnchorLayerState();
}

class _AnchorLayerState extends ConsumerState<AnchorLayer> {
  bool _flashOn = false;
  Timer? _flashTimer;

  @override
  void dispose() {
    _flashTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final anchor = ref.watch(anchorProvider);

    if (!anchor.isActive || anchor.dropPosition == null) {
      _flashTimer?.cancel();
      _flashTimer = null;
      return const SizedBox.shrink();
    }

    // Start/stop flash timer based on dragging state.
    if (anchor.isDragging && _flashTimer == null) {
      _flashTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
        if (mounted) setState(() => _flashOn = !_flashOn);
      });
    } else if (!anchor.isDragging && _flashTimer != null) {
      _flashTimer?.cancel();
      _flashTimer = null;
      _flashOn = false;
    }

    final circleColor = anchor.isDragging
        ? (_flashOn ? Colors.red : Colors.red.withValues(alpha: 0.3))
        : Colors.green;

    return Stack(
      children: [
        // Scope circle.
        CircleLayer(
          circles: [
            CircleMarker(
              point: anchor.dropPosition!,
              radius: anchor.radiusM,
              useRadiusInMeter: true,
              color: circleColor.withValues(alpha: 0.15),
              borderColor: circleColor,
              borderStrokeWidth: 2,
            ),
          ],
        ),
        // Anchor icon marker.
        MarkerLayer(
          markers: [
            Marker(
              point: anchor.dropPosition!,
              width: 40,
              height: 40,
              child: Icon(
                Icons.anchor,
                color: anchor.isDragging ? Colors.red : Colors.green,
                size: 32,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
