import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'dart:ui' as ui;
import 'package:latlong2/latlong.dart' hide Path;
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/nav/geo.dart';
import '../shared/responsive.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Models
// ─────────────────────────────────────────────────────────────────────────────

class TidalGate {
  final String id;
  final String name;
  final LatLng position;
  final double distanceNm; // from departure
  final double favorableBearing; // degrees, direction of favorable current
  bool enabled;

  TidalGate({
    required this.id,
    required this.name,
    required this.position,
    required this.distanceNm,
    required this.favorableBearing,
    this.enabled = true,
  });

  TidalGate copyWith({
    String? name,
    double? favorableBearing,
    bool? enabled,
  }) =>
      TidalGate(
        id: id,
        name: name ?? this.name,
        position: position,
        distanceNm: distanceNm,
        favorableBearing: favorableBearing ?? this.favorableBearing,
        enabled: enabled ?? this.enabled,
      );
}

class CurrentPrediction {
  final DateTime time;
  final double speedKn; // positive = favorable, negative = adverse

  const CurrentPrediction({required this.time, required this.speedKn});
}

class DepartureWindow {
  final DateTime departureTime;
  final double totalScore;
  final List<GateResult> gateResults;

  const DepartureWindow({
    required this.departureTime,
    required this.totalScore,
    required this.gateResults,
  });
}

class GateResult {
  final TidalGate gate;
  final DateTime eta;
  final double currentKn; // positive = favorable

  const GateResult({
    required this.gate,
    required this.eta,
    required this.currentKn,
  });
}

class NoaaCurrentStation {
  final String id;
  final String name;
  final LatLng position;

  const NoaaCurrentStation({
    required this.id,
    required this.name,
    required this.position,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// State
// ─────────────────────────────────────────────────────────────────────────────

enum TidalGateMode { auto, manual }

class TidalGateState {
  final TidalGateMode mode;
  final LatLng? departure;
  final LatLng? destination;
  final double vesselSpeedKn;
  final List<TidalGate> gates;
  final List<DepartureWindow> windows;
  final bool loading;
  final String? error;
  final String? status;
  final int? selectedWindowIndex;
  final DateTime? lastOptimized;

  const TidalGateState({
    this.mode = TidalGateMode.auto,
    this.departure,
    this.destination,
    this.vesselSpeedKn = 6.0,
    this.gates = const [],
    this.windows = const [],
    this.loading = false,
    this.error,
    this.status,
    this.selectedWindowIndex,
    this.lastOptimized,
  });

  TidalGateState copyWith({
    TidalGateMode? mode,
    LatLng? departure,
    LatLng? destination,
    double? vesselSpeedKn,
    List<TidalGate>? gates,
    List<DepartureWindow>? windows,
    bool? loading,
    String? error,
    String? status,
    int? selectedWindowIndex,
    DateTime? lastOptimized,
  }) =>
      TidalGateState(
        mode: mode ?? this.mode,
        departure: departure ?? this.departure,
        destination: destination ?? this.destination,
        vesselSpeedKn: vesselSpeedKn ?? this.vesselSpeedKn,
        gates: gates ?? this.gates,
        windows: windows ?? this.windows,
        loading: loading ?? this.loading,
        error: error,
        status: status,
        selectedWindowIndex: selectedWindowIndex ?? this.selectedWindowIndex,
        lastOptimized: lastOptimized ?? this.lastOptimized,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Notifier
// ─────────────────────────────────────────────────────────────────────────────

class TidalGateNotifier extends StateNotifier<TidalGateState> {
  TidalGateNotifier() : super(const TidalGateState());

  static const _noaaBase =
      'https://api.tidesandcurrents.noaa.gov/api/prod/datagetter';
  static const _noaaStationsUrl =
      'https://api.tidesandcurrents.noaa.gov/mdapi/prod/webapi/stations.json'
      '?type=currentpredictions&units=english';

  // Current predictions cache: stationId -> list of predictions
  final Map<String, List<CurrentPrediction>> _predCache = {};

  void setMode(TidalGateMode mode) => state = state.copyWith(mode: mode);

  void setVesselSpeed(double kn) => state = state.copyWith(vesselSpeedKn: kn);

  void setDeparture(LatLng pos) => state = state.copyWith(departure: pos);

  void setDestination(LatLng pos) => state = state.copyWith(destination: pos);

  void addManualGate(TidalGate gate) {
    state = state.copyWith(gates: [...state.gates, gate]);
  }

  void removeGate(String id) {
    state = state.copyWith(
        gates: state.gates.where((g) => g.id != id).toList());
  }

  void toggleGate(String id) {
    state = state.copyWith(
      gates: state.gates
          .map((g) => g.id == id ? g.copyWith(enabled: !g.enabled) : g)
          .toList(),
    );
  }

  void selectWindow(int index) =>
      state = state.copyWith(selectedWindowIndex: index);

  Future<void> saveDepartureWindow() async {
    if (state.selectedWindowIndex == null || state.windows.isEmpty) {
      return;
    }
    final idx = state.selectedWindowIndex!;
    if (idx >= state.windows.length) {
      return;
    }
    final window = state.windows[idx];
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        'tidal_gate_departure',
        window.departureTime.toIso8601String());
  }

  /// Auto-detect gates: find NOAA current stations within 20nm of route,
  /// treat each as a potential tidal gate.
  Future<void> autoDetectGates() async {
    if (state.departure == null || state.destination == null) {
      state = state.copyWith(
          error: 'Set departure and destination first', loading: false);
      return;
    }
    state = state.copyWith(loading: true, error: null, status: 'Fetching NOAA current stations...');

    try {
      final stations = await _fetchCurrentStations();
      state = state.copyWith(status: 'Found ${stations.length} stations, filtering by route...');

      final routeStations = _filterStationsAlongRoute(
        stations,
        state.departure!,
        state.destination!,
        radiusNm: 20,
      );

      if (routeStations.isEmpty) {
        state = state.copyWith(
          loading: false,
          error: 'No NOAA current stations found within 20nm of route. '
              'Try manual gate entry or a US coastal route.',
          status: null,
          gates: [],
        );
        return;
      }

      final gates = routeStations.take(8).map((s) {
        final distNm = haversineDistanceNm(state.departure!, s.position);
        // Estimate favorable bearing: along-route bearing at that point
        final bearing = initialBearing(state.departure!, state.destination!);
        return TidalGate(
          id: s.id,
          name: s.name,
          position: s.position,
          distanceNm: distNm,
          favorableBearing: bearing,
        );
      }).toList()
        ..sort((a, b) => a.distanceNm.compareTo(b.distanceNm));

      state = state.copyWith(
        gates: gates,
        loading: false,
        status: 'Found ${gates.length} tidal gates. Running optimizer...',
        error: null,
      );

      await optimize();
    } catch (e) {
      state = state.copyWith(
        loading: false,
        error: 'Error fetching stations: $e',
        status: null,
      );
    }
  }

  Future<void> optimize() async {
    final gates = state.gates.where((g) => g.enabled).toList();
    if (gates.isEmpty) {
      state = state.copyWith(error: 'No enabled gates to optimize', loading: false);
      return;
    }
    if (state.departure == null) {
      state = state.copyWith(error: 'Set departure position', loading: false);
      return;
    }

    state = state.copyWith(loading: true, error: null, status: 'Fetching current predictions...');

    try {
      // Pre-fetch predictions for all gates
      for (final gate in gates) {
        if (!_predCache.containsKey(gate.id)) {
          state = state.copyWith(status: 'Fetching currents for ${gate.name}...');
          final preds = await _fetchCurrentPredictions(gate.id, gate.favorableBearing);
          _predCache[gate.id] = preds;
        }
      }

      state = state.copyWith(status: 'Running optimizer (97 departure windows)...');
      await Future<void>.delayed(Duration.zero); // let UI update

      final now = DateTime.now().toUtc();
      final windows = <DepartureWindow>[];

      // Try departure times from now to +48h in 30-min steps
      for (int step = 0; step < 97; step++) {
        final departure = now.add(Duration(minutes: step * 30));
        final gateResults = <GateResult>[];
        double totalScore = 0;

        for (final gate in gates) {
          final etaHours = gate.distanceNm / state.vesselSpeedKn;
          final eta = departure.add(
              Duration(minutes: (etaHours * 60).round()));

          final preds = _predCache[gate.id] ?? [];
          final currentKn = _interpolateCurrent(preds, eta);
          totalScore += currentKn;

          gateResults.add(GateResult(
            gate: gate,
            eta: eta,
            currentKn: currentKn,
          ));
        }

        windows.add(DepartureWindow(
          departureTime: departure,
          totalScore: totalScore,
          gateResults: gateResults,
        ));
      }

      windows.sort((a, b) => b.totalScore.compareTo(a.totalScore));
      final top5 = windows.take(5).toList();

      state = state.copyWith(
        windows: top5,
        loading: false,
        status: null,
        error: null,
        selectedWindowIndex: 0,
        lastOptimized: DateTime.now(),
      );
    } catch (e) {
      state = state.copyWith(
        loading: false,
        error: 'Optimizer error: $e',
        status: null,
      );
    }
  }

  double _interpolateCurrent(List<CurrentPrediction> preds, DateTime at) {
    if (preds.isEmpty) return 0;
    if (preds.length == 1) return preds.first.speedKn;

    // Find surrounding predictions
    CurrentPrediction? before;
    CurrentPrediction? after;
    for (final p in preds) {
      if (p.time.isBefore(at) || p.time.isAtSameMomentAs(at)) {
        before = p;
      } else if (after == null) {
        after = p;
        break;
      }
    }

    if (before == null) return preds.first.speedKn;
    if (after == null) return preds.last.speedKn;

    final totalMs = after.time.difference(before.time).inMilliseconds;
    if (totalMs == 0) return before.speedKn;
    final fraction =
        at.difference(before.time).inMilliseconds / totalMs;
    return before.speedKn + (after.speedKn - before.speedKn) * fraction;
  }

  Future<List<NoaaCurrentStation>> _fetchCurrentStations() async {
    final resp = await http
        .get(Uri.parse(_noaaStationsUrl))
        .timeout(const Duration(seconds: 15));
    if (resp.statusCode != 200) {
      throw Exception('HTTP ${resp.statusCode}');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final list = data['stations'] as List<dynamic>? ?? [];
    return list.map((e) {
      final m = e as Map<String, dynamic>;
      return NoaaCurrentStation(
        id: m['id'] as String,
        name: m['name'] as String,
        position: LatLng(
          double.tryParse(m['lat']?.toString() ?? '0') ?? 0,
          double.tryParse(m['lng']?.toString() ?? '0') ?? 0,
        ),
      );
    }).toList();
  }

  /// Keep only stations within [radiusNm] of the great-circle route.
  List<NoaaCurrentStation> _filterStationsAlongRoute(
    List<NoaaCurrentStation> stations,
    LatLng dep,
    LatLng dest,
    {double radiusNm = 20}
  ) {
    final totalDist = haversineDistanceNm(dep, dest);
    return stations.where((s) {
      // Cross-track distance approximation
      final dA = haversineDistanceNm(dep, s.position);
      final dB = haversineDistanceNm(dest, s.position);
      // Keep if station is roughly between departure and destination
      if (dA > totalDist + radiusNm || dB > totalDist + radiusNm) return false;
      // Check perpendicular distance to route
      final xtd = _crossTrackNm(dep, dest, s.position);
      return xtd.abs() <= radiusNm;
    }).toList();
  }

  double _crossTrackNm(LatLng from, LatLng to, LatLng point) {
    // Spherical cross-track distance
    const r = 3440.065; // earth radius in nm
    final d13 = haversineDistanceNm(from, point) / r;
    final theta13 = initialBearing(from, point) * math.pi / 180;
    final theta12 = initialBearing(from, to) * math.pi / 180;
    return math.asin(math.sin(d13) * math.sin(theta13 - theta12)) * r;
  }

  Future<List<CurrentPrediction>> _fetchCurrentPredictions(
      String stationId, double favorableBearing) async {
    final now = DateTime.now().toUtc();
    final begin = _dateStr(now);
    final end = _dateStr(now.add(const Duration(days: 3)));

    final url = '$_noaaBase'
        '?product=currents_predictions'
        '&station=$stationId'
        '&begin_date=$begin'
        '&end_date=$end'
        '&datum=MLLW'
        '&time_zone=GMT'
        '&interval=6'
        '&units=knots'
        '&application=floatilla'
        '&format=json';

    final resp = await http
        .get(Uri.parse(url))
        .timeout(const Duration(seconds: 15));

    if (resp.statusCode != 200) {
      // Return empty — optimizer will score 0 for this gate
      return [];
    }

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final predictions = data['current_predictions'] as Map<String, dynamic>?;
    final list = predictions?['cp'] as List<dynamic>?;
    if (list == null || list.isEmpty) return [];

    return list.map((e) {
      final m = e as Map<String, dynamic>;
      final timeStr = m['Time'] as String? ?? '';
      final velStr = m['Velocity_Major'] as String? ?? '0';
      final dirStr = m['Direction'] as String? ?? '0';

      DateTime t;
      try {
        t = DateTime.parse('${timeStr.replaceAll(' ', 'T')}Z');
      } catch (_) {
        t = now;
      }

      double vel = double.tryParse(velStr) ?? 0;
      final dir = double.tryParse(dirStr) ?? 0;

      // NOAA Velocity_Major: positive = flood (along channel), negative = ebb
      // Determine favorable: if current direction aligns with favorableBearing,
      // vel is positive (favorable); otherwise negative.
      final angularDiff = _angleDiff(dir, favorableBearing);
      if (angularDiff.abs() > 90) {
        vel = -vel.abs(); // adverse
      } else {
        vel = vel.abs(); // favorable
      }

      return CurrentPrediction(time: t, speedKn: vel);
    }).toList()
      ..sort((a, b) => a.time.compareTo(b.time));
  }

  double _angleDiff(double a, double b) {
    double diff = (a - b) % 360;
    if (diff > 180) diff -= 360;
    return diff;
  }

  String _dateStr(DateTime dt) =>
      '${dt.year}${dt.month.toString().padLeft(2, '0')}${dt.day.toString().padLeft(2, '0')}';

  List<CurrentPrediction>? getGatePredictions(String gateId) =>
      _predCache[gateId];
}

// ─────────────────────────────────────────────────────────────────────────────
// Providers
// ─────────────────────────────────────────────────────────────────────────────

final tidalGateProvider =
    StateNotifierProvider<TidalGateNotifier, TidalGateState>((ref) {
  return TidalGateNotifier();
});

// ─────────────────────────────────────────────────────────────────────────────
// Screen
// ─────────────────────────────────────────────────────────────────────────────

class TidalGateScreen extends ConsumerStatefulWidget {
  const TidalGateScreen({super.key});

  @override
  ConsumerState<TidalGateScreen> createState() => _TidalGateScreenState();
}

class _TidalGateScreenState extends ConsumerState<TidalGateScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isTablet = Responsive.isTablet(context);
    final state = ref.watch(tidalGateProvider);

    if (isTablet) {
      return _buildTabletLayout(state);
    } else {
      return _buildPhoneLayout(state);
    }
  }

  Widget _buildPhoneLayout(TidalGateState state) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tidal Gate Optimizer'),
        actions: _appBarActions(state),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.route), text: 'Route'),
            Tab(icon: Icon(Icons.check_circle_outline), text: 'Results'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _RoutePanel(onOptimized: () => _tabController.animateTo(1)),
          const _ResultsPanel(),
        ],
      ),
    );
  }

  Widget _buildTabletLayout(TidalGateState state) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tidal Gate Optimizer'),
        actions: _appBarActions(state),
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 380,
            child: _RoutePanel(onOptimized: () {}),
          ),
          const VerticalDivider(width: 1),
          const Expanded(child: _ResultsPanel()),
        ],
      ),
    );
  }

  List<Widget> _appBarActions(TidalGateState state) {
    return [
      if (state.loading)
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      if (!state.loading && state.gates.isNotEmpty)
        IconButton(
          icon: const Icon(Icons.play_arrow),
          tooltip: 'Run optimizer',
          onPressed: () =>
              ref.read(tidalGateProvider.notifier).optimize(),
        ),
    ];
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Route Panel (left/top panel — input)
// ─────────────────────────────────────────────────────────────────────────────

class _RoutePanel extends ConsumerStatefulWidget {
  final VoidCallback onOptimized;

  const _RoutePanel({required this.onOptimized});

  @override
  ConsumerState<_RoutePanel> createState() => _RoutePanelState();
}

class _RoutePanelState extends ConsumerState<_RoutePanel> {
  final _depLatCtl = TextEditingController(text: '37.8');
  final _depLonCtl = TextEditingController(text: '-122.4');
  final _destLatCtl = TextEditingController(text: '37.5');
  final _destLonCtl = TextEditingController(text: '-122.1');
  final _speedCtl = TextEditingController(text: '6.0');

  // Manual gate fields
  final _gateNameCtl = TextEditingController();
  final _gateLatCtl = TextEditingController();
  final _gateLonCtl = TextEditingController();
  final _gateBearingCtl = TextEditingController(text: '0');
  final _gateDistCtl = TextEditingController();

  @override
  void dispose() {
    for (final ctl in [
      _depLatCtl, _depLonCtl, _destLatCtl, _destLonCtl,
      _speedCtl, _gateNameCtl, _gateLatCtl, _gateLonCtl,
      _gateBearingCtl, _gateDistCtl,
    ]) {
      ctl.dispose();
    }
    super.dispose();
  }

  void _applyRoute() {
    final depLat = double.tryParse(_depLatCtl.text) ?? 0;
    final depLon = double.tryParse(_depLonCtl.text) ?? 0;
    final destLat = double.tryParse(_destLatCtl.text) ?? 0;
    final destLon = double.tryParse(_destLonCtl.text) ?? 0;
    final speed = double.tryParse(_speedCtl.text) ?? 6.0;

    ref.read(tidalGateProvider.notifier).setDeparture(LatLng(depLat, depLon));
    ref.read(tidalGateProvider.notifier).setDestination(LatLng(destLat, destLon));
    ref.read(tidalGateProvider.notifier).setVesselSpeed(speed);
  }

  void _runAutoDetect() {
    _applyRoute();
    ref.read(tidalGateProvider.notifier).autoDetectGates().then((_) {
      widget.onOptimized();
    });
  }

  void _addManualGate() {
    final name = _gateNameCtl.text.trim();
    if (name.isEmpty) return;
    final lat = double.tryParse(_gateLatCtl.text) ?? 0;
    final lon = double.tryParse(_gateLonCtl.text) ?? 0;
    final bearing = double.tryParse(_gateBearingCtl.text) ?? 0;
    final distNm = double.tryParse(_gateDistCtl.text) ?? 0;

    ref.read(tidalGateProvider.notifier).addManualGate(
          TidalGate(
            id: 'manual_${DateTime.now().millisecondsSinceEpoch}',
            name: name,
            position: LatLng(lat, lon),
            distanceNm: distNm,
            favorableBearing: bearing,
          ),
        );

    _gateNameCtl.clear();
    _gateLatCtl.clear();
    _gateLonCtl.clear();
    _gateBearingCtl.text = '0';
    _gateDistCtl.clear();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(tidalGateProvider);
    final notifier = ref.read(tidalGateProvider.notifier);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Mode selector
          SegmentedButton<TidalGateMode>(
            segments: const [
              ButtonSegment(
                value: TidalGateMode.auto,
                icon: Icon(Icons.auto_fix_high),
                label: Text('Auto-detect'),
              ),
              ButtonSegment(
                value: TidalGateMode.manual,
                icon: Icon(Icons.edit),
                label: Text('Manual'),
              ),
            ],
            selected: {state.mode},
            onSelectionChanged: (s) => notifier.setMode(s.first),
          ),

          const SizedBox(height: 12),

          // Route inputs
          _SectionHeader(icon: Icons.route, label: 'Route'),
          const SizedBox(height: 8),

          // Departure row
          Row(
            children: [
              const SizedBox(
                  width: 80,
                  child: Text('Departure', style: TextStyle(fontSize: 12))),
              Expanded(
                child: _LatLonField(
                    latCtl: _depLatCtl, lonCtl: _depLonCtl, label: 'Dep.'),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Destination row
          Row(
            children: [
              const SizedBox(
                  width: 80,
                  child:
                      Text('Destination', style: TextStyle(fontSize: 12))),
              Expanded(
                child: _LatLonField(
                    latCtl: _destLatCtl,
                    lonCtl: _destLonCtl,
                    label: 'Dest.'),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Speed
          Row(
            children: [
              const SizedBox(
                  width: 80,
                  child: Text('Speed (kn)', style: TextStyle(fontSize: 12))),
              Expanded(
                child: TextField(
                  controller: _speedCtl,
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true),
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                    hintText: '6.0',
                    suffixText: 'kn',
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          if (state.mode == TidalGateMode.auto) ...[
            FilledButton.icon(
              icon: const Icon(Icons.search),
              label: const Text('Detect gates & optimize'),
              onPressed: state.loading ? null : _runAutoDetect,
            ),
            const SizedBox(height: 4),
            Text(
              'Searches NOAA current stations within 20nm of your route.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],

          if (state.mode == TidalGateMode.manual) ...[
            _SectionHeader(icon: Icons.add_location, label: 'Add Gate'),
            const SizedBox(height: 8),
            TextField(
              controller: _gateNameCtl,
              decoration: const InputDecoration(
                labelText: 'Gate name',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            _LatLonField(
                latCtl: _gateLatCtl, lonCtl: _gateLonCtl, label: 'Gate'),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _gateBearingCtl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Favorable bearing',
                      border: OutlineInputBorder(),
                      isDense: true,
                      suffixText: 'deg',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _gateDistCtl,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Distance from dep.',
                      border: OutlineInputBorder(),
                      isDense: true,
                      suffixText: 'nm',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Add gate'),
              onPressed: _addManualGate,
            ),
            const SizedBox(height: 12),
            if (state.gates.isNotEmpty) ...[
              FilledButton.icon(
                icon: const Icon(Icons.play_arrow),
                label: const Text('Run optimizer'),
                onPressed: state.loading
                    ? null
                    : () {
                        _applyRoute();
                        ref
                            .read(tidalGateProvider.notifier)
                            .optimize()
                            .then((_) => widget.onOptimized());
                      },
              ),
            ],
          ],

          // Status / error
          if (state.status != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    state.status!,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ],
          if (state.error != null) ...[
            const SizedBox(height: 8),
            _ErrorBanner(message: state.error!),
          ],

          // Gates list
          if (state.gates.isNotEmpty) ...[
            const SizedBox(height: 12),
            _SectionHeader(icon: Icons.water, label: 'Tidal Gates'),
            const SizedBox(height: 4),
            ...state.gates.map(
              (g) => _GateTile(
                gate: g,
                predictions: notifier.getGatePredictions(g.id),
                onToggle: () => notifier.toggleGate(g.id),
                onRemove: () => notifier.removeGate(g.id),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Results Panel (right/bottom panel)
// ─────────────────────────────────────────────────────────────────────────────

class _ResultsPanel extends ConsumerWidget {
  const _ResultsPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(tidalGateProvider);
    final notifier = ref.read(tidalGateProvider.notifier);

    if (state.loading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Optimizing departure windows...'),
          ],
        ),
      );
    }

    if (state.windows.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.water, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            const Text(
              'No results yet',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text(
              'Set your route and run the optimizer.',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    final fmt = DateFormat('EEE d MMM HH:mm');

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (state.lastOptimized != null)
            Text(
              'Optimized at ${DateFormat('HH:mm').format(state.lastOptimized!.toLocal())} '
              '— top ${state.windows.length} departure windows',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          const SizedBox(height: 8),

          ...List.generate(state.windows.length, (i) {
            final w = state.windows[i];
            final isSelected = state.selectedWindowIndex == i;
            final isBest = i == 0;

            return GestureDetector(
              onTap: () => notifier.selectWindow(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: isSelected
                        ? Theme.of(context).colorScheme.primary
                        : Colors.grey.shade300,
                    width: isSelected ? 2 : 1,
                  ),
                  borderRadius: BorderRadius.circular(10),
                  color: isBest
                      ? Colors.green.withValues(alpha: 0.05)
                      : null,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header row
                      Row(
                        children: [
                          if (isBest) ...[
                            Icon(Icons.star,
                                size: 18,
                                color: Colors.amber.shade700),
                            const SizedBox(width: 4),
                          ] else ...[
                            Text(
                              '#${i + 1}',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey.shade600),
                            ),
                            const SizedBox(width: 8),
                          ],
                          Expanded(
                            child: Text(
                              fmt.format(w.departureTime.toLocal()),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                          ),
                          _ScoreBadge(score: w.totalScore),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // Gate results
                      ...w.gateResults.map(
                        (gr) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: _GateResultRow(result: gr),
                        ),
                      ),

                      // Set as departure button
                      if (isSelected) ...[
                        const SizedBox(height: 8),
                        FilledButton.icon(
                          icon: const Icon(Icons.departure_board, size: 18),
                          label: const Text('Set as departure'),
                          onPressed: () async {
                            await notifier.saveDepartureWindow();
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Departure set: ${fmt.format(w.departureTime.toLocal())}',
                                  ),
                                ),
                              );
                            }
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          }),

          // Timeline chart for selected window
          if (state.selectedWindowIndex != null &&
              state.windows.isNotEmpty) ...[
            const SizedBox(height: 8),
            _SectionHeader(icon: Icons.show_chart, label: 'Current Timeline'),
            const SizedBox(height: 8),
            _CurrentTimelineChart(
              window: state.windows[state.selectedWindowIndex!],
              notifier: ref.read(tidalGateProvider.notifier),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Gate result row
// ─────────────────────────────────────────────────────────────────────────────

class _GateResultRow extends StatelessWidget {
  final GateResult result;

  const _GateResultRow({required this.result});

  @override
  Widget build(BuildContext context) {
    final favorable = result.currentKn >= 0;
    final color = favorable ? Colors.green.shade700 : Colors.red.shade700;
    final icon = favorable ? Icons.arrow_upward : Icons.arrow_downward;

    return Row(
      children: [
        Icon(Icons.water, size: 14, color: Colors.grey.shade500),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            result.gate.name,
            style: const TextStyle(fontSize: 12),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Text(
          DateFormat('HH:mm').format(result.eta.toLocal()),
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
        const SizedBox(width: 8),
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 2),
        SizedBox(
          width: 50,
          child: Text(
            '${result.currentKn.abs().toStringAsFixed(1)} kn',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: color,
            ),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Score badge
// ─────────────────────────────────────────────────────────────────────────────

class _ScoreBadge extends StatelessWidget {
  final double score;

  const _ScoreBadge({required this.score});

  @override
  Widget build(BuildContext context) {
    final positive = score >= 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: positive
            ? Colors.green.withValues(alpha: 0.12)
            : Colors.red.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: positive ? Colors.green.shade300 : Colors.red.shade300,
        ),
      ),
      child: Text(
        '${positive ? '+' : ''}${score.toStringAsFixed(1)} kn',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: positive ? Colors.green.shade800 : Colors.red.shade800,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Gate tile
// ─────────────────────────────────────────────────────────────────────────────

class _GateTile extends StatelessWidget {
  final TidalGate gate;
  final List<CurrentPrediction>? predictions;
  final VoidCallback onToggle;
  final VoidCallback onRemove;

  const _GateTile({
    required this.gate,
    required this.predictions,
    required this.onToggle,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Switch(
              value: gate.enabled,
              onChanged: (_) => onToggle(),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            const SizedBox(width: 8),
            Icon(Icons.water, size: 18,
                color: gate.enabled ? Colors.blue : Colors.grey),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    gate.name,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: gate.enabled ? null : Colors.grey,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '${gate.distanceNm.toStringAsFixed(1)} nm from departure  '
                    '· bearing ${gate.favorableBearing.toStringAsFixed(0)}°',
                    style: TextStyle(
                        fontSize: 11, color: Colors.grey.shade600),
                  ),
                  if (predictions != null && predictions!.isNotEmpty)
                    Text(
                      '${predictions!.length} prediction points loaded',
                      style: const TextStyle(
                          fontSize: 10, color: Colors.green),
                    ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 18),
              onPressed: onRemove,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Current timeline chart (CustomPaint)
// ─────────────────────────────────────────────────────────────────────────────

class _CurrentTimelineChart extends StatelessWidget {
  final DepartureWindow window;
  final TidalGateNotifier notifier;

  const _CurrentTimelineChart({
    required this.window,
    required this.notifier,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 180,
      child: CustomPaint(
        painter: _TimelinePainter(
          window: window,
          notifier: notifier,
          textColor: Theme.of(context).colorScheme.onSurface,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _TimelinePainter extends CustomPainter {
  final DepartureWindow window;
  final TidalGateNotifier notifier;
  final Color textColor;

  const _TimelinePainter({
    required this.window,
    required this.notifier,
    required this.textColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const padL = 40.0;
    const padR = 16.0;
    const padT = 16.0;
    const padB = 30.0;

    final chartW = size.width - padL - padR;
    final chartH = size.height - padT - padB;
    final centerY = padT + chartH / 2;

    // Grid
    final gridPaint = Paint()
      ..color = Colors.grey.withValues(alpha: 0.2)
      ..strokeWidth = 0.5;
    canvas.drawLine(
        Offset(padL, centerY), Offset(padL + chartW, centerY), gridPaint);
    canvas.drawRect(
        Rect.fromLTWH(padL, padT, chartW, chartH),
        Paint()
          ..color = Colors.grey.withValues(alpha: 0.08)
          ..style = PaintingStyle.fill);
    canvas.drawRect(
        Rect.fromLTWH(padL, padT, chartW, chartH),
        Paint()
          ..color = Colors.grey.withValues(alpha: 0.3)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8);

    final now = DateTime.now().toUtc();
    final horizonH = 48.0;

    // Draw per-gate current curves
    final colors = [
      Colors.blue, Colors.orange, Colors.purple,
      Colors.teal, Colors.pink, Colors.indigo, Colors.brown, Colors.cyan,
    ];

    for (int gi = 0; gi < window.gateResults.length; gi++) {
      final gr = window.gateResults[gi];
      final preds = notifier.getGatePredictions(gr.gate.id);
      if (preds == null || preds.isEmpty) continue;

      final color = colors[gi % colors.length];
      final path = Path();
      bool started = false;

      // Find Y scale — assume max 5 kn
      const maxKn = 5.0;

      for (final p in preds) {
        final hours = p.time.difference(now).inMinutes / 60.0;
        if (hours < 0 || hours > horizonH) continue;

        final x = padL + (hours / horizonH) * chartW;
        final y = centerY - (p.speedKn / maxKn) * (chartH / 2);

        if (!started) {
          path.moveTo(x, y);
          started = true;
        } else {
          path.lineTo(x, y);
        }
      }

      canvas.drawPath(
          path,
          Paint()
            ..color = color.withValues(alpha: 0.7)
            ..strokeWidth = 1.5
            ..style = PaintingStyle.stroke);

      // ETA marker
      final etaH = gr.eta.difference(now).inMinutes / 60.0;
      if (etaH >= 0 && etaH <= horizonH) {
        final etaX = padL + (etaH / horizonH) * chartW;
        final etaY = centerY - (gr.currentKn / maxKn) * (chartH / 2);

        // Vertical line at ETA
        canvas.drawLine(
          Offset(etaX, padT),
          Offset(etaX, padT + chartH),
          Paint()
            ..color = color.withValues(alpha: 0.4)
            ..strokeWidth = 1
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            // dashed effect approximation
        );

        // Dot at ETA
        canvas.drawCircle(
          Offset(etaX, etaY),
          5,
          Paint()
            ..color = color
            ..style = PaintingStyle.fill,
        );
        canvas.drawCircle(
          Offset(etaX, etaY),
          5,
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );

        // Gate label above dot
        _drawText(
          canvas,
          gi < 9 ? '${gi + 1}' : '+',
          Offset(etaX - 3, etaY - 16),
          TextStyle(
              fontSize: 9,
              color: color,
              fontWeight: FontWeight.bold),
        );
      }
    }

    // X-axis labels (0, 6, 12, 18, 24, 30, 36, 42, 48h)
    for (int h = 0; h <= 48; h += 6) {
      final x = padL + (h / horizonH) * chartW;
      _drawText(canvas, '${h}h', Offset(x - 6, padT + chartH + 6),
          TextStyle(fontSize: 9, color: textColor.withValues(alpha: 0.6)));
      canvas.drawLine(
          Offset(x, padT + chartH),
          Offset(x, padT + chartH + 3),
          Paint()
            ..color = Colors.grey.withValues(alpha: 0.5)
            ..strokeWidth = 0.8);
    }

    // Y-axis labels
    _drawText(canvas, '+5', Offset(2, padT + 2),
        TextStyle(fontSize: 9, color: Colors.green.withValues(alpha: 0.8)));
    _drawText(canvas, '0', Offset(8, centerY - 5),
        TextStyle(fontSize: 9, color: textColor.withValues(alpha: 0.5)));
    _drawText(canvas, '-5', Offset(2, padT + chartH - 14),
        TextStyle(fontSize: 9, color: Colors.red.withValues(alpha: 0.8)));

    // Now marker
    final nowX = padL;
    canvas.drawLine(
      Offset(nowX, padT),
      Offset(nowX, padT + chartH),
      Paint()
        ..color = Colors.orange.withValues(alpha: 0.8)
        ..strokeWidth = 1.5,
    );
    _drawText(canvas, 'now', Offset(nowX + 2, padT),
        const TextStyle(fontSize: 9, color: Colors.orange));

    // Departure marker
    final depH = window.departureTime.difference(now).inMinutes / 60.0;
    if (depH >= 0 && depH <= horizonH) {
      final depX = padL + (depH / horizonH) * chartW;
      canvas.drawLine(
        Offset(depX, padT),
        Offset(depX, padT + chartH),
        Paint()
          ..color = Colors.green.withValues(alpha: 0.8)
          ..strokeWidth = 1.5,
      );
      _drawText(
          canvas,
          'dep',
          Offset(depX + 2, padT + chartH - 20),
          const TextStyle(fontSize: 9, color: Colors.green));
    }
  }

  void _drawText(Canvas canvas, String text, Offset pos, TextStyle style) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    tp.paint(canvas, pos);
  }

  @override
  bool shouldRepaint(_TimelinePainter old) =>
      old.window != window;
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;

  const _SectionHeader({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 13,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ],
    );
  }
}

class _LatLonField extends StatelessWidget {
  final TextEditingController latCtl;
  final TextEditingController lonCtl;
  final String label;

  const _LatLonField({
    required this.latCtl,
    required this.lonCtl,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: latCtl,
            keyboardType: const TextInputType.numberWithOptions(
                decimal: true, signed: true),
            decoration: InputDecoration(
              labelText: '$label lat',
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: lonCtl,
            keyboardType: const TextInputType.numberWithOptions(
                decimal: true, signed: true),
            decoration: InputDecoration(
              labelText: '$label lon',
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;

  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber, size: 16, color: Colors.red),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 12, color: Colors.red.shade800),
            ),
          ),
        ],
      ),
    );
  }
}
