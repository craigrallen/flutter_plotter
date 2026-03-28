import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/floatilla/voyage_logger_service.dart';
import '../../data/providers/voyage_logger_provider.dart';
import '../shared/responsive.dart';

// ── Main screen ────────────────────────────────────────────────────────────

class VoyageLoggerScreen extends ConsumerStatefulWidget {
  const VoyageLoggerScreen({super.key});

  @override
  ConsumerState<VoyageLoggerScreen> createState() => _VoyageLoggerScreenState();
}

class _VoyageLoggerScreenState extends ConsumerState<VoyageLoggerScreen> {
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(voyageLoggerProvider);
    final layout = Responsive.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Voyage Logger'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => _showSettings(context, state.settings),
            tooltip: 'Settings',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () =>
                ref.read(voyageLoggerProvider.notifier).refresh(),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: layout == LayoutSize.expanded
          ? _TabletLayout(state: state)
          : _PhoneLayout(state: state),
    );
  }

  void _showSettings(BuildContext context, VoyageLoggerSettings current) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _SettingsSheet(settings: current),
    );
  }
}

// ── Phone layout (single column) ───────────────────────────────────────────

class _PhoneLayout extends ConsumerWidget {
  final VoyageLoggerState state;
  const _PhoneLayout({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _StatusHeader(state: state),
        const SizedBox(height: 12),
        _ManualOverrideCard(state: state),
        if (state.isVoyageActive) ...[
          const SizedBox(height: 12),
          _CurrentVoyageCard(state: state),
        ],
        const SizedBox(height: 16),
        const _PastVoyagesSection(),
      ],
    );
  }
}

// ── Tablet layout (stats + list side by side) ──────────────────────────────

class _TabletLayout extends ConsumerWidget {
  final VoyageLoggerState state;
  const _TabletLayout({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 340,
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              _StatusHeader(state: state),
              const SizedBox(height: 12),
              _ManualOverrideCard(state: state),
              if (state.isVoyageActive) ...[
                const SizedBox(height: 12),
                _CurrentVoyageCard(state: state),
              ],
            ],
          ),
        ),
        const VerticalDivider(width: 1),
        const Expanded(child: _PastVoyagesSection()),
      ],
    );
  }
}

// ── Status header ──────────────────────────────────────────────────────────

class _StatusHeader extends StatelessWidget {
  final VoyageLoggerState state;
  const _StatusHeader({required this.state});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = state.isVoyageActive;
    final sog = state.currentSog;

    return Card(
      color: active
          ? theme.colorScheme.primaryContainer
          : theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              active ? Icons.directions_boat : Icons.anchor,
              size: 36,
              color: active
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    active ? 'Voyage in progress' : 'Idle',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: active
                          ? theme.colorScheme.onPrimaryContainer
                          : theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (sog != null)
                    Text(
                      'SOG: ${sog.toStringAsFixed(1)} kn',
                      style: theme.textTheme.bodyMedium,
                    ),
                  if (active && state.currentVoyageId != null)
                    _DurationText(
                        voyageId: state.currentVoyageId!),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DurationText extends ConsumerStatefulWidget {
  final String voyageId;
  const _DurationText({required this.voyageId});

  @override
  ConsumerState<_DurationText> createState() => _DurationTextState();
}

class _DurationTextState extends ConsumerState<_DurationText> {
  late final Stream<int> _ticks;

  @override
  void initState() {
    super.initState();
    _ticks = Stream.periodic(const Duration(seconds: 10), (i) => i);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: _ticks,
      builder: (context, _) {
        // During an active voyage it won't be in past voyages yet —
        // fall back to showing generic "ongoing"
        return Text(
          'Ongoing',
          style: Theme.of(context).textTheme.bodySmall,
        );
      },
    );
  }
}

// ── Manual override ────────────────────────────────────────────────────────

class _ManualOverrideCard extends ConsumerWidget {
  final VoyageLoggerState state;
  const _ManualOverrideCard({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(voyageLoggerProvider.notifier);
    final active = state.isVoyageActive;

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            const Icon(Icons.touch_app),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Manual override',
                      style: Theme.of(context).textTheme.titleSmall),
                  Text(
                    active
                        ? 'Stop the current voyage now'
                        : 'Start a voyage manually',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            FilledButton.tonal(
              onPressed: active
                  ? () => notifier.forceEndVoyage()
                  : () => notifier.forceStartVoyage(),
              child: Text(active ? 'End' : 'Start'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Current voyage card ────────────────────────────────────────────────────

class _CurrentVoyageCard extends ConsumerWidget {
  final VoyageLoggerState state;
  const _CurrentVoyageCard({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = state.currentVoyageStats;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Current voyage',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            if (stats != null) ...[
              _StatRow(
                label: 'Distance',
                value: '${stats.distanceNm.toStringAsFixed(2)} nm',
              ),
              _StatRow(
                label: 'Avg SOG',
                value: '${stats.avgSog.toStringAsFixed(1)} kn',
              ),
              _StatRow(
                label: 'Max SOG',
                value: '${stats.maxSog.toStringAsFixed(1)} kn',
              ),
              if (stats.avgTws != null)
                _StatRow(
                  label: 'Avg TWS',
                  value: '${stats.avgTws!.toStringAsFixed(1)} kn',
                ),
            ] else
              Text(
                'Logging data...',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
          ],
        ),
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  final String label;
  final String value;
  const _StatRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    )),
          ),
          Text(value, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}

// ── Past voyages list ──────────────────────────────────────────────────────

class _PastVoyagesSection extends ConsumerWidget {
  const _PastVoyagesSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final voyages = ref.watch(pastVoyagesProvider);

    if (voyages.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.directions_boat_outlined, size: 48),
              SizedBox(height: 8),
              Text('No past voyages yet'),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text('Past voyages',
              style: Theme.of(context).textTheme.titleMedium),
        ),
        ...voyages.map((v) => _VoyageTile(voyage: v)),
      ],
    );
  }
}

class _VoyageTile extends ConsumerWidget {
  final VoyageRecord voyage;
  const _VoyageTile({required this.voyage});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dateFmt = DateFormat('d MMM yyyy');
    final start = voyage.startTime;
    final end = voyage.endTime;
    final duration = end?.difference(start);

    return ListTile(
      leading: const Icon(Icons.directions_boat_outlined),
      title: Text(dateFmt.format(start)),
      subtitle: Text(
        [
          if (duration != null) _formatDuration(duration),
        ].join(' · '),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _openDetail(context, ref, voyage),
    );
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }

  Future<void> _openDetail(
      BuildContext context, WidgetRef ref, VoyageRecord voyage) async {
    final entries =
        await ref.read(voyageLoggerProvider.notifier).entriesForVoyage(
              voyage.voyageId,
            );
    if (!context.mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _VoyageDetailScreen(voyage: voyage, entries: entries),
      ),
    );
  }
}

// ── Voyage detail ──────────────────────────────────────────────────────────

class _VoyageDetailScreen extends ConsumerWidget {
  final VoyageRecord voyage;
  final List<VoyageLogEntry> entries;

  const _VoyageDetailScreen({
    required this.voyage,
    required this.entries,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref
        .read(voyageLoggerProvider.notifier)
        .statsForVoyage(voyage, entries);
    final trackPoints = entries
        .where((e) => e.lat != null && e.lng != null)
        .map((e) => LatLng(e.lat!, e.lng!))
        .toList();
    final layout = Responsive.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(DateFormat('d MMM yyyy').format(voyage.startTime)),
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: 'Export GPX',
            onPressed: () => _exportGpx(context),
          ),
        ],
      ),
      body: layout == LayoutSize.expanded
          ? _TabletDetailLayout(
              stats: stats, trackPoints: trackPoints, entries: entries)
          : _PhoneDetailLayout(
              stats: stats, trackPoints: trackPoints, entries: entries),
    );
  }

  Future<void> _exportGpx(BuildContext context) async {
    final gpx = _buildGpx();
    await Share.share(gpx, subject: 'Voyage ${voyage.voyageId}.gpx');
  }

  String _buildGpx() {
    final buf = StringBuffer();
    buf.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    buf.writeln(
        '<gpx version="1.1" creator="Floatilla" xmlns="http://www.topografix.com/GPX/1/1">');
    buf.writeln('<trk><name>Voyage ${voyage.voyageId}</name><trkseg>');
    for (final e in entries) {
      if (e.lat == null || e.lng == null) continue;
      buf.writeln(
          '<trkpt lat="${e.lat}" lon="${e.lng}"><time>${e.timestamp.toUtc().toIso8601String()}</time></trkpt>');
    }
    buf.writeln('</trkseg></trk></gpx>');
    return buf.toString();
  }
}

class _PhoneDetailLayout extends StatelessWidget {
  final VoyageStats stats;
  final List<LatLng> trackPoints;
  final List<VoyageLogEntry> entries;

  const _PhoneDetailLayout({
    required this.stats,
    required this.trackPoints,
    required this.entries,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (trackPoints.length > 1)
          SizedBox(
            height: 240,
            child: _TrackMap(points: trackPoints),
          ),
        const SizedBox(height: 12),
        _StatsPanel(stats: stats),
      ],
    );
  }
}

class _TabletDetailLayout extends StatelessWidget {
  final VoyageStats stats;
  final List<LatLng> trackPoints;
  final List<VoyageLogEntry> entries;

  const _TabletDetailLayout({
    required this.stats,
    required this.trackPoints,
    required this.entries,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (trackPoints.length > 1)
          Expanded(child: _TrackMap(points: trackPoints)),
        SizedBox(
          width: 280,
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [_StatsPanel(stats: stats)],
          ),
        ),
      ],
    );
  }
}

// ── Track map ──────────────────────────────────────────────────────────────

class _TrackMap extends StatelessWidget {
  final List<LatLng> points;
  const _TrackMap({required this.points});

  @override
  Widget build(BuildContext context) {
    final bounds = LatLngBounds.fromPoints(points);
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: FlutterMap(
        options: MapOptions(
          initialCameraFit: CameraFit.bounds(
            bounds: bounds,
            padding: const EdgeInsets.all(32),
          ),
          interactionOptions: const InteractionOptions(
            flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag,
          ),
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.floatilla.app',
          ),
          PolylineLayer(
            polylines: [
              Polyline(
                points: points,
                color: Theme.of(context).colorScheme.primary,
                strokeWidth: 3,
              ),
            ],
          ),
          MarkerLayer(
            markers: [
              if (points.isNotEmpty)
                Marker(
                  point: points.first,
                  width: 20,
                  height: 20,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                      border:
                          Border.all(color: Colors.white, width: 2),
                    ),
                  ),
                ),
              if (points.length > 1)
                Marker(
                  point: points.last,
                  width: 20,
                  height: 20,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                      border:
                          Border.all(color: Colors.white, width: 2),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Stats panel ────────────────────────────────────────────────────────────

class _StatsPanel extends StatelessWidget {
  final VoyageStats stats;
  const _StatsPanel({required this.stats});

  @override
  Widget build(BuildContext context) {
    final duration = stats.duration;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Voyage stats',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            _StatRow(
              label: 'Distance',
              value: '${stats.distanceNm.toStringAsFixed(2)} nm',
            ),
            _StatRow(
              label: 'Duration',
              value: _fmt(duration),
            ),
            _StatRow(
              label: 'Avg SOG',
              value: '${stats.avgSog.toStringAsFixed(1)} kn',
            ),
            _StatRow(
              label: 'Max SOG',
              value: '${stats.maxSog.toStringAsFixed(1)} kn',
            ),
            if (stats.avgTws != null)
              _StatRow(
                label: 'Avg TWS',
                value: '${stats.avgTws!.toStringAsFixed(1)} kn',
              ),
            _StatRow(
              label: 'Log entries',
              value: stats.entryCount.toString(),
            ),
          ],
        ),
      ),
    );
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }
}

// ── Settings sheet ─────────────────────────────────────────────────────────

class _SettingsSheet extends ConsumerStatefulWidget {
  final VoyageLoggerSettings settings;
  const _SettingsSheet({required this.settings});

  @override
  ConsumerState<_SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends ConsumerState<_SettingsSheet> {
  late LogInterval _interval;
  late DetectionSensitivity _sensitivity;
  late bool _autoDetect;

  @override
  void initState() {
    super.initState();
    _interval = widget.settings.interval;
    _sensitivity = widget.settings.sensitivity;
    _autoDetect = widget.settings.autoDetect;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 16,
        right: 16,
        top: 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Voyage logger settings',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          SwitchListTile(
            title: const Text('Auto-detect voyages'),
            subtitle: const Text(
                'Start/stop based on SOG thresholds automatically'),
            value: _autoDetect,
            onChanged: (v) => setState(() => _autoDetect = v),
          ),
          const Divider(),
          ListTile(
            title: const Text('Log interval'),
            trailing: DropdownButton<LogInterval>(
              value: _interval,
              onChanged: (v) => setState(() => _interval = v!),
              items: const [
                DropdownMenuItem(
                    value: LogInterval.thirtySeconds, child: Text('30 s')),
                DropdownMenuItem(
                    value: LogInterval.oneMinute, child: Text('1 min')),
                DropdownMenuItem(
                    value: LogInterval.fiveMinutes, child: Text('5 min')),
              ],
            ),
          ),
          ListTile(
            title: const Text('Detection sensitivity'),
            trailing: DropdownButton<DetectionSensitivity>(
              value: _sensitivity,
              onChanged: (v) => setState(() => _sensitivity = v!),
              items: const [
                DropdownMenuItem(
                    value: DetectionSensitivity.slow, child: Text('Slow')),
                DropdownMenuItem(
                    value: DetectionSensitivity.normal, child: Text('Normal')),
                DropdownMenuItem(
                    value: DetectionSensitivity.fast, child: Text('Fast')),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () {
                  ref.read(voyageLoggerProvider.notifier).updateSettings(
                        VoyageLoggerSettings(
                          interval: _interval,
                          sensitivity: _sensitivity,
                          autoDetect: _autoDetect,
                        ),
                      );
                  Navigator.pop(context);
                },
                child: const Text('Save'),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
