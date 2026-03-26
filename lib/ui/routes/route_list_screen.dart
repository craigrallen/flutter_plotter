import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/gpx/gpx_io.dart';
import '../../data/models/route_model.dart';
import '../../data/models/waypoint.dart';
import '../../data/providers/route_provider.dart';
import 'route_editor_screen.dart';

class RouteListScreen extends ConsumerWidget {
  const RouteListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final routes = ref.watch(routesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Routes'),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_download),
            tooltip: 'Import GPX',
            onPressed: () => _importGpx(context, ref),
          ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _createRoute(context, ref),
          ),
        ],
      ),
      body: routes.isEmpty
          ? const Center(
              child: Text(
                'No routes yet.\nLong-press on the chart to add waypoints.',
                textAlign: TextAlign.center,
              ),
            )
          : ListView.builder(
              itemCount: routes.length,
              itemBuilder: (ctx, index) {
                final route = routes[index];
                return _RouteListTile(route: route);
              },
            ),
    );
  }

  void _createRoute(BuildContext context, WidgetRef ref) {
    final nameController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Route'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(labelText: 'Route name'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final name = nameController.text.trim();
              if (name.isEmpty) return;
              Navigator.pop(ctx);
              _openEditor(context, ref, name);
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _openEditor(BuildContext context, WidgetRef ref, String name) async {
    final route = await ref.read(routesProvider.notifier).add(RouteModel(
          name: name,
          createdAt: DateTime.now(),
        ));
    if (context.mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => RouteEditorScreen(routeId: route.id!),
        ),
      );
    }
  }

  Future<void> _importGpx(BuildContext context, WidgetRef ref) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['gpx'],
    );
    if (result == null || result.files.isEmpty) return;

    final path = result.files.first.path;
    if (path == null) return;

    final gpxStr = await File(path).readAsString();

    // Import standalone waypoints
    final wps = GpxParser.parseWaypoints(gpxStr);
    for (final wp in wps) {
      await ref.read(waypointsProvider.notifier).add(wp);
    }

    // Import routes
    final parsedRoutes = GpxParser.parseRoutes(gpxStr);
    final parsedTracks = GpxParser.parseTracks(gpxStr);

    for (final parsed in [...parsedRoutes, ...parsedTracks]) {
      // First, save each waypoint to the DB
      final savedWps = <Waypoint>[];
      for (final wp in parsed.waypoints) {
        final saved = await ref.read(waypointsProvider.notifier).add(wp);
        savedWps.add(saved);
      }
      // Then create the route with saved waypoints
      await ref.read(routesProvider.notifier).add(RouteModel(
            name: parsed.name,
            waypoints: savedWps,
            createdAt: DateTime.now(),
          ));
    }

    if (context.mounted) {
      final total = parsedRoutes.length + parsedTracks.length;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Imported ${wps.length} waypoints, $total routes',
          ),
        ),
      );
    }
  }
}

class _RouteListTile extends ConsumerWidget {
  final RouteModel route;

  const _RouteListTile({required this.route});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      leading: Icon(
        route.isActive ? Icons.navigation : Icons.route,
        color: route.isActive ? Colors.orange : null,
      ),
      title: Text(route.name),
      subtitle: Text(
        '${route.waypoints.length} waypoints'
        '${route.isActive ? ' — ACTIVE' : ''}',
      ),
      trailing: PopupMenuButton<String>(
        onSelected: (action) async {
          switch (action) {
            case 'activate':
              ref.read(routesProvider.notifier).setActive(route.id!);
              ref.read(nextWaypointIndexProvider.notifier).state = 0;
            case 'deactivate':
              ref.read(routesProvider.notifier).deactivateAll();
            case 'edit':
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => RouteEditorScreen(routeId: route.id!),
                ),
              );
            case 'export':
              _exportGpx(context, route);
            case 'delete':
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Delete Route?'),
                  content: Text('Delete "${route.name}"?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Delete'),
                    ),
                  ],
                ),
              );
              if (confirm == true) {
                ref.read(routesProvider.notifier).remove(route.id!);
              }
          }
        },
        itemBuilder: (_) => [
          if (!route.isActive)
            const PopupMenuItem(value: 'activate', child: Text('Activate')),
          if (route.isActive)
            const PopupMenuItem(value: 'deactivate', child: Text('Deactivate')),
          const PopupMenuItem(value: 'edit', child: Text('Edit')),
          if (route.waypoints.isNotEmpty)
            const PopupMenuItem(value: 'export', child: Text('Export GPX')),
          const PopupMenuItem(value: 'delete', child: Text('Delete')),
        ],
      ),
    );
  }

  Future<void> _exportGpx(BuildContext context, RouteModel route) async {
    final filePath = await GpxExporter.exportToFile(route);
    await Share.shareXFiles([XFile(filePath)]);
  }
}
