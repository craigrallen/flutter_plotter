import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../../routing/auto_route_screen.dart';

class AutoRoutePreviewLayer extends ConsumerWidget {
  const AutoRoutePreviewLayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final autoRoute = ref.watch(autoRoutePreviewProvider);
    if (autoRoute == null || autoRoute.waypoints.length < 2) {
      return const SizedBox.shrink();
    }

    final waypoints = autoRoute.waypoints;
    final margins = autoRoute.depthMargins;
    final hasMargins = margins.length == waypoints.length;

    // Build colour-coded polyline segments
    final segments = <_Segment>[];
    for (var i = 0; i < waypoints.length - 1; i++) {
      Color color;
      if (hasMargins) {
        // Use the minimum margin of the two endpoints
        final margin =
            margins[i] < margins[i + 1] ? margins[i] : margins[i + 1];
        if (margin > 2.0) {
          color = Colors.green;
        } else if (margin >= 0.5) {
          color = Colors.yellow.shade700;
        } else {
          color = Colors.red;
        }
      } else {
        color = Colors.blue;
      }
      segments.add(_Segment(waypoints[i], waypoints[i + 1], color));
    }

    // Group consecutive segments by colour to minimise draw calls
    final polylines = <Polyline>[];
    var currentPoints = <LatLng>[segments[0].start];
    var currentColor = segments[0].color;

    for (final seg in segments) {
      if (seg.color == currentColor) {
        currentPoints.add(seg.end);
      } else {
        polylines.add(Polyline(
          points: currentPoints,
          color: currentColor,
          strokeWidth: 4.0,
        ));
        currentPoints = [seg.start, seg.end];
        currentColor = seg.color;
      }
    }
    polylines.add(Polyline(
      points: currentPoints,
      color: currentColor,
      strokeWidth: 4.0,
    ));

    // Find tightest depth margin points for annotation
    final markers = <Marker>[];
    if (hasMargins) {
      // Find indices of minimum margins
      double minMargin = double.infinity;
      int minIdx = 0;
      for (var i = 0; i < margins.length; i++) {
        if (margins[i] < minMargin) {
          minMargin = margins[i];
          minIdx = i;
        }
      }

      if (minMargin < 5.0) {
        markers.add(Marker(
          point: waypoints[minIdx],
          width: 60,
          height: 24,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(
              color: minMargin < 0.5
                  ? Colors.red
                  : minMargin < 2.0
                      ? Colors.orange
                      : Colors.green,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '${minMargin.toStringAsFixed(1)}m',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ));
      }
    }

    return Stack(
      children: [
        PolylineLayer(polylines: polylines),
        if (markers.isNotEmpty) MarkerLayer(markers: markers),
      ],
    );
  }
}

class _Segment {
  final LatLng start;
  final LatLng end;
  final Color color;

  _Segment(this.start, this.end, this.color);
}
