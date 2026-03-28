import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/floatilla/floatilla_service.dart';
import '../../core/nav/geo.dart';
import '../../data/providers/anchor_provider.dart';
import '../../data/providers/signalk_provider.dart';
import '../../data/providers/vessel_provider.dart';
import '../shared/responsive.dart';

// ─── State ─────────────────────────────────────────────────────────────────

enum ScopeFormula { catenary, conservative }

class AnchorScopeState {
  final bool isActive;
  final LatLng? dropPosition;
  final double chainLengthM;
  final bool chainInFeet;
  final double depthM;
  final double freeboard;
  final double safetyMarginM;
  final ScopeFormula formula;
  final double? currentDistanceM;
  final double? maxDistanceM;
  final double? bearingDeg;
  final bool isDragging;

  const AnchorScopeState({
    this.isActive = false,
    this.dropPosition,
    this.chainLengthM = 40,
    this.chainInFeet = false,
    this.depthM = 5,
    this.freeboard = 1.5,
    this.safetyMarginM = 10,
    this.formula = ScopeFormula.catenary,
    this.currentDistanceM,
    this.maxDistanceM,
    this.bearingDeg,
    this.isDragging = false,
  });

  double get swingRadiusCatenary {
    final totalDepth = depthM + freeboard;
    final chain = chainLengthM;
    if (chain <= totalDepth) return safetyMarginM;
    return sqrt(chain * chain - totalDepth * totalDepth) + safetyMarginM;
  }

  double get swingRadiusConservative {
    return chainLengthM + depthM + safetyMarginM;
  }

  double get activeSwingRadius =>
      formula == ScopeFormula.catenary ? swingRadiusCatenary : swingRadiusConservative;

  AnchorScopeState copyWith({
    bool? isActive,
    LatLng? dropPosition,
    double? chainLengthM,
    bool? chainInFeet,
    double? depthM,
    double? freeboard,
    double? safetyMarginM,
    ScopeFormula? formula,
    double? currentDistanceM,
    double? maxDistanceM,
    double? bearingDeg,
    bool? isDragging,
  }) {
    return AnchorScopeState(
      isActive: isActive ?? this.isActive,
      dropPosition: dropPosition ?? this.dropPosition,
      chainLengthM: chainLengthM ?? this.chainLengthM,
      chainInFeet: chainInFeet ?? this.chainInFeet,
      depthM: depthM ?? this.depthM,
      freeboard: freeboard ?? this.freeboard,
      safetyMarginM: safetyMarginM ?? this.safetyMarginM,
      formula: formula ?? this.formula,
      currentDistanceM: currentDistanceM ?? this.currentDistanceM,
      maxDistanceM: maxDistanceM ?? this.maxDistanceM,
      bearingDeg: bearingDeg ?? this.bearingDeg,
      isDragging: isDragging ?? this.isDragging,
    );
  }
}

// ─── Provider ──────────────────────────────────────────────────────────────

class AnchorScopeNotifier extends StateNotifier<AnchorScopeState> {
  final Ref _ref;
  Timer? _timer;
  bool _alarmSent = false;

  AnchorScopeNotifier(this._ref) : super(const AnchorScopeState()) {
    _loadPersisted();
  }

  Future<void> _loadPersisted() async {
    final prefs = await SharedPreferences.getInstance();
    final active = prefs.getBool('scope_active') ?? false;
    final lat = prefs.getDouble('scope_lat');
    final lon = prefs.getDouble('scope_lon');
    final chain = prefs.getDouble('scope_chain') ?? 40;
    final depth = prefs.getDouble('scope_depth') ?? 5;
    final freeboard = prefs.getDouble('scope_freeboard') ?? 1.5;
    final margin = prefs.getDouble('scope_margin') ?? 10;
    final inFeet = prefs.getBool('scope_in_feet') ?? false;
    final formulaIndex = prefs.getInt('scope_formula') ?? 0;

    state = AnchorScopeState(
      isActive: active && lat != null && lon != null,
      dropPosition: (lat != null && lon != null) ? LatLng(lat, lon) : null,
      chainLengthM: chain,
      chainInFeet: inFeet,
      depthM: depth,
      freeboard: freeboard,
      safetyMarginM: margin,
      formula: ScopeFormula.values[formulaIndex.clamp(0, 1)],
    );

    if (state.isActive) _startMonitoring();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('scope_active', state.isActive);
    if (state.dropPosition != null) {
      await prefs.setDouble('scope_lat', state.dropPosition!.latitude);
      await prefs.setDouble('scope_lon', state.dropPosition!.longitude);
    }
    await prefs.setDouble('scope_chain', state.chainLengthM);
    await prefs.setDouble('scope_depth', state.depthM);
    await prefs.setDouble('scope_freeboard', state.freeboard);
    await prefs.setDouble('scope_margin', state.safetyMarginM);
    await prefs.setBool('scope_in_feet', state.chainInFeet);
    await prefs.setInt('scope_formula', state.formula.index);
  }

  void dropAnchor(LatLng pos) {
    state = state.copyWith(
      isActive: true,
      dropPosition: pos,
      isDragging: false,
      currentDistanceM: 0,
      maxDistanceM: 0,
    );
    _alarmSent = false;
    _persist();
    _startMonitoring();
  }

  void releaseAnchor() {
    _timer?.cancel();
    _timer = null;
    _alarmSent = false;
    state = AnchorScopeState(
      chainLengthM: state.chainLengthM,
      chainInFeet: state.chainInFeet,
      depthM: state.depthM,
      freeboard: state.freeboard,
      safetyMarginM: state.safetyMarginM,
      formula: state.formula,
    );
    _persist();
  }

  void setChainLength(double metres) {
    state = state.copyWith(chainLengthM: metres);
    _persist();
  }

  void setDepth(double metres) {
    state = state.copyWith(depthM: metres);
    _persist();
  }

  void setFreeboard(double metres) {
    state = state.copyWith(freeboard: metres);
    _persist();
  }

  void setSafetyMargin(double metres) {
    state = state.copyWith(safetyMarginM: metres);
    _persist();
  }

  void setFormula(ScopeFormula f) {
    state = state.copyWith(formula: f);
    _persist();
  }

  void setChainInFeet(bool inFeet) {
    state = state.copyWith(chainInFeet: inFeet);
    _persist();
  }

  void _startMonitoring() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _check());
  }

  void _check() {
    if (!state.isActive || state.dropPosition == null) return;
    final vessel = _ref.read(vesselProvider);
    if (vessel.position == null) return;

    final dist = haversineDistanceM(state.dropPosition!, vessel.position!);
    final bearing = initialBearing(state.dropPosition!, vessel.position!);
    final radius = state.activeSwingRadius;
    final dragging = dist > radius;
    final maxDist = (state.maxDistanceM == null || dist > state.maxDistanceM!)
        ? dist
        : state.maxDistanceM!;

    state = state.copyWith(
      currentDistanceM: dist,
      bearingDeg: bearing,
      maxDistanceM: maxDist,
      isDragging: dragging,
    );

    if (dragging && !_alarmSent) {
      _alarmSent = true;
      HapticFeedback.heavyImpact();
      _sendServerAlert(dist, radius);
    } else if (!dragging) {
      _alarmSent = false;
    }
  }

  Future<void> _sendServerAlert(double distM, double radiusM) async {
    final pos = _ref.read(vesselProvider).position;
    if (pos == null) return;
    try {
      await FloatillaService.instance.postAnchorAlert(
        lat: pos.latitude,
        lng: pos.longitude,
        distanceM: distM,
        swingRadiusM: radiusM,
      );
    } catch (_) {
      // best-effort
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

final anchorScopeProvider =
    StateNotifierProvider<AnchorScopeNotifier, AnchorScopeState>((ref) {
  return AnchorScopeNotifier(ref);
});

// ─── Screen ────────────────────────────────────────────────────────────────

class AnchorScopeScreen extends ConsumerStatefulWidget {
  const AnchorScopeScreen({super.key});

  @override
  ConsumerState<AnchorScopeScreen> createState() => _AnchorScopeScreenState();
}

class _AnchorScopeScreenState extends ConsumerState<AnchorScopeScreen> {
  late TextEditingController _chainCtrl;
  late TextEditingController _depthCtrl;
  late TextEditingController _freeboardCtrl;
  late TextEditingController _marginCtrl;
  bool _synced = false;

  @override
  void initState() {
    super.initState();
    _chainCtrl = TextEditingController();
    _depthCtrl = TextEditingController();
    _freeboardCtrl = TextEditingController();
    _marginCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _chainCtrl.dispose();
    _depthCtrl.dispose();
    _freeboardCtrl.dispose();
    _marginCtrl.dispose();
    super.dispose();
  }

  void _syncControllersOnce(AnchorScopeState s) {
    if (_synced) return;
    _synced = true;
    final chain = s.chainInFeet
        ? (s.chainLengthM * 3.28084).toStringAsFixed(1)
        : s.chainLengthM.toStringAsFixed(1);
    _chainCtrl.text = chain;
    _depthCtrl.text = s.depthM.toStringAsFixed(1);
    _freeboardCtrl.text = s.freeboard.toStringAsFixed(1);
    _marginCtrl.text = s.safetyMarginM.toStringAsFixed(1);
  }

  Future<void> _dropAnchor(BuildContext context, WidgetRef ref) async {
    await ref.read(anchorProvider.notifier).requestNotificationPermission();
    await ref.read(vesselProvider.notifier).requestAlwaysPermission();
    HapticFeedback.heavyImpact();

    final pos = ref.read(vesselProvider).position;
    if (pos == null) return;

    // Pre-fill depth from Signal K if available
    final skDepth = ref
        .read(signalKEnvironmentProvider)
        .depthBelowKeel;
    if (skDepth != null && skDepth > 0) {
      ref.read(anchorScopeProvider.notifier).setDepth(skDepth);
      _depthCtrl.text = skDepth.toStringAsFixed(1);
    }

    ref.read(anchorScopeProvider.notifier).dropAnchor(pos);
  }

  void _onChainChanged(String v, AnchorScopeState s) {
    final val = double.tryParse(v);
    if (val == null || val <= 0) return;
    final metres = s.chainInFeet ? val / 3.28084 : val;
    ref.read(anchorScopeProvider.notifier).setChainLength(metres);
  }

  @override
  Widget build(BuildContext context) {
    final scope = ref.watch(anchorScopeProvider);
    final vessel = ref.watch(vesselProvider);
    final skEnv = ref.watch(signalKEnvironmentProvider);

    _syncControllersOnce(scope);

    // Auto-fill depth from Signal K when not watching
    if (!scope.isActive && skEnv.depthBelowKeel != null && skEnv.depthBelowKeel! > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final d = skEnv.depthBelowKeel!;
        final newText = d.toStringAsFixed(1);
        if (_depthCtrl.text != newText) {
          _depthCtrl.text = newText;
          ref.read(anchorScopeProvider.notifier).setDepth(d);
        }
      });
    }

    final layout = Responsive.of(context);
    final isTablet = layout != LayoutSize.compact;

    if (isTablet) {
      return Scaffold(
        appBar: AppBar(title: const Text('Anchor Watch')),
        body: Row(
          children: [
            SizedBox(
              width: 320,
              child: _InputPanel(
                scope: scope,
                vessel: vessel,
                chainCtrl: _chainCtrl,
                depthCtrl: _depthCtrl,
                freeboardCtrl: _freeboardCtrl,
                marginCtrl: _marginCtrl,
                onChainChanged: (v) => _onChainChanged(v, scope),
                onDepthChanged: (v) {
                  final val = double.tryParse(v);
                  if (val != null && val >= 0) {
                    ref.read(anchorScopeProvider.notifier).setDepth(val);
                  }
                },
                onFreeboardChanged: (v) {
                  final val = double.tryParse(v);
                  if (val != null && val >= 0) {
                    ref.read(anchorScopeProvider.notifier).setFreeboard(val);
                  }
                },
                onMarginChanged: (v) {
                  final val = double.tryParse(v);
                  if (val != null && val >= 0) {
                    ref.read(anchorScopeProvider.notifier).setSafetyMargin(val);
                  }
                },
                onToggleUnits: (inFeet) {
                  ref.read(anchorScopeProvider.notifier).setChainInFeet(inFeet);
                  final metres = scope.chainLengthM;
                  _chainCtrl.text = inFeet
                      ? (metres * 3.28084).toStringAsFixed(1)
                      : metres.toStringAsFixed(1);
                },
                onFormulaChanged: (f) {
                  ref.read(anchorScopeProvider.notifier).setFormula(f);
                },
                onDrop: vessel.position != null
                    ? () => _dropAnchor(context, ref)
                    : null,
                onRelease: () => ref.read(anchorScopeProvider.notifier).releaseAnchor(),
              ),
            ),
            const VerticalDivider(width: 1, thickness: 1),
            Expanded(child: _AnchorMap(scope: scope)),
          ],
        ),
      );
    }

    // Phone: vertical layout
    return Scaffold(
      appBar: AppBar(title: const Text('Anchor Watch')),
      body: Column(
        children: [
          _InputPanel(
            scope: scope,
            vessel: vessel,
            chainCtrl: _chainCtrl,
            depthCtrl: _depthCtrl,
            freeboardCtrl: _freeboardCtrl,
            marginCtrl: _marginCtrl,
            onChainChanged: (v) => _onChainChanged(v, scope),
            onDepthChanged: (v) {
              final val = double.tryParse(v);
              if (val != null && val >= 0) {
                ref.read(anchorScopeProvider.notifier).setDepth(val);
              }
            },
            onFreeboardChanged: (v) {
              final val = double.tryParse(v);
              if (val != null && val >= 0) {
                ref.read(anchorScopeProvider.notifier).setFreeboard(val);
              }
            },
            onMarginChanged: (v) {
              final val = double.tryParse(v);
              if (val != null && val >= 0) {
                ref.read(anchorScopeProvider.notifier).setSafetyMargin(val);
              }
            },
            onToggleUnits: (inFeet) {
              ref.read(anchorScopeProvider.notifier).setChainInFeet(inFeet);
              final metres = scope.chainLengthM;
              _chainCtrl.text = inFeet
                  ? (metres * 3.28084).toStringAsFixed(1)
                  : metres.toStringAsFixed(1);
            },
            onFormulaChanged: (f) {
              ref.read(anchorScopeProvider.notifier).setFormula(f);
            },
            onDrop: vessel.position != null
                ? () => _dropAnchor(context, ref)
                : null,
            onRelease: () => ref.read(anchorScopeProvider.notifier).releaseAnchor(),
          ),
          Expanded(child: _AnchorMap(scope: scope)),
        ],
      ),
    );
  }
}

// ─── Input panel ──────────────────────────────────────────────────────────

class _InputPanel extends StatelessWidget {
  const _InputPanel({
    required this.scope,
    required this.vessel,
    required this.chainCtrl,
    required this.depthCtrl,
    required this.freeboardCtrl,
    required this.marginCtrl,
    required this.onChainChanged,
    required this.onDepthChanged,
    required this.onFreeboardChanged,
    required this.onMarginChanged,
    required this.onToggleUnits,
    required this.onFormulaChanged,
    required this.onDrop,
    required this.onRelease,
  });

  final AnchorScopeState scope;
  final dynamic vessel;
  final TextEditingController chainCtrl;
  final TextEditingController depthCtrl;
  final TextEditingController freeboardCtrl;
  final TextEditingController marginCtrl;
  final ValueChanged<String> onChainChanged;
  final ValueChanged<String> onDepthChanged;
  final ValueChanged<String> onFreeboardChanged;
  final ValueChanged<String> onMarginChanged;
  final ValueChanged<bool> onToggleUnits;
  final ValueChanged<ScopeFormula> onFormulaChanged;
  final VoidCallback? onDrop;
  final VoidCallback onRelease;

  @override
  Widget build(BuildContext context) {
    final radius = scope.activeSwingRadius;
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag alert banner
          if (scope.isDragging)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'ANCHOR DRAGGING — '
                      '${scope.currentDistanceM?.toStringAsFixed(0) ?? '?'} m from anchor',
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),

          // Status row
          if (scope.isActive) ...[
            Row(
              children: [
                Icon(Icons.anchor,
                    color: scope.isDragging ? Colors.red : Colors.green),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Distance: ${scope.currentDistanceM?.toStringAsFixed(1) ?? '--'} m  '
                        '| Bearing: ${scope.bearingDeg?.toStringAsFixed(0) ?? '--'}',
                        style: theme.textTheme.bodySmall,
                      ),
                      Text(
                        'Max this session: ${scope.maxDistanceM?.toStringAsFixed(1) ?? '--'} m',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],

          // Scope display
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Swing radius', style: theme.textTheme.labelMedium),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      _RadioChip(
                        label:
                            'Catenary  ${scope.swingRadiusCatenary.toStringAsFixed(0)} m',
                        selected: scope.formula == ScopeFormula.catenary,
                        onTap: () => onFormulaChanged(ScopeFormula.catenary),
                      ),
                      const SizedBox(width: 8),
                      _RadioChip(
                        label:
                            '7:1 rule  ${scope.swingRadiusConservative.toStringAsFixed(0)} m',
                        selected: scope.formula == ScopeFormula.conservative,
                        onTap: () =>
                            onFormulaChanged(ScopeFormula.conservative),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Active radius: ${radius.toStringAsFixed(0)} m',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Chain length
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: chainCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText:
                        'Chain length (${scope.chainInFeet ? 'ft' : 'm'})',
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: onChainChanged,
                ),
              ),
              const SizedBox(width: 8),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('m')),
                  ButtonSegment(value: true, label: Text('ft')),
                ],
                selected: {scope.chainInFeet},
                onSelectionChanged: (s) => onToggleUnits(s.first),
                style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // Depth
          TextField(
            controller: depthCtrl,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Depth below keel (m)',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: onDepthChanged,
          ),

          const SizedBox(height: 10),

          // Freeboard
          TextField(
            controller: freeboardCtrl,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Bow height above water (m)',
              border: OutlineInputBorder(),
              isDense: true,
              helperText: 'Default 1.5 m',
            ),
            onChanged: onFreeboardChanged,
          ),

          const SizedBox(height: 10),

          // Safety margin
          TextField(
            controller: marginCtrl,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Safety margin (m)',
              border: OutlineInputBorder(),
              isDense: true,
              helperText: 'Default 10 m',
            ),
            onChanged: onMarginChanged,
          ),

          const SizedBox(height: 16),

          // Drop / Release
          if (!scope.isActive)
            FilledButton.icon(
              onPressed: onDrop,
              icon: const Icon(Icons.anchor),
              label: const Text('Drop Anchor Here'),
              style: FilledButton.styleFrom(padding: const EdgeInsets.all(14)),
            )
          else
            OutlinedButton.icon(
              onPressed: onRelease,
              icon: const Icon(Icons.clear),
              label: const Text('Release Anchor'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                padding: const EdgeInsets.all(14),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Map ──────────────────────────────────────────────────────────────────

class _AnchorMap extends ConsumerWidget {
  const _AnchorMap({required this.scope});
  final AnchorScopeState scope;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vessel = ref.watch(vesselProvider);
    final skEnv = ref.watch(signalKEnvironmentProvider);

    final center = scope.dropPosition ??
        vessel.position ??
        const LatLng(57.7, 11.9); // fallback

    final radius = scope.activeSwingRadius;

    // TWD from Signal K (degrees true)
    final twd = skEnv.windAngleTrueGround;
    final circleColor = scope.isDragging ? Colors.red : Colors.blue;

    return FlutterMap(
      options: MapOptions(
        initialCenter: center,
        initialZoom: 15,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.floatilla.app',
        ),
        // Scope circle
        CircleLayer(
          circles: [
            CircleMarker(
              point: center,
              radius: radius,
              useRadiusInMeter: true,
              color: circleColor.withValues(alpha: 0.12),
              borderColor: circleColor,
              borderStrokeWidth: 2,
            ),
          ],
        ),
        // Anchor icon
        MarkerLayer(
          markers: [
            Marker(
              point: center,
              width: 40,
              height: 40,
              child: Icon(
                Icons.anchor,
                size: 32,
                color: scope.isDragging ? Colors.red : Colors.teal.shade700,
              ),
            ),
          ],
        ),
        // Wind direction arc
        if (twd != null && scope.isActive)
          _WindArcLayer(
            anchor: center,
            radius: radius,
            twdDeg: twd,
          ),
        // Vessel position
        if (vessel.position != null)
          MarkerLayer(
            markers: [
              Marker(
                point: vessel.position!,
                width: 24,
                height: 24,
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: scope.isDragging
                        ? Colors.red
                        : Colors.blueAccent,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }
}

// ─── Wind arc overlay ─────────────────────────────────────────────────────

class _WindArcLayer extends StatelessWidget {
  const _WindArcLayer({
    required this.anchor,
    required this.radius,
    required this.twdDeg,
  });

  final LatLng anchor;
  final double radius;
  final double twdDeg;

  @override
  Widget build(BuildContext context) {
    // Wind comes FROM twdDeg, boat swings downwind — arc ±45 deg from downwind direction
    final downwind = (twdDeg + 180) % 360;
    final arcStart = (downwind - 45) % 360;
    final arcEnd = (downwind + 45) % 360;

    // Build a wedge of points for the wind arc
    final points = <LatLng>[];
    points.add(anchor);
    for (var deg = arcStart; ; deg = (deg + 5) % 360) {
      points.add(destinationPoint(anchor, deg, radius));
      if ((deg - arcStart).abs() >= 90 || deg == arcEnd) break;
      // guard infinite loop
      if (points.length > 50) break;
    }
    points.add(destinationPoint(anchor, arcEnd, radius));
    points.add(anchor);

    return PolygonLayer(
      polygons: [
        Polygon(
          points: points,
          color: Colors.amber.withValues(alpha: 0.18),
          borderColor: Colors.amber.shade700,
          borderStrokeWidth: 1.5,
        ),
      ],
    );
  }
}

// ─── Small helpers ────────────────────────────────────────────────────────

class _RadioChip extends StatelessWidget {
  const _RadioChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? scheme.primaryContainer : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? scheme.primary : scheme.outlineVariant,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: selected ? scheme.onPrimaryContainer : scheme.onSurface,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
