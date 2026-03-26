import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/providers/route_provider.dart';

/// Draws the active route on the chart: route lines + waypoint markers.
class RouteLayer extends ConsumerWidget {
  final double mapRotation;

  const RouteLayer({super.key, this.mapRotation = 0});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final route = ref.watch(activeRouteProvider);
    final navData = ref.watch(routeNavProvider);

    if (route == null || route.waypoints.isEmpty) {
      return const SizedBox.shrink();
    }

    final wps = route.waypoints;
    final nextIdx = navData?.nextWaypointIndex ?? 0;

    // Route polyline
    final points = wps.map((wp) => wp.position).toList();

    // Completed legs (dimmer)
    final completedPoints = points.sublist(0, (nextIdx + 1).clamp(0, points.length));
    // Remaining legs (bright)
    final remainingPoints = points.sublist(nextIdx.clamp(0, points.length - 1));

    final polylines = <Polyline>[
      if (completedPoints.length >= 2)
        Polyline(
          points: completedPoints,
          color: Colors.blue.withValues(alpha: 0.3),
          strokeWidth: 3,
          isDotted: true,
        ),
      if (remainingPoints.length >= 2)
        Polyline(
          points: remainingPoints,
          color: Colors.blue,
          strokeWidth: 3,
        ),
    ];

    // Waypoint markers
    final markers = <Marker>[];
    for (var i = 0; i < wps.length; i++) {
      final wp = wps[i];
      final isNext = i == nextIdx;
      markers.add(Marker(
        point: wp.position,
        width: 36,
        height: 36,
        child: _WaypointMarker(
          name: wp.name,
          index: i,
          isNext: isNext,
        ),
      ));
    }

    return Stack(
      children: [
        if (polylines.isNotEmpty) PolylineLayer(polylines: polylines),
        MarkerLayer(markers: markers),
      ],
    );
  }
}

class _WaypointMarker extends StatelessWidget {
  final String name;
  final int index;
  final bool isNext;

  const _WaypointMarker({
    required this.name,
    required this.index,
    required this.isNext,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          decoration: BoxDecoration(
            color: isNext
                ? Colors.orange.withValues(alpha: 0.9)
                : Colors.blue.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            name,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Icon(
          Icons.location_on,
          color: isNext ? Colors.orange : Colors.blue,
          size: 20,
        ),
      ],
    );
  }
}
