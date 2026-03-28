import 'dart:math' as math;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import '../../core/floatilla/floatilla_service.dart';
import '../../core/floatilla/track_comparison_service.dart';

// ── Track color palette (4 slots) ────────────────────────────────────────────

const _kTrackColors = <Color>[
  Color(0xFF1E88E5), // blue (primary)
  Color(0xFFE53935), // red
  Color(0xFF43A047), // green
  Color(0xFFFF9800), // orange
];

// ── State notifier ────────────────────────────────────────────────────────────

class _ComparisonState {
  final List<ComparisonTrack> tracks;
  final bool timeAligned;
  final bool speedColorMode;
  final bool loading;
  final String? error;

  const _ComparisonState({
    this.tracks = const [],
    this.timeAligned = false,
    this.speedColorMode = false,
    this.loading = false,
    this.error,
  });

  _ComparisonState copyWith({
    List<ComparisonTrack>? tracks,
    bool? timeAligned,
    bool? speedColorMode,
    bool? loading,
    String? error,
  }) {
    return _ComparisonState(
      tracks: tracks ?? this.tracks,
      timeAligned: timeAligned ?? this.timeAligned,
      speedColorMode: speedColorMode ?? this.speedColorMode,
      loading: loading ?? this.loading,
      error: error,
    );
  }
}

class _ComparisonNotifier extends StateNotifier<_ComparisonState> {
  _ComparisonNotifier() : super(const _ComparisonState());

  final _svc = TrackComparisonService.instance;

  List<ComparisonTrack> get _displayTracks =>
      state.timeAligned ? _svc.alignByTime(state.tracks) : state.tracks;

  void toggleTimeAlign() {
    state = state.copyWith(timeAligned: !state.timeAligned);
  }

  void toggleSpeedColor() {
    state = state.copyWith(speedColorMode: !state.speedColorMode);
  }

  void toggleTrack(int index) {
    final updated = List<ComparisonTrack>.from(state.tracks);
    updated[index] = ComparisonTrack(
      id: updated[index].id,
      label: updated[index].label,
      username: updated[index].username,
      source: updated[index].source,
      points: updated[index].points,
      startTime: updated[index].startTime,
      endTime: updated[index].endTime,
      distanceNm: updated[index].distanceNm,
      enabled: !updated[index].enabled,
    );
    state = state.copyWith(tracks: updated);
  }

  void removeTrack(int index) {
    final updated = List<ComparisonTrack>.from(state.tracks)..removeAt(index);
    state = state.copyWith(tracks: updated);
  }

  bool get canAddMore => state.tracks.length < 4;

  Future<void> addLocalTrack(LocalVoyageSummary voyage, String vesselName) async {
    if (!canAddMore) return;
    final track = ComparisonTrack(
      id: voyage.voyageId,
      label: vesselName,
      source: 'local',
      points: voyage.points,
      startTime: voyage.startTime,
      endTime: voyage.endTime,
      distanceNm: voyage.distanceNm,
    );
    state = state.copyWith(tracks: [...state.tracks, track]);
  }

  Future<void> addFriendTracks(String username) async {
    if (!canAddMore) return;
    state = state.copyWith(loading: true, error: null);
    try {
      final tracks = await _svc.loadFriendTracks(username);
      if (tracks.isEmpty) {
        state = state.copyWith(
          loading: false,
          error: 'No tracks found for $username (friend relationship required)',
        );
        return;
      }
      // Take only one (most recent) to not overflow the 4-slot limit
      final toAdd = tracks.take(canAddMore ? 4 - state.tracks.length : 0);
      state = state.copyWith(
        tracks: [...state.tracks, ...toAdd],
        loading: false,
      );
    } catch (e) {
      state = state.copyWith(loading: false, error: 'Failed to load tracks: $e');
    }
  }

  Future<void> addGpxFile() async {
    if (!canAddMore) return;
    state = state.copyWith(loading: true, error: null);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['gpx'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) {
        state = state.copyWith(loading: false);
        return;
      }
      final file = result.files.first;
      final track = await _svc.loadGpxFromBytes(
        file.bytes!.toList(),
        file.name,
      );
      if (track == null) {
        state = state.copyWith(
          loading: false,
          error: 'Could not parse GPX file',
        );
        return;
      }
      state = state.copyWith(
        tracks: [...state.tracks, track],
        loading: false,
      );
    } catch (e) {
      state = state.copyWith(loading: false, error: 'Failed to load GPX: $e');
    }
  }

  List<ComparisonTrack> get displayTracks => _displayTracks;

  List<DivergencePoint> getDivergencePoints() {
    final enabled = state.tracks.where((t) => t.enabled).toList();
    if (enabled.length < 2) return [];
    return _svc.calculateDivergencePoints(enabled[0], enabled[1]);
  }
}

final _comparisonProvider =
    StateNotifierProvider.autoDispose<_ComparisonNotifier, _ComparisonState>(
  (_) => _ComparisonNotifier(),
);

// ── Main screen ───────────────────────────────────────────────────────────────

class TrackComparisonScreen extends ConsumerStatefulWidget {
  const TrackComparisonScreen({super.key});

  @override
  ConsumerState<TrackComparisonScreen> createState() =>
      _TrackComparisonScreenState();
}

class _TrackComparisonScreenState
    extends ConsumerState<TrackComparisonScreen> {
  final _mapController = MapController();

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isTablet = width >= 700;

    if (isTablet) {
      return _buildTabletLayout();
    } else {
      return _buildPhoneLayout();
    }
  }

  Widget _buildPhoneLayout() {
    final state = ref.watch(_comparisonProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Compare Tracks'),
        actions: [
          _TimeAlignButton(),
          _SpeedColorButton(),
          _ZoomFitButton(mapController: _mapController),
        ],
      ),
      body: Column(
        children: [
          _TrackSelectorPanel(),
          if (state.error != null)
            _ErrorBanner(message: state.error!),
          Expanded(child: _MapView(mapController: _mapController)),
        ],
      ),
      floatingActionButton: state.tracks.isNotEmpty
          ? FloatingActionButton.extended(
              icon: const Icon(Icons.analytics),
              label: const Text('Stats'),
              onPressed: () => _showStatsSheet(context),
            )
          : null,
    );
  }

  Widget _buildTabletLayout() {
    final state = ref.watch(_comparisonProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Compare Tracks'),
        actions: [
          _TimeAlignButton(),
          _SpeedColorButton(),
          _ZoomFitButton(mapController: _mapController),
        ],
      ),
      body: Row(
        children: [
          SizedBox(
            width: 320,
            child: Column(
              children: [
                _TrackSelectorPanel(),
                if (state.error != null)
                  _ErrorBanner(message: state.error!),
                const Divider(height: 1),
                Expanded(child: _StatsPanel()),
              ],
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(child: _MapView(mapController: _mapController)),
        ],
      ),
    );
  }

  void _showStatsSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.25,
        maxChildSize: 0.9,
        expand: false,
        builder: (_, scrollController) => _StatsPanel(
          scrollController: scrollController,
        ),
      ),
    );
  }
}

// ── Track selector ─────────────────────────────────────────────────────────────

class _TrackSelectorPanel extends ConsumerWidget {
  const _TrackSelectorPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(_comparisonProvider);
    final notifier = ref.read(_comparisonProvider.notifier);

    return Container(
      constraints: const BoxConstraints(maxHeight: 240),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Track list
          ...state.tracks.asMap().entries.map((e) => _TrackRow(
                index: e.key,
                track: e.value,
                color: _kTrackColors[e.key % _kTrackColors.length],
              )),

          // Add track button
          if (notifier.canAddMore)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  _AddTrackChip(
                    icon: Icons.history,
                    label: 'My Voyages',
                    onTap: () => _showMyVoyages(context, ref),
                  ),
                  const SizedBox(width: 6),
                  _AddTrackChip(
                    icon: Icons.person_search,
                    label: "Friend's Track",
                    onTap: () => _showFriendSearch(context, ref),
                  ),
                  const SizedBox(width: 6),
                  _AddTrackChip(
                    icon: Icons.upload_file,
                    label: 'GPX File',
                    onTap: () => notifier.addGpxFile(),
                  ),
                ],
              ),
            ),

          if (state.loading)
            const Padding(
              padding: EdgeInsets.all(8),
              child: LinearProgressIndicator(),
            ),
        ],
      ),
    );
  }

  void _showMyVoyages(BuildContext context, WidgetRef ref) async {
    final svc = FloatillaService.instance;
    final vesselName = svc.vesselName ?? svc.username ?? 'My Vessel';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    final notifier = ref.read(_comparisonProvider.notifier);
    final compSvc = TrackComparisonService.instance;

    // Try ships-log first, fall back to logbook entries
    var voyages = await compSvc.loadLocalTracks();
    if (voyages.isEmpty) {
      voyages = await compSvc.loadLocalLogbookTracks();
    }

    if (context.mounted) Navigator.pop(context);

    if (!context.mounted) return;

    if (voyages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No local voyages found')),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _VoyagePickerSheet(
        voyages: voyages,
        vesselName: vesselName,
        onPicked: (v) => notifier.addLocalTrack(v, vesselName),
      ),
    );
  }

  void _showFriendSearch(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => _FriendSearchDialog(
        onSearch: (username) =>
            ref.read(_comparisonProvider.notifier).addFriendTracks(username),
      ),
    );
  }
}

class _TrackRow extends ConsumerWidget {
  final int index;
  final ComparisonTrack track;
  final Color color;

  const _TrackRow({
    required this.index,
    required this.track,
    required this.color,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(_comparisonProvider.notifier);
    final elapsed = track.elapsed;
    final elapsedStr = elapsed != null
        ? '${elapsed.inHours}h ${elapsed.inMinutes % 60}m'
        : '';
    final dateStr = track.startTime != null
        ? DateFormat('d MMM').format(track.startTime!)
        : '';

    return ListTile(
      dense: true,
      leading: Checkbox(
        value: track.enabled,
        activeColor: color,
        onChanged: (_) => notifier.toggleTrack(index),
      ),
      title: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              track.label,
              style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      subtitle: Text(
        '${track.distanceNm.toStringAsFixed(1)} nm'
        '${elapsedStr.isNotEmpty ? ' · $elapsedStr' : ''}'
        '${dateStr.isNotEmpty ? ' · $dateStr' : ''}',
        style: const TextStyle(fontSize: 11),
      ),
      trailing: IconButton(
        icon: const Icon(Icons.close, size: 18),
        onPressed: () => notifier.removeTrack(index),
      ),
    );
  }
}

class _AddTrackChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _AddTrackChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: Icon(icon, size: 14),
      label: Text(label, style: const TextStyle(fontSize: 11)),
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 4),
    );
  }
}

// ── Map view ───────────────────────────────────────────────────────────────────

class _MapView extends ConsumerWidget {
  final MapController mapController;

  const _MapView({required this.mapController});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(_comparisonProvider);
    final notifier = ref.read(_comparisonProvider.notifier);
    final displayTracks = notifier.displayTracks;
    final enabledTracks = displayTracks.where((t) => t.enabled).toList();
    final divergences = notifier.getDivergencePoints();

    // Build polylines
    final polylines = <Polyline>[];
    for (int i = 0; i < enabledTracks.length; i++) {
      final track = enabledTracks[i];
      final color = _kTrackColors[
          state.tracks.indexWhere((t) => t.id == track.id) %
              _kTrackColors.length];
      final isPrimary = i == 0;

      if (state.speedColorMode && track.points.any((p) => p.sog != null)) {
        // Speed color segments
        polylines.addAll(_buildSpeedPolylines(track, isPrimary));
      } else {
        polylines.add(Polyline(
          points: track.points.map((p) => p.position).toList(),
          color: color.withValues(alpha: isPrimary ? 1.0 : 0.5),
          strokeWidth: 3,
        ));
      }
    }

    // Divergence markers
    final markers = divergences.map((d) => Marker(
          point: d.position,
          width: 24,
          height: 24,
          child: Icon(
            Icons.call_split,
            color: Colors.deepOrange,
            size: 20,
          ),
        )).toList();

    if (enabledTracks.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.compare_arrows, size: 64, color: Colors.grey),
            SizedBox(height: 12),
            Text('Add tracks to compare',
                style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    return FlutterMap(
      mapController: mapController,
      options: MapOptions(
        initialCenter: enabledTracks.first.points.isNotEmpty
            ? enabledTracks.first.points.first.position
            : const LatLng(57.0, 12.0),
        initialZoom: 11,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.floatilla.app',
        ),
        if (polylines.isNotEmpty) PolylineLayer(polylines: polylines),
        if (markers.isNotEmpty) MarkerLayer(markers: markers),
      ],
    );
  }

  List<Polyline> _buildSpeedPolylines(ComparisonTrack track, bool isPrimary) {
    final polylines = <Polyline>[];
    final maxSog = track.maxSog ?? 10.0;
    if (maxSog == 0) return polylines;

    for (int i = 1; i < track.points.length; i++) {
      final prev = track.points[i - 1];
      final curr = track.points[i];
      final sog = curr.sog ?? prev.sog ?? 0;
      final t = (sog / maxSog).clamp(0.0, 1.0);
      final color = Color.lerp(Colors.blue, Colors.red, t)!
          .withValues(alpha: isPrimary ? 1.0 : 0.5);
      polylines.add(Polyline(
        points: [prev.position, curr.position],
        color: color,
        strokeWidth: 3,
      ));
    }
    return polylines;
  }
}

// ── Toolbar buttons ────────────────────────────────────────────────────────────

class _TimeAlignButton extends ConsumerWidget {
  const _TimeAlignButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final aligned = ref.watch(_comparisonProvider).timeAligned;
    return IconButton(
      icon: Icon(aligned ? Icons.timer : Icons.timer_off),
      tooltip: aligned ? 'Absolute time' : 'Align by departure (T=0)',
      onPressed: () => ref.read(_comparisonProvider.notifier).toggleTimeAlign(),
    );
  }
}

class _SpeedColorButton extends ConsumerWidget {
  const _SpeedColorButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final speedColor = ref.watch(_comparisonProvider).speedColorMode;
    return IconButton(
      icon: Icon(speedColor ? Icons.speed : Icons.show_chart),
      tooltip: speedColor ? 'Flat color' : 'Speed color',
      onPressed: () =>
          ref.read(_comparisonProvider.notifier).toggleSpeedColor(),
    );
  }
}

class _ZoomFitButton extends ConsumerWidget {
  final MapController mapController;

  const _ZoomFitButton({required this.mapController});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton(
      icon: const Icon(Icons.fit_screen),
      tooltip: 'Zoom to fit all tracks',
      onPressed: () {
        final notifier = ref.read(_comparisonProvider.notifier);
        final tracks = notifier.displayTracks.where((t) => t.enabled).toList();
        if (tracks.isEmpty) return;

        final allPoints = tracks
            .expand((t) => t.points.map((p) => p.position))
            .toList();
        if (allPoints.isEmpty) return;

        final minLat =
            allPoints.map((p) => p.latitude).reduce(math.min);
        final maxLat =
            allPoints.map((p) => p.latitude).reduce(math.max);
        final minLng =
            allPoints.map((p) => p.longitude).reduce(math.min);
        final maxLng =
            allPoints.map((p) => p.longitude).reduce(math.max);

        final bounds = LatLngBounds(
          LatLng(minLat, minLng),
          LatLng(maxLat, maxLng),
        );
        mapController.fitCamera(
          CameraFit.bounds(
            bounds: bounds,
            padding: const EdgeInsets.all(40),
          ),
        );
      },
    );
  }
}

// ── Stats panel ────────────────────────────────────────────────────────────────

class _StatsPanel extends ConsumerWidget {
  final ScrollController? scrollController;

  const _StatsPanel({this.scrollController});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(_comparisonProvider);
    final notifier = ref.read(_comparisonProvider.notifier);
    final tracks = state.tracks.where((t) => t.enabled).toList();
    final divergences = notifier.getDivergencePoints();

    if (tracks.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Add tracks above to see stats',
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.all(16),
      children: [
        // Drag handle for bottom sheet
        if (scrollController != null)
          Center(
            child: Container(
              width: 32,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.grey[400],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

        Text('Performance', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        _StatsTable(tracks: tracks),

        const SizedBox(height: 16),
        _WinnerBanner(tracks: tracks),

        if (divergences.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Divergence Points (${divergences.length})',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          ...divergences.take(5).map((d) => ListTile(
                dense: true,
                leading: const Icon(Icons.call_split, color: Colors.deepOrange),
                title: Text(
                  '${d.position.latitude.toStringAsFixed(4)}, '
                  '${d.position.longitude.toStringAsFixed(4)}',
                  style: const TextStyle(fontSize: 13),
                ),
                subtitle: Text(
                  '${d.separationNm.toStringAsFixed(2)} nm apart · '
                  '${DateFormat('HH:mm').format(d.timestamp)}',
                  style: const TextStyle(fontSize: 11),
                ),
              )),
          if (divergences.length > 5)
            Padding(
              padding: const EdgeInsets.only(left: 16),
              child: Text(
                '+${divergences.length - 5} more divergence points',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
        ],
      ],
    );
  }
}

class _StatsTable extends StatelessWidget {
  final List<ComparisonTrack> tracks;

  const _StatsTable({required this.tracks});

  @override
  Widget build(BuildContext context) {
    return Table(
      border: TableBorder.all(
        color: Theme.of(context).dividerColor,
        width: 0.5,
        borderRadius: BorderRadius.circular(4),
      ),
      columnWidths: const {
        0: FlexColumnWidth(2),
        1: FlexColumnWidth(1),
        2: FlexColumnWidth(1),
        3: FlexColumnWidth(1.5),
        4: FlexColumnWidth(1.5),
      },
      children: [
        // Header row
        TableRow(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
          ),
          children: const [
            _TCell('Vessel', header: true),
            _TCell('Avg SOG', header: true),
            _TCell('Max SOG', header: true),
            _TCell('Distance', header: true),
            _TCell('Elapsed', header: true),
          ],
        ),
        // Data rows
        ...tracks.asMap().entries.map((e) {
          final i = e.key;
          final t = e.value;
          final elapsed = t.elapsed;
          final elapsedStr = elapsed != null
              ? '${elapsed.inHours}h ${elapsed.inMinutes % 60}m'
              : '--';
          final color = _kTrackColors[i % _kTrackColors.length];

          return TableRow(children: [
            _TCell(t.label, color: color),
            _TCell(t.avgSog != null
                ? '${t.avgSog!.toStringAsFixed(1)} kn'
                : '--'),
            _TCell(t.maxSog != null
                ? '${t.maxSog!.toStringAsFixed(1)} kn'
                : '--'),
            _TCell('${t.distanceNm.toStringAsFixed(1)} nm'),
            _TCell(elapsedStr),
          ]);
        }),
      ],
    );
  }
}

class _TCell extends StatelessWidget {
  final String text;
  final bool header;
  final Color? color;

  const _TCell(this.text, {this.header = false, this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (color != null) ...[
            Container(
              width: 8,
              height: 8,
              decoration:
                  BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                fontWeight: header ? FontWeight.w600 : FontWeight.normal,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _WinnerBanner extends StatelessWidget {
  final List<ComparisonTrack> tracks;

  const _WinnerBanner({required this.tracks});

  @override
  Widget build(BuildContext context) {
    if (tracks.length < 2) return const SizedBox.shrink();

    // Fastest avg SOG
    ComparisonTrack? fastestAvg;
    double bestAvg = 0;
    for (final t in tracks) {
      if ((t.avgSog ?? 0) > bestAvg) {
        bestAvg = t.avgSog!;
        fastestAvg = t;
      }
    }

    // Shortest elapsed time
    ComparisonTrack? shortestTime;
    Duration? bestDur;
    for (final t in tracks) {
      if (t.elapsed != null &&
          (bestDur == null || t.elapsed! < bestDur)) {
        bestDur = t.elapsed;
        shortestTime = t;
      }
    }

    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.emoji_events, size: 18),
                const SizedBox(width: 6),
                Text('Results',
                    style: Theme.of(context).textTheme.labelLarge),
              ],
            ),
            const SizedBox(height: 8),
            if (fastestAvg != null)
              _resultRow(Icons.speed, 'Fastest avg SOG', fastestAvg.label,
                  '${bestAvg.toStringAsFixed(1)} kn'),
            if (shortestTime != null && bestDur != null)
              _resultRow(
                Icons.timer,
                'Shortest elapsed',
                shortestTime.label,
                '${bestDur.inHours}h ${bestDur.inMinutes % 60}m',
              ),
          ],
        ),
      ),
    );
  }

  Widget _resultRow(
      IconData icon, String metric, String winner, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(icon, size: 14, color: Colors.grey),
          const SizedBox(width: 6),
          Expanded(
            child: Text(metric,
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ),
          Text(
            '$winner ($value)',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

// ── Error banner ───────────────────────────────────────────────────────────────

class _ErrorBanner extends StatelessWidget {
  final String message;

  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: Theme.of(context).colorScheme.errorContainer,
      child: Row(
        children: [
          const Icon(Icons.error_outline, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Voyage picker sheet ────────────────────────────────────────────────────────

class _VoyagePickerSheet extends StatelessWidget {
  final List<LocalVoyageSummary> voyages;
  final String vesselName;
  final void Function(LocalVoyageSummary) onPicked;

  const _VoyagePickerSheet({
    required this.voyages,
    required this.vesselName,
    required this.onPicked,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            'Select a Voyage',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        const Divider(height: 1),
        Flexible(
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: voyages.length,
            itemBuilder: (ctx, i) {
              final v = voyages[i];
              final elapsed = v.endTime.difference(v.startTime);
              final dateStr = DateFormat('d MMM yyyy').format(v.startTime);
              final durStr =
                  '${elapsed.inHours}h ${elapsed.inMinutes % 60}m';

              return ListTile(
                leading: const Icon(Icons.sailing),
                title: Text('$vesselName — $dateStr'),
                subtitle: Text(
                  '${v.distanceNm.toStringAsFixed(1)} nm · $durStr · '
                  '${v.points.length} pts',
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  onPicked(v);
                },
              );
            },
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

// ── Friend search dialog ───────────────────────────────────────────────────────

class _FriendSearchDialog extends StatefulWidget {
  final void Function(String username) onSearch;

  const _FriendSearchDialog({required this.onSearch});

  @override
  State<_FriendSearchDialog> createState() => _FriendSearchDialogState();
}

class _FriendSearchDialogState extends State<_FriendSearchDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Friend's Tracks"),
      content: TextField(
        controller: _ctrl,
        decoration: const InputDecoration(
          labelText: 'Username',
          prefixIcon: Icon(Icons.person_search),
          border: OutlineInputBorder(),
        ),
        textInputAction: TextInputAction.search,
        onSubmitted: (v) => _submit(context),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => _submit(context),
          child: const Text('Load Tracks'),
        ),
      ],
    );
  }

  void _submit(BuildContext context) {
    final username = _ctrl.text.trim();
    if (username.isEmpty) return;
    Navigator.pop(context);
    widget.onSearch(username);
  }
}
