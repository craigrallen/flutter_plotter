import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/tides/tide_station.dart';
import '../../../data/providers/tide_provider.dart';
import '../../tides/tide_panel.dart';

/// Shows markers on the chart for the 5 nearest tide stations.
class TideLayer extends ConsumerWidget {
  const TideLayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stations = ref.watch(nearestTideStationsProvider);

    return stations.when(
      data: (list) {
        if (list.isEmpty) return const SizedBox.shrink();
        final markers = list.map((s) => Marker(
              point: s.position,
              width: 36,
              height: 36,
              child: GestureDetector(
                onTap: () => _openTidePanel(context, s),
                child: const _TideStationIcon(),
              ),
            ));
        return MarkerLayer(markers: markers.toList());
      },
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
    );
  }

  void _openTidePanel(BuildContext context, TideStation station) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => TidePanel(
        stationId: station.id,
        stationName: station.name,
      ),
    ));
  }
}

class _TideStationIcon extends StatelessWidget {
  const _TideStationIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: 0.8),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: const Center(
        child: Icon(Icons.waves, color: Colors.white, size: 18),
      ),
    );
  }
}
