import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../data/providers/ais_history_provider.dart';
import '../../data/providers/chart_tile_provider.dart';
import '../../data/providers/vessel_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Colour palette — distinct hues for up to 12 simultaneously tracked vessels.
// ─────────────────────────────────────────────────────────────────────────────

const _kTrailPalette = <Color>[
  Color(0xFFE53935), // red
  Color(0xFF1E88E5), // blue
  Color(0xFF43A047), // green
  Color(0xFFFF9800), // orange
  Color(0xFF8E24AA), // purple
  Color(0xFF00ACC1), // cyan
  Color(0xFFFFB300), // amber
  Color(0xFF6D4C41), // brown
  Color(0xFF00897B), // teal
  Color(0xFF5E35B1), // deep purple
  Color(0xFFD81B60), // pink
  Color(0xFF039BE5), // light blue
];

Color _colorForMmsi(int mmsi) =>
    _kTrailPalette[mmsi % _kTrailPalette.length];

// ─────────────────────────────────────────────────────────────────────────────
// Screen
// ─────────────────────────────────────────────────────────────────────────────

class AisHistoryTrailScreen extends ConsumerStatefulWidget {
  const AisHistoryTrailScreen({super.key});

  @override
  ConsumerState<AisHistoryTrailScreen> createState() =>
      _AisHistoryTrailScreenState();
}

class _AisHistoryTrailScreenState
    extends ConsumerState<AisHistoryTrailScreen> {
  final _mapController = MapController();
  bool _showMapView = true;
  int? _selectedMmsi;

  @override
  Widget build(BuildContext context) {
    final histState = ref.watch(aisHistoryProvider);
    final vessel = ref.watch(vesselProvider);
    final trails = histState.visibleTrails;

    return Scaffold(
      appBar: AppBar(
        title: const Text('AIS History Trails'),
        actions: [
          // Window selector
          PopupMenuButton<int>(
            tooltip: 'Time window',
            icon: const Icon(Icons.schedule),
            initialValue: histState.windowHours,
            itemBuilder: (_) => const [
              PopupMenuItem(value: 1, child: Text('Last 1 hour')),
              PopupMenuItem(value: 2, child: Text('Last 2 hours')),
              PopupMenuItem(value: 6, child: Text('Last 6 hours')),
              PopupMenuItem(value: 12, child: Text('Last 12 hours')),
              PopupMenuItem(value: 24, child: Text('Last 24 hours')),
            ],
            onSelected: (h) =>
                ref.read(aisHistoryProvider.notifier).setWindowHours(h),
          ),
          // Toggle map/list view
          IconButton(
            tooltip: _showMapView ? 'List view' : 'Map view',
            icon:
                Icon(_showMapView ? Icons.list : Icons.map),
            onPressed: () => setState(() => _showMapView = !_showMapView),
          ),
          // Clear all
          IconButton(
            tooltip: 'Clear all trails',
            icon: const Icon(Icons.delete_sweep),
            onPressed: trails.isEmpty
                ? null
                : () => _confirmClearAll(context),
          ),
        ],
      ),
      body: trails.isEmpty
          ? _buildEmptyState(histState.windowHours)
          : _showMapView
              ? _buildMapView(trails, vessel.position)
              : _buildListView(trails, histState.windowHours),
    );
  }

  // ── Empty state ────────────────────────────────────────────────────────────

  Widget _buildEmptyState(int windowHours) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history_toggle_off,
                size: 64,
                color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            Text(
              'No AIS history yet',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Vessel tracks will appear here once AIS targets have moved'
              ' enough to record positions.\n\n'
              'Currently showing last $windowHours hour${windowHours == 1 ? '' : 's'}.'
              ' Adjust the time window using the clock icon.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color:
                        Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Map view ───────────────────────────────────────────────────────────────

  Widget _buildMapView(
      List<AisVesselTrail> trails, LatLng? vesselPosition) {
    final center = vesselPosition ?? const LatLng(57.7089, 11.9746);

    final polylines = <Polyline>[];
    final markers = <Marker>[];

    for (final trail in trails) {
      final color = _colorForMmsi(trail.mmsi);
      final isSelected = _selectedMmsi == trail.mmsi;

      // Trail polyline — fade older segments using alpha gradient.
      final pts = trail.points.map((p) => p.position).toList();
      polylines.add(Polyline(
        points: pts,
        color: isSelected
            ? color
            : color.withValues(alpha: 0.6),
        strokeWidth: isSelected ? 4.0 : 2.5,
      ));

      // Head-of-trail marker (latest position).
      final latest = trail.points.last;
      markers.add(Marker(
        point: latest.position,
        width: 44,
        height: 44,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() {
              _selectedMmsi =
                  _selectedMmsi == trail.mmsi ? null : trail.mmsi;
            });
            if (_selectedMmsi != null) {
              _showTrailSheet(trail);
            }
          },
          child: Center(
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: color.withValues(alpha: 0.5),
                          blurRadius: 8,
                          spreadRadius: 2,
                        )
                      ]
                    : null,
              ),
              child: isSelected
                  ? const Icon(Icons.sailing,
                      size: 14, color: Colors.white)
                  : null,
            ),
          ),
        ),
      ));

      // Tail-of-trail dot (oldest point).
      if (trail.points.length > 1) {
        final oldest = trail.points.first;
        markers.add(Marker(
          point: oldest.position,
          width: 12,
          height: 12,
          child: Container(
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.4),
              shape: BoxShape.circle,
              border: Border.all(
                  color: color.withValues(alpha: 0.6), width: 1),
            ),
          ),
        ));
      }
    }

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: center,
            initialZoom: 11,
            onTap: (pos, hasGesture) => setState(() => _selectedMmsi = null),
          ),
          children: [
            OsmBaseProvider().tileLayer,
            if (polylines.isNotEmpty)
              PolylineLayer(polylines: polylines),
            MarkerLayer(markers: markers),
          ],
        ),
        // Legend overlay
        Positioned(
          bottom: 16,
          left: 12,
          child: _TrailLegend(trails: trails, selectedMmsi: _selectedMmsi),
        ),
      ],
    );
  }

  void _showTrailSheet(AisVesselTrail trail) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        minChildSize: 0.3,
        maxChildSize: 0.7,
        initialChildSize: 0.45,
        builder: (ctx, sc) =>
            _TrailDetailSheet(trail: trail, scrollController: sc),
      ),
    );
  }

  // ── List view ─────────────────────────────────────────────────────────────

  Widget _buildListView(
      List<AisVesselTrail> trails, int windowHours) {
    // Sort by most recent activity descending.
    final sorted = [...trails]..sort((a, b) =>
        b.points.last.timestamp.compareTo(a.points.last.timestamp));

    return ListView.separated(
      itemCount: sorted.length,
      separatorBuilder: (ctx, idx) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final trail = sorted[index];
        final color = _colorForMmsi(trail.mmsi);
        final latest = trail.points.last;
        final oldest = trail.points.first;
        final durationMin = latest.timestamp
            .difference(oldest.timestamp)
            .inMinutes;
        final distNm = _totalDistanceNm(trail);

        return ListTile(
          leading: CircleAvatar(
            backgroundColor: color,
            child: Text(
              trail.displayName.substring(0, 1).toUpperCase(),
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
          title: Text(trail.displayName),
          subtitle: Text(
            '${trail.points.length} pts · '
            '${durationMin}min · '
            '${distNm.toStringAsFixed(1)} nm · '
            'Last ${latest.sogKnots.toStringAsFixed(1)} kn',
          ),
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Clear trail',
            onPressed: () =>
                ref.read(aisHistoryProvider.notifier).clearTrail(trail.mmsi),
          ),
          onTap: () {
            setState(() {
              _showMapView = true;
              _selectedMmsi = trail.mmsi;
            });
            // Pan map to latest position after frame.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _mapController.move(latest.position, 12);
            });
          },
        );
      },
    );
  }

  double _totalDistanceNm(AisVesselTrail trail) {
    if (trail.points.length < 2) return 0;
    double total = 0;
    for (int i = 1; i < trail.points.length; i++) {
      final d = const Distance().as(
        LengthUnit.Meter,
        trail.points[i - 1].position,
        trail.points[i].position,
      );
      total += d;
    }
    return total / 1852;
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  Future<void> _confirmClearAll(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear all trails?'),
        content: const Text(
            'This will delete all accumulated AIS history for this session.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Clear')),
        ],
      ),
    );
    if (ok == true) {
      ref.read(aisHistoryProvider.notifier).clearAll();
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Legend widget
// ─────────────────────────────────────────────────────────────────────────────

class _TrailLegend extends StatelessWidget {
  final List<AisVesselTrail> trails;
  final int? selectedMmsi;

  const _TrailLegend({required this.trails, this.selectedMmsi});

  @override
  Widget build(BuildContext context) {
    if (trails.isEmpty) return const SizedBox.shrink();

    // Show at most 6 in the legend; rest indicated by a count.
    final shown = trails.length <= 6 ? trails : trails.sublist(0, 6);
    final extra = trails.length - shown.length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...shown.map((t) => _LegendRow(trail: t, selected: t.mmsi == selectedMmsi)),
          if (extra > 0)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                '+$extra more',
                style: const TextStyle(color: Colors.white70, fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }
}

class _LegendRow extends StatelessWidget {
  final AisVesselTrail trail;
  final bool selected;

  const _LegendRow({required this.trail, this.selected = false});

  @override
  Widget build(BuildContext context) {
    final color = _colorForMmsi(trail.mmsi);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 18,
            height: 4,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            trail.displayName.length > 14
                ? '${trail.displayName.substring(0, 13)}…'
                : trail.displayName,
            style: TextStyle(
              color: selected ? Colors.white : Colors.white70,
              fontSize: 12,
              fontWeight:
                  selected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Trail detail bottom sheet
// ─────────────────────────────────────────────────────────────────────────────

class _TrailDetailSheet extends StatelessWidget {
  final AisVesselTrail trail;
  final ScrollController scrollController;

  const _TrailDetailSheet(
      {required this.trail, required this.scrollController});

  @override
  Widget build(BuildContext context) {
    final latest = trail.points.last;
    final oldest = trail.points.first;
    final durationMin =
        latest.timestamp.difference(oldest.timestamp).inMinutes;
    final durationHours = durationMin / 60;

    // Compute total distance.
    double totalMetres = 0;
    for (int i = 1; i < trail.points.length; i++) {
      totalMetres += const Distance().as(
        LengthUnit.Meter,
        trail.points[i - 1].position,
        trail.points[i].position,
      );
    }
    final totalNm = totalMetres / 1852;
    final avgSog = durationMin > 0
        ? (totalNm / (durationMin / 60))
        : latest.sogKnots;

    // Speed over trail (simple max).
    final maxSog = trail.points
        .map((p) => p.sogKnots)
        .fold<double>(0, math.max);

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.all(16),
      children: [
        // Drag handle
        Center(
          child: Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.grey.shade400,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        Row(
          children: [
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: _colorForMmsi(trail.mmsi),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                trail.displayName,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _row('MMSI', trail.mmsi.toString()),
        _row('Track points', trail.points.length.toString()),
        _row(
          'Duration',
          durationHours >= 1
              ? '${durationHours.toStringAsFixed(1)} h'
              : '$durationMin min',
        ),
        _row('Total distance', '${totalNm.toStringAsFixed(2)} nm'),
        _row('Avg SOG', '${avgSog.toStringAsFixed(1)} kn'),
        _row('Max SOG', '${maxSog.toStringAsFixed(1)} kn'),
        _row(
          'Latest COG',
          '${latest.cogDegrees.toStringAsFixed(1)}°',
        ),
        const Divider(),
        _row(
          'First fix',
          _formatTime(oldest.timestamp),
        ),
        _row(
          'Latest fix',
          _formatTime(latest.timestamp),
        ),
        const SizedBox(height: 16),
        // Mini track summary — show last 5 positions.
        Text(
          'Recent positions (newest first)',
          style: Theme.of(context).textTheme.labelMedium,
        ),
        const SizedBox(height: 8),
        ...trail.points.reversed.take(5).map((p) => _positionRow(p)),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _row(String label, String value) {
    return SizedBox(
      height: 44,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(fontWeight: FontWeight.w500)),
          Text(value),
        ],
      ),
    );
  }

  Widget _positionRow(AisTrailPoint p) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${p.position.latitude.toStringAsFixed(4)}, '
              '${p.position.longitude.toStringAsFixed(4)}',
              style: const TextStyle(fontSize: 12),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${p.sogKnots.toStringAsFixed(1)} kn',
            style: const TextStyle(fontSize: 12),
          ),
          const SizedBox(width: 8),
          Text(
            _formatTime(p.timestamp),
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}
