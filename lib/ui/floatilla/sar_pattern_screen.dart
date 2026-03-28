import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

// ─────────────────────────────────────────────────────────────────
//  Models
// ─────────────────────────────────────────────────────────────────

enum SarPatternType { expandingSquare, sectorSearch, parallelTrack }

class LatLng {
  final double lat;
  final double lng;
  const LatLng(this.lat, this.lng);

  Map<String, dynamic> toJson() => {'lat': lat, 'lng': lng};
  factory LatLng.fromJson(Map<String, dynamic> j) =>
      LatLng((j['lat'] as num).toDouble(), (j['lng'] as num).toDouble());
}

class SarLeg {
  final LatLng start;
  final LatLng end;
  final double bearingDeg;
  final double distanceNm;
  final int legNumber;

  const SarLeg({
    required this.start,
    required this.end,
    required this.bearingDeg,
    required this.distanceNm,
    required this.legNumber,
  });
}

class SarPlan {
  final SarPatternType type;
  final LatLng datum;
  final double trackSpacingNm;
  final double initialBearingDeg;
  final double vesselSpeedKt;
  final int numLegs;           // for expanding square / parallel
  final double sectorRadiusNm; // for sector search
  final int numSectors;        // for sector search

  const SarPlan({
    required this.type,
    required this.datum,
    required this.trackSpacingNm,
    required this.initialBearingDeg,
    required this.vesselSpeedKt,
    required this.numLegs,
    required this.sectorRadiusNm,
    required this.numSectors,
  });

  Map<String, dynamic> toJson() => {
        'type': type.index,
        'datum': datum.toJson(),
        'trackSpacingNm': trackSpacingNm,
        'initialBearingDeg': initialBearingDeg,
        'vesselSpeedKt': vesselSpeedKt,
        'numLegs': numLegs,
        'sectorRadiusNm': sectorRadiusNm,
        'numSectors': numSectors,
      };

  factory SarPlan.fromJson(Map<String, dynamic> j) => SarPlan(
        type: SarPatternType.values[(j['type'] as num).toInt()],
        datum: LatLng.fromJson(j['datum'] as Map<String, dynamic>),
        trackSpacingNm: (j['trackSpacingNm'] as num).toDouble(),
        initialBearingDeg: (j['initialBearingDeg'] as num).toDouble(),
        vesselSpeedKt: (j['vesselSpeedKt'] as num).toDouble(),
        numLegs: (j['numLegs'] as num).toInt(),
        sectorRadiusNm: (j['sectorRadiusNm'] as num).toDouble(),
        numSectors: (j['numSectors'] as num).toInt(),
      );
}

// ─────────────────────────────────────────────────────────────────
//  Geometry helpers (NM ↔ degrees, bearing, destination)
// ─────────────────────────────────────────────────────────────────

const _nmPerDeg = 60.0;  // 1° latitude ≈ 60 NM

LatLng _destination(LatLng origin, double bearingDeg, double distanceNm) {
  final R = 6371000.0; // Earth radius metres
  final d = distanceNm * 1852.0;
  final lat1 = origin.lat * math.pi / 180;
  final lon1 = origin.lng * math.pi / 180;
  final brng = bearingDeg * math.pi / 180;

  final lat2 = math.asin(math.sin(lat1) * math.cos(d / R) +
      math.cos(lat1) * math.sin(d / R) * math.cos(brng));
  final lon2 = lon1 +
      math.atan2(math.sin(brng) * math.sin(d / R) * math.cos(lat1),
          math.cos(d / R) - math.sin(lat1) * math.sin(lat2));

  return LatLng(lat2 * 180 / math.pi, lon2 * 180 / math.pi);
}

double _bearing(LatLng from, LatLng to) {
  final lat1 = from.lat * math.pi / 180;
  final lat2 = to.lat * math.pi / 180;
  final dLon = (to.lng - from.lng) * math.pi / 180;
  final y = math.sin(dLon) * math.cos(lat2);
  final x = math.cos(lat1) * math.sin(lat2) -
      math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
  return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
}

double _haversineNm(LatLng a, LatLng b) {
  const R = 3440.065; // NM
  final dLat = (b.lat - a.lat) * math.pi / 180;
  final dLon = (b.lng - a.lng) * math.pi / 180;
  final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(a.lat * math.pi / 180) *
          math.cos(b.lat * math.pi / 180) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);
  return 2 * R * math.asin(math.sqrt(h));
}

// ─────────────────────────────────────────────────────────────────
//  Pattern calculators
// ─────────────────────────────────────────────────────────────────

List<SarLeg> _expandingSquare(SarPlan p) {
  // IAMSAR expanding square: from datum, legs increase by S every two turns
  // Headings rotate 90° right each leg.
  final List<SarLeg> legs = [];
  var pos = p.datum;
  final S = p.trackSpacingNm;
  double brng = p.initialBearingDeg;
  int legNum = 0;

  // Pattern: 1×S, 1×S, 2×S, 2×S, 3×S, 3×S …
  int n = math.min(p.numLegs, 40);
  for (int i = 0; i < n; i++) {
    final legDist = ((i ~/ 2) + 1) * S;
    final end = _destination(pos, brng, legDist);
    legs.add(SarLeg(
      start: pos,
      end: end,
      bearingDeg: brng,
      distanceNm: legDist,
      legNumber: ++legNum,
    ));
    pos = end;
    brng = (brng + 90) % 360;
  }
  return legs;
}

List<SarLeg> _sectorSearch(SarPlan p) {
  // IAMSAR sector search: radial legs from datum, rotating by 360/numSectors each sweep
  final List<SarLeg> legs = [];
  final n = p.numSectors.clamp(3, 12);
  final sectorAngle = 360.0 / n;
  int legNum = 0;

  for (int s = 0; s < n; s++) {
    final outBrng = (p.initialBearingDeg + s * sectorAngle) % 360;
    final outEnd = _destination(p.datum, outBrng, p.sectorRadiusNm);
    legs.add(SarLeg(
      start: p.datum,
      end: outEnd,
      bearingDeg: outBrng,
      distanceNm: p.sectorRadiusNm,
      legNumber: ++legNum,
    ));
    // Return to datum
    final retBrng = (outBrng + 180) % 360;
    legs.add(SarLeg(
      start: outEnd,
      end: p.datum,
      bearingDeg: retBrng,
      distanceNm: p.sectorRadiusNm,
      legNumber: ++legNum,
    ));
  }
  return legs;
}

List<SarLeg> _parallelTrack(SarPlan p) {
  // Parallel track sweep: N legs spaced S NM apart, alternating direction
  final List<SarLeg> legs = [];
  final S = p.trackSpacingNm;
  final n = p.numLegs.clamp(2, 30);
  final legLengthNm = S * n * 0.8; // sensible default leg length

  // Perpendicular direction for spacing
  final perpBrng = (p.initialBearingDeg + 90) % 360;
  int legNum = 0;

  for (int i = 0; i < n; i++) {
    final startOffset = _destination(p.datum, perpBrng, (i - n / 2) * S);
    final brng = i.isEven ? p.initialBearingDeg : (p.initialBearingDeg + 180) % 360;
    final end = _destination(startOffset, brng, legLengthNm);
    legs.add(SarLeg(
      start: startOffset,
      end: end,
      bearingDeg: brng,
      distanceNm: legLengthNm,
      legNumber: ++legNum,
    ));
  }
  return legs;
}

List<SarLeg> calculateLegs(SarPlan p) {
  switch (p.type) {
    case SarPatternType.expandingSquare:
      return _expandingSquare(p);
    case SarPatternType.sectorSearch:
      return _sectorSearch(p);
    case SarPatternType.parallelTrack:
      return _parallelTrack(p);
  }
}

// ─────────────────────────────────────────────────────────────────
//  Provider
// ─────────────────────────────────────────────────────────────────

const _kPrefKey = 'sar_plan_v1';

final sarPlanProvider =
    StateNotifierProvider<SarPlanNotifier, SarPlan>((ref) => SarPlanNotifier());

class SarPlanNotifier extends StateNotifier<SarPlan> {
  SarPlanNotifier()
      : super(const SarPlan(
          type: SarPatternType.expandingSquare,
          datum: LatLng(0, 0),
          trackSpacingNm: 0.5,
          initialBearingDeg: 0,
          vesselSpeedKt: 6,
          numLegs: 8,
          sectorRadiusNm: 1.0,
          numSectors: 6,
        )) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString(_kPrefKey);
    if (s != null) {
      try {
        state = SarPlan.fromJson(jsonDecode(s) as Map<String, dynamic>);
      } catch (_) {}
    }
  }

  Future<void> update(SarPlan p) async {
    state = p;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPrefKey, jsonEncode(p.toJson()));
  }
}

// ─────────────────────────────────────────────────────────────────
//  Screen
// ─────────────────────────────────────────────────────────────────

class SarPatternScreen extends ConsumerStatefulWidget {
  const SarPatternScreen({super.key});

  @override
  ConsumerState<SarPatternScreen> createState() => _SarPatternScreenState();
}

class _SarPatternScreenState extends ConsumerState<SarPatternScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;

  // Form controllers
  final _latCtrl = TextEditingController(text: '0.000000');
  final _lonCtrl = TextEditingController(text: '0.000000');
  final _spacingCtrl = TextEditingController(text: '0.5');
  final _bearingCtrl = TextEditingController(text: '0');
  final _speedCtrl = TextEditingController(text: '6');
  final _numLegsCtrl = TextEditingController(text: '8');
  final _sectorRadCtrl = TextEditingController(text: '1.0');
  final _numSectorsCtrl = TextEditingController(text: '6');

  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    for (final c in [
      _latCtrl, _lonCtrl, _spacingCtrl, _bearingCtrl,
      _speedCtrl, _numLegsCtrl, _sectorRadCtrl, _numSectorsCtrl
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _syncFromState(SarPlan p) {
    if (_dirty) return;
    _latCtrl.text = p.datum.lat.toStringAsFixed(6);
    _lonCtrl.text = p.datum.lng.toStringAsFixed(6);
    _spacingCtrl.text = p.trackSpacingNm.toString();
    _bearingCtrl.text = p.initialBearingDeg.toStringAsFixed(0);
    _speedCtrl.text = p.vesselSpeedKt.toString();
    _numLegsCtrl.text = p.numLegs.toString();
    _sectorRadCtrl.text = p.sectorRadiusNm.toString();
    _numSectorsCtrl.text = p.numSectors.toString();
  }

  SarPlan _buildPlan(SarPlan current) {
    double parseDouble(TextEditingController c, double fallback) =>
        double.tryParse(c.text) ?? fallback;
    int parseInt(TextEditingController c, int fallback) =>
        int.tryParse(c.text) ?? fallback;

    return SarPlan(
      type: current.type,
      datum: LatLng(
        parseDouble(_latCtrl, 0),
        parseDouble(_lonCtrl, 0),
      ),
      trackSpacingNm: parseDouble(_spacingCtrl, 0.5),
      initialBearingDeg: parseDouble(_bearingCtrl, 0),
      vesselSpeedKt: parseDouble(_speedCtrl, 6),
      numLegs: parseInt(_numLegsCtrl, 8),
      sectorRadiusNm: parseDouble(_sectorRadCtrl, 1.0),
      numSectors: parseInt(_numSectorsCtrl, 6),
    );
  }

  @override
  Widget build(BuildContext context) {
    final plan = ref.watch(sarPlanProvider);
    _syncFromState(plan);
    final legs = calculateLegs(plan);
    final totalDist = legs.fold(0.0, (s, l) => s + l.distanceNm);
    final totalTimeH = plan.vesselSpeedKt > 0 ? totalDist / plan.vesselSpeedKt : 0.0;
    final totalTimeMin = (totalTimeH * 60).round();

    return Scaffold(
      appBar: AppBar(
        title: const Text('SAR Pattern Planner'),
        bottom: TabBar(
          controller: _tab,
          tabs: const [
            Tab(icon: Icon(Icons.tune), text: 'Plan'),
            Tab(icon: Icon(Icons.list_alt), text: 'Legs'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          _buildPlanTab(plan, legs, totalDist, totalTimeMin),
          _buildLegsTab(legs, plan.vesselSpeedKt),
        ],
      ),
    );
  }

  Widget _buildPlanTab(
      SarPlan plan, List<SarLeg> legs, double totalDist, int totalTimeMin) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Pattern type selector ──────────────────────────────
          _sectionHeader('Pattern Type'),
          Wrap(
            spacing: 8,
            children: SarPatternType.values.map((t) {
              final labels = ['Expanding Square', 'Sector Search', 'Parallel Track'];
              final icons = [Icons.crop_square, Icons.pie_chart_outline, Icons.view_week];
              return ChoiceChip(
                avatar: Icon(icons[t.index], size: 18),
                label: Text(labels[t.index]),
                selected: plan.type == t,
                onSelected: (_) {
                  _dirty = true;
                  final updated = _buildPlan(plan).copyWith(type: t);
                  ref.read(sarPlanProvider.notifier).update(updated);
                  Future.delayed(const Duration(milliseconds: 100),
                      () => _dirty = false);
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 16),

          // ── Datum ──────────────────────────────────────────────
          _sectionHeader('Last Known Position (Datum)'),
          Row(
            children: [
              Expanded(
                child: _numField('Latitude (°)', _latCtrl,
                    hint: '59.123456', plan: plan),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _numField('Longitude (°)', _lonCtrl,
                    hint: '18.123456', plan: plan),
              ),
            ],
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.my_location, size: 18),
            label: const Text('Use GPS Position'),
            onPressed: () => _showGpsNotice(context),
          ),
          const SizedBox(height: 16),

          // ── Common params ──────────────────────────────────────
          _sectionHeader('Search Parameters'),
          Row(
            children: [
              Expanded(
                  child: _numField('Initial Bearing (°T)', _bearingCtrl,
                      hint: '0–360', plan: plan)),
              const SizedBox(width: 12),
              Expanded(
                  child: _numField('Vessel Speed (kt)', _speedCtrl,
                      hint: '6', plan: plan)),
            ],
          ),
          const SizedBox(height: 8),

          if (plan.type != SarPatternType.sectorSearch) ...[
            Row(
              children: [
                Expanded(
                    child: _numField('Track Spacing (NM)', _spacingCtrl,
                        hint: '0.5', plan: plan)),
                const SizedBox(width: 12),
                Expanded(
                    child: _numField(
                        plan.type == SarPatternType.expandingSquare
                            ? 'Number of Legs'
                            : 'Number of Tracks',
                        _numLegsCtrl,
                        hint: '8',
                        plan: plan)),
              ],
            ),
          ],

          if (plan.type == SarPatternType.sectorSearch) ...[
            Row(
              children: [
                Expanded(
                    child: _numField('Sector Radius (NM)', _sectorRadCtrl,
                        hint: '1.0', plan: plan)),
                const SizedBox(width: 12),
                Expanded(
                    child: _numField('Number of Sectors', _numSectorsCtrl,
                        hint: '6', plan: plan)),
              ],
            ),
          ],

          const SizedBox(height: 16),

          // ── Apply button ───────────────────────────────────────
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              icon: const Icon(Icons.calculate),
              label: const Text('Calculate Pattern'),
              onPressed: () {
                _dirty = true;
                final updated = _buildPlan(plan);
                ref.read(sarPlanProvider.notifier).update(updated);
                Future.delayed(
                    const Duration(milliseconds: 100), () => _dirty = false);
                _tab.animateTo(1);
              },
            ),
          ),
          const SizedBox(height: 16),

          // ── Summary card ───────────────────────────────────────
          if (legs.isNotEmpty) ...[
            _sectionHeader('Summary'),
            _SarSummaryCard(
              plan: plan,
              legs: legs,
              totalDistNm: totalDist,
              totalTimeMin: totalTimeMin,
            ),
          ],

          const SizedBox(height: 16),
          // ── Pattern visualiser ─────────────────────────────────
          _sectionHeader('Pattern Preview'),
          Container(
            height: 320,
            decoration: BoxDecoration(
              color: Colors.blueGrey.shade900,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blueGrey.shade700),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: _SarPatternPainter(legs: legs, datum: plan.datum),
            ),
          ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _buildLegsTab(List<SarLeg> legs, double speedKt) {
    if (legs.isEmpty) {
      return const Center(
        child: Text('Set plan parameters and tap Calculate Pattern.'),
      );
    }
    double cumDist = 0;
    return Column(
      children: [
        Container(
          color: Theme.of(context).colorScheme.surfaceVariant,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              _legHeader('Leg', flex: 1),
              _legHeader('Bearing', flex: 2),
              _legHeader('Dist (NM)', flex: 2),
              _legHeader('ETE', flex: 2),
              _legHeader('Cum (NM)', flex: 2),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            itemCount: legs.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (ctx, i) {
              final leg = legs[i];
              cumDist += leg.distanceNm;
              final eteMin = speedKt > 0
                  ? (leg.distanceNm / speedKt * 60).round()
                  : 0;
              return Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                        flex: 1,
                        child: Text('${leg.legNumber}',
                            style: const TextStyle(fontWeight: FontWeight.bold))),
                    Expanded(
                        flex: 2,
                        child: Text(
                            '${leg.bearingDeg.toStringAsFixed(0)}°T')),
                    Expanded(
                        flex: 2,
                        child: Text(leg.distanceNm.toStringAsFixed(2))),
                    Expanded(
                        flex: 2, child: Text('${eteMin}m')),
                    Expanded(
                        flex: 2,
                        child: Text(cumDist.toStringAsFixed(2),
                            style: TextStyle(
                                color:
                                    Theme.of(context).colorScheme.primary))),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _legHeader(String label, {int flex = 1}) => Expanded(
        flex: flex,
        child: Text(label,
            style: const TextStyle(
                fontWeight: FontWeight.bold, fontSize: 12)),
      );

  Widget _sectionHeader(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(t,
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(color: Theme.of(context).colorScheme.primary)),
      );

  Widget _numField(String label, TextEditingController ctrl,
      {String? hint, required SarPlan plan}) {
    return TextField(
      controller: ctrl,
      keyboardType: const TextInputType.numberWithOptions(
          decimal: true, signed: true),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        isDense: true,
        border: const OutlineInputBorder(),
      ),
      onChanged: (_) => _dirty = true,
    );
  }

  void _showGpsNotice(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
            'Connect Signal K / NMEA and the datum will auto-fill from GPS.'),
        duration: Duration(seconds: 3),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
//  Summary card
// ─────────────────────────────────────────────────────────────────

class _SarSummaryCard extends StatelessWidget {
  final SarPlan plan;
  final List<SarLeg> legs;
  final double totalDistNm;
  final int totalTimeMin;

  const _SarSummaryCard({
    required this.plan,
    required this.legs,
    required this.totalDistNm,
    required this.totalTimeMin,
  });

  @override
  Widget build(BuildContext context) {
    final typeLabels = ['Expanding Square', 'Sector Search', 'Parallel Track'];
    final h = totalTimeMin ~/ 60;
    final m = totalTimeMin % 60;
    final timeStr = h > 0 ? '${h}h ${m}m' : '${m}m';

    // Estimate covered area (rough)
    double areaSqNm = 0;
    if (plan.type == SarPatternType.expandingSquare) {
      final side = ((plan.numLegs ~/ 2) + 1) * plan.trackSpacingNm;
      areaSqNm = side * side;
    } else if (plan.type == SarPatternType.sectorSearch) {
      areaSqNm = math.pi * plan.sectorRadiusNm * plan.sectorRadiusNm;
    } else {
      final legLen = plan.trackSpacingNm * plan.numLegs * 0.8;
      areaSqNm = legLen * plan.numLegs * plan.trackSpacingNm;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _row(context, 'Pattern', typeLabels[plan.type.index]),
            _row(context, 'Datum',
                '${plan.datum.lat.toStringAsFixed(4)}°N  ${plan.datum.lng.toStringAsFixed(4)}°E'),
            _row(context, 'Total Legs', '${legs.length}'),
            _row(context, 'Total Distance', '${totalDistNm.toStringAsFixed(1)} NM'),
            _row(context, 'Est. Time', timeStr),
            _row(context, 'Search Area', '≈ ${areaSqNm.toStringAsFixed(1)} NM²'),
            if (plan.type != SarPatternType.sectorSearch)
              _row(context, 'Track Spacing', '${plan.trackSpacingNm} NM'),
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext ctx, String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            SizedBox(
              width: 130,
              child: Text(k,
                  style: const TextStyle(
                      fontWeight: FontWeight.w500, fontSize: 13)),
            ),
            Expanded(child: Text(v, style: const TextStyle(fontSize: 13))),
          ],
        ),
      );
}

// ─────────────────────────────────────────────────────────────────
//  Pattern painter (canvas visualisation)
// ─────────────────────────────────────────────────────────────────

class _SarPatternPainter extends StatelessWidget {
  final List<SarLeg> legs;
  final LatLng datum;

  const _SarPatternPainter({required this.legs, required this.datum});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(double.infinity, 320),
      painter: _SarPainter(legs: legs, datum: datum),
    );
  }
}

class _SarPainter extends CustomPainter {
  final List<SarLeg> legs;
  final LatLng datum;

  _SarPainter({required this.legs, required this.datum});

  @override
  void paint(Canvas canvas, Size size) {
    if (legs.isEmpty) return;

    // Collect all points
    final allPts = <LatLng>[datum];
    for (final l in legs) {
      allPts.add(l.start);
      allPts.add(l.end);
    }

    double minLat = allPts.map((p) => p.lat).reduce(math.min);
    double maxLat = allPts.map((p) => p.lat).reduce(math.max);
    double minLon = allPts.map((p) => p.lng).reduce(math.min);
    double maxLon = allPts.map((p) => p.lng).reduce(math.max);

    // Add 10% margin
    final latRange = (maxLat - minLat).abs() + 0.0001;
    final lonRange = (maxLon - minLon).abs() + 0.0001;
    minLat -= latRange * 0.1;
    maxLat += latRange * 0.1;
    minLon -= lonRange * 0.1;
    maxLon += lonRange * 0.1;

    Offset toScreen(LatLng p) {
      final x = (p.lng - minLon) / (maxLon - minLon) * size.width;
      final y = size.height - (p.lat - minLat) / (maxLat - minLat) * size.height;
      return Offset(x, y);
    }

    // Background
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = const Color(0xFF0D1B2A),
    );

    // Draw legs with colour gradient
    final colours = [
      Colors.cyan,
      Colors.lightBlue,
      Colors.teal,
      Colors.green,
      Colors.lime,
      Colors.yellow,
      Colors.orange,
      Colors.deepOrange,
    ];

    for (int i = 0; i < legs.length; i++) {
      final leg = legs[i];
      final colour = colours[i % colours.length];
      final paint = Paint()
        ..color = colour.withOpacity(0.85)
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      final s = toScreen(leg.start);
      final e = toScreen(leg.end);
      canvas.drawLine(s, e, paint);

      // Arrow at midpoint indicating direction
      final mid = Offset((s.dx + e.dx) / 2, (s.dy + e.dy) / 2);
      final dx = e.dx - s.dx;
      final dy = e.dy - s.dy;
      final len = math.sqrt(dx * dx + dy * dy);
      if (len > 10) {
        final nx = dx / len;
        final ny = dy / len;
        const arrowSize = 6.0;
        final p1 = Offset(
            mid.dx - arrowSize * nx + arrowSize * 0.5 * ny,
            mid.dy - arrowSize * ny - arrowSize * 0.5 * nx);
        final p2 = Offset(
            mid.dx - arrowSize * nx - arrowSize * 0.5 * ny,
            mid.dy - arrowSize * ny + arrowSize * 0.5 * nx);
        final arrowPath = Path()
          ..moveTo(mid.dx, mid.dy)
          ..lineTo(p1.dx, p1.dy)
          ..moveTo(mid.dx, mid.dy)
          ..lineTo(p2.dx, p2.dy);
        canvas.drawPath(arrowPath, paint..strokeWidth = 1.5);
      }

      // Leg number
      if (legs.length <= 20) {
        final tp = TextPainter(
          text: TextSpan(
            text: '${leg.legNumber}',
            style: TextStyle(
                color: colour.withOpacity(0.9),
                fontSize: 9,
                fontWeight: FontWeight.bold),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, mid.translate(3, -8));
      }
    }

    // Datum marker (red X)
    final datumPt = toScreen(datum);
    final datumPaint = Paint()
      ..color = Colors.red
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    const crossSize = 7.0;
    canvas.drawLine(
        datumPt.translate(-crossSize, -crossSize),
        datumPt.translate(crossSize, crossSize),
        datumPaint);
    canvas.drawLine(
        datumPt.translate(crossSize, -crossSize),
        datumPt.translate(-crossSize, crossSize),
        datumPaint);

    // Datum label
    final dtTp = TextPainter(
      text: const TextSpan(
        text: 'DATUM',
        style: TextStyle(
            color: Colors.red, fontSize: 10, fontWeight: FontWeight.bold),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    dtTp.paint(canvas, datumPt.translate(8, -6));
  }

  @override
  bool shouldRepaint(_SarPainter old) =>
      old.legs != legs || old.datum.lat != datum.lat || old.datum.lng != datum.lng;
}

// ─────────────────────────────────────────────────────────────────
//  SarPlan.copyWith helper
// ─────────────────────────────────────────────────────────────────

extension _SarPlanCopy on SarPlan {
  SarPlan copyWith({
    SarPatternType? type,
    LatLng? datum,
    double? trackSpacingNm,
    double? initialBearingDeg,
    double? vesselSpeedKt,
    int? numLegs,
    double? sectorRadiusNm,
    int? numSectors,
  }) =>
      SarPlan(
        type: type ?? this.type,
        datum: datum ?? this.datum,
        trackSpacingNm: trackSpacingNm ?? this.trackSpacingNm,
        initialBearingDeg: initialBearingDeg ?? this.initialBearingDeg,
        vesselSpeedKt: vesselSpeedKt ?? this.vesselSpeedKt,
        numLegs: numLegs ?? this.numLegs,
        sectorRadiusNm: sectorRadiusNm ?? this.sectorRadiusNm,
        numSectors: numSectors ?? this.numSectors,
      );
}
