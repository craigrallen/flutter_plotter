import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/waypoint.dart';
import '../../data/providers/route_provider.dart';

class RouteEditorScreen extends ConsumerStatefulWidget {
  final int routeId;

  const RouteEditorScreen({super.key, required this.routeId});

  @override
  ConsumerState<RouteEditorScreen> createState() => _RouteEditorScreenState();
}

class _RouteEditorScreenState extends ConsumerState<RouteEditorScreen> {
  late List<Waypoint> _routeWaypoints;
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded) {
      final routes = ref.read(routesProvider);
      final route = routes.firstWhere((r) => r.id == widget.routeId);
      _routeWaypoints = List.from(route.waypoints);
      _loaded = true;
    }
  }

  void _save() {
    final routes = ref.read(routesProvider);
    final route = routes.firstWhere((r) => r.id == widget.routeId);
    ref.read(routesProvider.notifier).update(
          route.copyWith(waypoints: _routeWaypoints),
        );
    Navigator.pop(context);
  }

  void _addWaypoint() {
    final allWaypoints = ref.read(waypointsProvider);
    // Filter out waypoints already in the route
    final available = allWaypoints
        .where((wp) => !_routeWaypoints.any((rw) => rw.id == wp.id))
        .toList();

    if (available.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No waypoints available. Long-press on the chart to create some.'),
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Add Waypoint'),
        children: available.map((wp) {
          return SimpleDialogOption(
            onPressed: () {
              setState(() => _routeWaypoints.add(wp));
              Navigator.pop(ctx);
            },
            child: Text(
              '${wp.name} (${wp.position.latitude.toStringAsFixed(4)}, '
              '${wp.position.longitude.toStringAsFixed(4)})',
            ),
          );
        }).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Route'),
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: _save,
          ),
        ],
      ),
      body: _routeWaypoints.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('No waypoints in this route.'),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _addWaypoint,
                    icon: const Icon(Icons.add),
                    label: const Text('Add Waypoint'),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                Expanded(
                  child: ReorderableListView.builder(
                    itemCount: _routeWaypoints.length,
                    onReorder: (oldIndex, newIndex) {
                      setState(() {
                        if (newIndex > oldIndex) newIndex--;
                        final wp = _routeWaypoints.removeAt(oldIndex);
                        _routeWaypoints.insert(newIndex, wp);
                      });
                    },
                    itemBuilder: (ctx, index) {
                      final wp = _routeWaypoints[index];
                      return ListTile(
                        key: ValueKey(wp.id),
                        leading: CircleAvatar(child: Text('${index + 1}')),
                        title: Text(wp.name),
                        subtitle: Text(
                          '${wp.position.latitude.toStringAsFixed(4)}, '
                          '${wp.position.longitude.toStringAsFixed(4)}',
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.remove_circle_outline),
                          onPressed: () {
                            setState(() => _routeWaypoints.removeAt(index));
                          },
                        ),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: FilledButton.icon(
                    onPressed: _addWaypoint,
                    icon: const Icon(Icons.add),
                    label: const Text('Add Waypoint'),
                  ),
                ),
              ],
            ),
    );
  }
}
