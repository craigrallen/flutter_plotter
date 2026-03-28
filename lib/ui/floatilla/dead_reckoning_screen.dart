import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/signalk/signalk_source.dart';
import '../../data/providers/signalk_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Constants & helpers
// ─────────────────────────────────────────────────────────────────────────────

const double _kEarthRadiusM = 6371000.0;
const String _kPrefsKey = 'dr_fixes';

double _degToRad(double deg) => deg * math.pi / 180.0;
double _radToDeg(double rad) => rad * 180.0 / math.pi;

/// Haversine: project a position forward by [distanceM] metres along [bearingDeg].
_LatLon _projectPosition(_LatLon origin, double bearingDeg, double distanceM) {
  final lat1 = _degToRad(origin.lat);
  final lon1 = _degToRad(origin.lon);
  final bearing = _degToRad(bearingDeg);
  final angDist = distanceM / _kEarthRadiusM;

  final lat2 = math.asin(
    math.sin(lat1) * math.cos(angDist) +
        math.cos(lat1) * math.sin(angDist) * math.cos(bearing),
  );
  final lon2 = lon1 +
      math.atan2(
        math.sin(bearing) * math.sin(angDist) * math.cos(lat1),
        math.cos(angDist) - math.sin(lat1) * math.sin(lat2),
      );

  return _LatLon(lat: _radToDeg(lat2), lon: _radToDeg(lon2));
}

// ─────────────────────────────────────────────────────────────────────────────
// Value types
// ─────────────────────────────────────────────────────────────────────────────

class _LatLon {
  final double lat;
  final double lon;
  const _LatLon({required this.lat, required this.lon});

  Map<String, dynamic> toJson() => {'lat': lat, 'lon': lon};

  factory _LatLon.fromJson(Map<String, dynamic> j) =>
      _LatLon(lat: (j['lat'] as num).toDouble(), lon: (j['lon'] as num).toDouble());

  String toDisplayString() {
    final latDir = lat >= 0 ? 'N' : 'S';
    final lonDir = lon >= 0 ? 'E' : 'W';
    return '${_dmm(lat.abs())} $latDir   ${_dmm(lon.abs())} $lonDir';
  }

  String _dmm(double deg) {
    final d = deg.truncate();
    final m = (deg - d) * 60.0;
    return '$d° ${m.toStringAsFixed(3)}\'';
  }
}

/// A saved DR fix (last known position + course/speed).
class DrFix {
  final String id;
  final DateTime time;
  final _LatLon position;
  final double courseTrue; // degrees true
  final double speedKts;
  final String? label;

  const DrFix({
    required this.id,
    required this.time,
    required this.position,
    required this.courseTrue,
    required this.speedKts,
    this.label,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'time': time.toIso8601String(),
        'position': position.toJson(),
        'courseTrue': courseTrue,
        'speedKts': speedKts,
        if (label != null) 'label': label,
      };

  factory DrFix.fromJson(Map<String, dynamic> j) => DrFix(
        id: j['id'] as String,
        time: DateTime.parse(j['time'] as String),
        position: _LatLon.fromJson(j['position'] as Map<String, dynamic>),
        courseTrue: (j['courseTrue'] as num).toDouble(),
        speedKts: (j['speedKts'] as num).toDouble(),
        label: j['label'] as String?,
      );
}

/// Computed projection from a fix.
class _DrProjection {
  final _LatLon position;
  final double distanceNm;

  const _DrProjection({required this.position, required this.distanceNm});

  factory _DrProjection.compute(DrFix fix, Duration elapsed) {
    final hours = elapsed.inSeconds / 3600.0;
    final distNm = fix.speedKts * hours;
    final distM = distNm * 1852.0;
    final pos = _projectPosition(fix.position, fix.courseTrue, distM);
    return _DrProjection(position: pos, distanceNm: distNm);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// State + notifier
// ─────────────────────────────────────────────────────────────────────────────

class _DrState {
  final List<DrFix> fixes;
  final Duration lookAhead;
  final bool isLoading;

  const _DrState({
    this.fixes = const [],
    this.lookAhead = const Duration(hours: 1),
    this.isLoading = true,
  });

  _DrState copyWith({List<DrFix>? fixes, Duration? lookAhead, bool? isLoading}) =>
      _DrState(
        fixes: fixes ?? this.fixes,
        lookAhead: lookAhead ?? this.lookAhead,
        isLoading: isLoading ?? this.isLoading,
      );
}

class _DrNotifier extends StateNotifier<_DrState> {
  _DrNotifier() : super(const _DrState()) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_kPrefsKey) ?? [];
    final fixes = raw
        .map((s) {
          try {
            final decoded = jsonDecode(s);
            if (decoded is Map<String, dynamic>) {
              return DrFix.fromJson(decoded);
            }
          } catch (_) {}
          return null;
        })
        .whereType<DrFix>()
        .toList()
      ..sort((a, b) => b.time.compareTo(a.time));
    state = state.copyWith(fixes: fixes, isLoading: false);
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
        _kPrefsKey, state.fixes.map((f) => jsonEncode(f.toJson())).toList());
  }

  Future<void> addFix(DrFix fix) async {
    final updated = [fix, ...state.fixes];
    state = state.copyWith(fixes: updated);
    await _persist();
  }

  Future<void> removeFix(String id) async {
    final updated = state.fixes.where((f) => f.id != id).toList();
    state = state.copyWith(fixes: updated);
    await _persist();
  }

  void setLookAhead(Duration d) => state = state.copyWith(lookAhead: d);
}

final _drProvider = StateNotifierProvider<_DrNotifier, _DrState>(
  (_) => _DrNotifier(),
);

// ─────────────────────────────────────────────────────────────────────────────
// Screen
// ─────────────────────────────────────────────────────────────────────────────

class DeadReckoningScreen extends ConsumerStatefulWidget {
  const DeadReckoningScreen({super.key});

  @override
  ConsumerState<DeadReckoningScreen> createState() =>
      _DeadReckoningScreenState();
}

class _DeadReckoningScreenState extends ConsumerState<DeadReckoningScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  Timer? _ticker;
  DateTime _now = DateTime.now();

  final _latCtrl = TextEditingController();
  final _lonCtrl = TextEditingController();
  final _cogCtrl = TextEditingController();
  final _sogCtrl = TextEditingController();
  final _labelCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _ticker = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    _ticker?.cancel();
    _latCtrl.dispose();
    _lonCtrl.dispose();
    _cogCtrl.dispose();
    _sogCtrl.dispose();
    _labelCtrl.dispose();
    super.dispose();
  }

  void _fillFromSignalK() {
    final sk = ref.read(signalKProvider);
    final nav = sk.ownVessel.navigation;
    final pos = nav.position;
    final cog = nav.cog;  // already in degrees true
    final sog = nav.sog;  // already in knots

    if (pos != null) {
      _latCtrl.text = pos.latitude.toStringAsFixed(6);
      _lonCtrl.text = pos.longitude.toStringAsFixed(6);
    }
    if (cog != null) _cogCtrl.text = cog.toStringAsFixed(1);
    if (sog != null) _sogCtrl.text = sog.toStringAsFixed(1);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Filled from Signal K'),
          duration: Duration(seconds: 2)),
    );
  }

  void _saveFix() {
    final lat = double.tryParse(_latCtrl.text.trim());
    final lon = double.tryParse(_lonCtrl.text.trim());
    final cog = double.tryParse(_cogCtrl.text.trim());
    final sog = double.tryParse(_sogCtrl.text.trim());

    if (lat == null || lon == null || cog == null || sog == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Fill in all fields')));
      return;
    }
    if (cog < 0 || cog > 360) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Course must be 0–360°')));
      return;
    }
    if (sog < 0 || sog > 50) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Speed out of range (0–50 kts)')));
      return;
    }

    final fix = DrFix(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      time: DateTime.now(),
      position: _LatLon(lat: lat, lon: lon),
      courseTrue: cog % 360,
      speedKts: sog,
      label: _labelCtrl.text.trim().isEmpty ? null : _labelCtrl.text.trim(),
    );
    ref.read(_drProvider.notifier).addFix(fix);
    _labelCtrl.clear();
    _tabs.animateTo(1);
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fix saved'), duration: Duration(seconds: 2)));
  }

  @override
  Widget build(BuildContext context) {
    final drState = ref.watch(_drProvider);
    final skState = ref.watch(signalKProvider);
    final skConnected =
        skState.connectionState == SignalKConnectionState.connected;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dead Reckoning'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(icon: Icon(Icons.add_location_alt), text: 'Log Fix'),
            Tab(icon: Icon(Icons.timeline), text: 'Projections'),
          ],
        ),
      ),
      body: drState.isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabs,
              children: [
                _buildLogFixTab(skConnected),
                _buildProjectionsTab(drState),
              ],
            ),
    );
  }

  // ── Log Fix Tab ───────────────────────────────────────────────────────────

  Widget _buildLogFixTab(bool skConnected) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            color: Theme.of(context).colorScheme.secondaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, size: 18),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Record your last confirmed position, course, and speed. '
                      'The app projects forward using time elapsed to estimate '
                      'your current and future position.',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          if (skConnected) ...[
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.download),
                label: const Text('Fill from Signal K (live position)'),
                onPressed: _fillFromSignalK,
              ),
            ),
            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 8),
          ],

          Text('Position', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _latCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true, signed: true),
                  decoration: const InputDecoration(
                    labelText: 'Latitude',
                    hintText: '59.3293',
                    border: OutlineInputBorder(),
                    suffixText: '°',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _lonCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true, signed: true),
                  decoration: const InputDecoration(
                    labelText: 'Longitude',
                    hintText: '18.0686',
                    border: OutlineInputBorder(),
                    suffixText: '°',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text('Course & Speed',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _cogCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Course (True)',
                    hintText: '270',
                    border: OutlineInputBorder(),
                    suffixText: '°T',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _sogCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Speed',
                    hintText: '5.5',
                    border: OutlineInputBorder(),
                    suffixText: 'kts',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _labelCtrl,
            decoration: const InputDecoration(
              labelText: 'Label (optional)',
              hintText: 'e.g. "Left Sandhamn"',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              icon: const Icon(Icons.save),
              label: const Text('Save Fix'),
              onPressed: _saveFix,
            ),
          ),
        ],
      ),
    );
  }

  // ── Projections Tab ───────────────────────────────────────────────────────

  Widget _buildProjectionsTab(_DrState drState) {
    final options = const [
      Duration(minutes: 30),
      Duration(hours: 1),
      Duration(hours: 2),
      Duration(hours: 4),
      Duration(hours: 6),
      Duration(hours: 12),
      Duration(hours: 24),
    ];

    String dLabel(Duration d) {
      if (d.inMinutes < 60) return '${d.inMinutes}m';
      return '${d.inHours}h';
    }

    return Column(
      children: [
        // Look-ahead chips
        SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            children: [
              const Padding(
                padding: EdgeInsets.only(right: 8, top: 6),
                child: Text('Project:', style: TextStyle(fontSize: 13)),
              ),
              ...options.map((d) {
                final selected = drState.lookAhead == d;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(dLabel(d)),
                    selected: selected,
                    onSelected: (_) =>
                        ref.read(_drProvider.notifier).setLookAhead(d),
                  ),
                );
              }),
            ],
          ),
        ),
        const Divider(height: 1),
        if (drState.fixes.isEmpty)
          const Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.location_off, size: 48, color: Colors.grey),
                  SizedBox(height: 12),
                  Text('No fixes logged yet.',
                      style: TextStyle(color: Colors.grey)),
                  SizedBox(height: 4),
                  Text('Use the Log Fix tab to save your position.',
                      style: TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ),
            ),
          )
        else
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: drState.fixes.length,
              itemBuilder: (ctx, i) {
                final fix = drState.fixes[i];
                final age = _now.difference(fix.time);
                final currentProj =
                    _DrProjection.compute(fix, age < Duration.zero ? Duration.zero : age);
                final futureProj =
                    _DrProjection.compute(fix, age + drState.lookAhead);
                return _FixCard(
                  fix: fix,
                  currentProj: currentProj,
                  futureProj: futureProj,
                  age: age,
                  lookAhead: drState.lookAhead,
                  onDelete: () =>
                      ref.read(_drProvider.notifier).removeFix(fix.id),
                );
              },
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Fix card widget
// ─────────────────────────────────────────────────────────────────────────────

class _FixCard extends StatelessWidget {
  final DrFix fix;
  final _DrProjection currentProj;
  final _DrProjection futureProj;
  final Duration age;
  final Duration lookAhead;
  final VoidCallback onDelete;

  const _FixCard({
    required this.fix,
    required this.currentProj,
    required this.futureProj,
    required this.age,
    required this.lookAhead,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ageStr = _fmtAge(age);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title row
            Row(
              children: [
                Icon(Icons.my_location, size: 18, color: cs.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    fix.label ?? 'Fix at ${_fmtTime(fix.time)}',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  onPressed: onDelete,
                  tooltip: 'Delete',
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 4),

            // Fix info
            _Row('Fixed at', '${_fmtTime(fix.time)}  ($ageStr ago)'),
            _Row('Position', fix.position.toDisplayString()),
            _Row(
                'Course / Speed',
                '${fix.courseTrue.toStringAsFixed(0)}°T  ·  '
                    '${fix.speedKts.toStringAsFixed(1)} kts'),

            const Divider(height: 18),

            // Current DR position
            Row(
              children: [
                Icon(Icons.navigation, size: 14, color: cs.secondary),
                const SizedBox(width: 4),
                Text('Current DR position',
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: cs.secondary)),
              ],
            ),
            const SizedBox(height: 4),
            _Row('Position', currentProj.position.toDisplayString()),
            _Row('From fix',
                '${currentProj.distanceNm.toStringAsFixed(2)} nm'),

            const Divider(height: 18),

            // Future projection
            Row(
              children: [
                Icon(Icons.arrow_forward_ios,
                    size: 13, color: cs.tertiary),
                const SizedBox(width: 4),
                Text(
                  'In ${_fmtLookAhead(lookAhead)} (projected)',
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: cs.tertiary),
                ),
              ],
            ),
            const SizedBox(height: 4),
            _Row('Position', futureProj.position.toDisplayString()),
            _Row('Total dist from fix',
                '${futureProj.distanceNm.toStringAsFixed(2)} nm'),

            // Staleness warning
            if (age.inHours >= 4) ...[
              const SizedBox(height: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.orange.shade300),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber,
                        size: 16, color: Colors.orange),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Fix is $ageStr old — '
                        'DR accuracy decreasing. Log a new fix.',
                        style: const TextStyle(
                            fontSize: 12, color: Colors.orange),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _fmtTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  String _fmtAge(Duration d) {
    if (d.inMinutes < 1) return '<1m';
    if (d.inMinutes < 60) return '${d.inMinutes}m';
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }

  String _fmtLookAhead(Duration d) {
    if (d.inMinutes < 60) return '${d.inMinutes} min';
    return '${d.inHours}h';
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  const _Row(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(label,
                style: TextStyle(
                    fontSize: 12, color: Theme.of(context).hintColor)),
          ),
          Expanded(
              child: Text(value, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}
