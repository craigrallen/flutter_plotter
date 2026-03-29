import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:ui' as ui;

import 'package:latlong2/latlong.dart' hide Path;

import '../../data/providers/signalk_provider.dart';
import '../../data/providers/vessel_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Constants
// ─────────────────────────────────────────────────────────────────────────────

const double _kEarthRadiusM = 6371000.0;
const double _kNmToMetres = 1852.0;

/// Simulation time steps in minutes.
const List<int> _kTimeStepsMin = [0, 15, 30, 45, 60, 90, 120];

// ─────────────────────────────────────────────────────────────────────────────
// Person type & leeway factors (IAMSAR)
// ─────────────────────────────────────────────────────────────────────────────

enum PersonType { consciousSwimmer, unconscious, liferaft }

extension PersonTypeX on PersonType {
  String get label {
    switch (this) {
      case PersonType.consciousSwimmer:
        return 'Conscious Swimmer';
      case PersonType.unconscious:
        return 'Unconscious Person';
      case PersonType.liferaft:
        return 'Life Raft';
    }
  }

  /// Leeway as fraction of wind speed (knots).
  double leewayFraction(double windSpeedKt) {
    switch (this) {
      case PersonType.consciousSwimmer:
        return 0.03;
      case PersonType.unconscious:
        return 0.045;
      case PersonType.liferaft:
        return 0.04; // mid of 3–5%
    }
  }

  /// Whether tidal current is added to leeway.
  bool get includesTidal {
    switch (this) {
      case PersonType.consciousSwimmer:
        return true;
      case PersonType.unconscious:
        return false;
      case PersonType.liferaft:
        return true;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Geometry helpers
// ─────────────────────────────────────────────────────────────────────────────

double _degToRad(double d) => d * math.pi / 180.0;
double _radToDeg(double r) => r * 180.0 / math.pi;

/// Project [origin] by [distanceNm] nautical miles along [bearingDeg].
LatLng _destination(LatLng origin, double bearingDeg, double distanceNm) {
  final distM = distanceNm * _kNmToMetres;
  final lat1 = _degToRad(origin.latitude);
  final lon1 = _degToRad(origin.longitude);
  final brng = _degToRad(bearingDeg);
  final ang = distM / _kEarthRadiusM;

  final lat2 = math.asin(
    math.sin(lat1) * math.cos(ang) +
        math.cos(lat1) * math.sin(ang) * math.cos(brng),
  );
  final lon2 = lon1 +
      math.atan2(
        math.sin(brng) * math.sin(ang) * math.cos(lat1),
        math.cos(ang) - math.sin(lat1) * math.sin(lat2),
      );
  return LatLng(_radToDeg(lat2), _radToDeg(lon2));
}

/// Haversine distance in nautical miles.
double _distanceNm(LatLng a, LatLng b) {
  const R = 3440.065; // Earth radius in NM
  final dLat = _degToRad(b.latitude - a.latitude);
  final dLon = _degToRad(b.longitude - a.longitude);
  final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_degToRad(a.latitude)) *
          math.cos(_degToRad(b.latitude)) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);
  return 2 * R * math.asin(math.sqrt(h));
}

/// Initial bearing from [from] to [to] in degrees true (0–360).
double _bearing(LatLng from, LatLng to) {
  final lat1 = _degToRad(from.latitude);
  final lat2 = _degToRad(to.latitude);
  final dLon = _degToRad(to.longitude - from.longitude);
  final y = math.sin(dLon) * math.cos(lat2);
  final x = math.cos(lat1) * math.sin(lat2) -
      math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
  return (_radToDeg(math.atan2(y, x)) + 360) % 360;
}

// ─────────────────────────────────────────────────────────────────────────────
// Drift model
// ─────────────────────────────────────────────────────────────────────────────

class DriftInputs {
  final double windSpeedKt;
  final double windDirectionDeg; // direction FROM (meteorological)
  final double tidalSpeedKt;
  final double tidalDirectionDeg; // direction TO (oceanographic)
  final PersonType personType;

  const DriftInputs({
    required this.windSpeedKt,
    required this.windDirectionDeg,
    required this.tidalSpeedKt,
    required this.tidalDirectionDeg,
    required this.personType,
  });

  DriftInputs copyWith({
    double? windSpeedKt,
    double? windDirectionDeg,
    double? tidalSpeedKt,
    double? tidalDirectionDeg,
    PersonType? personType,
  }) =>
      DriftInputs(
        windSpeedKt: windSpeedKt ?? this.windSpeedKt,
        windDirectionDeg: windDirectionDeg ?? this.windDirectionDeg,
        tidalSpeedKt: tidalSpeedKt ?? this.tidalSpeedKt,
        tidalDirectionDeg: tidalDirectionDeg ?? this.tidalDirectionDeg,
        personType: personType ?? this.personType,
      );
}

class DriftPoint {
  final LatLng position;
  final int minutesFromMob;
  final double uncertaintyRadiusNm;

  const DriftPoint({
    required this.position,
    required this.minutesFromMob,
    required this.uncertaintyRadiusNm,
  });
}

class DriftResult {
  final LatLng mobPosition;
  final List<DriftPoint> trail; // index 0 = MOB position (t=0)
  final DriftInputs inputs;

  const DriftResult({
    required this.mobPosition,
    required this.trail,
    required this.inputs,
  });
}

/// Run IAMSAR leeway drift simulation.
DriftResult calculateDrift(LatLng mobPos, DriftInputs inputs) {
  const uncertaintyGrowthPerHour = 0.3; // NM per hour baseline

  // Leeway speed and direction
  final leewayFraction = inputs.personType.leewayFraction(inputs.windSpeedKt);
  final leewaySpeedKt = inputs.windSpeedKt * leewayFraction;
  // Leeway direction: downwind (wind FROM → drift TO = windDir + 180)
  final leewayDirDeg = (inputs.windDirectionDeg + 180) % 360;

  final List<DriftPoint> trail = [];

  for (final tMin in _kTimeStepsMin) {
    final tHours = tMin / 60.0;

    LatLng pos;
    if (tMin == 0) {
      pos = mobPos;
    } else {
      // Accumulate from previous step for a step-by-step simulation
      // Recalculate from t=0 using resultant vector per step
      pos = mobPos;
      // Step through each 15-min interval up to tMin
      int step = 0;
      while (step < tMin) {
        const stepMin = 15;
        final stepHours = stepMin / 60.0;

        // Tidal component
        double lat = pos.latitude;
        double lon = pos.longitude;

        if (inputs.personType.includesTidal) {
          final tidalPos =
              _destination(pos, inputs.tidalDirectionDeg, inputs.tidalSpeedKt * stepHours);
          lat = tidalPos.latitude;
          lon = tidalPos.longitude;
          pos = LatLng(lat, lon);
        }

        // Leeway component
        final leewayPos =
            _destination(pos, leewayDirDeg, leewaySpeedKt * stepHours);
        pos = leewayPos;

        step += stepMin;
      }
    }

    // Uncertainty: grows with square root of time (drift uncertainty model)
    final uncertaintyNm =
        uncertaintyGrowthPerHour * math.sqrt(tHours) + (tHours * 0.1);

    trail.add(DriftPoint(
      position: pos,
      minutesFromMob: tMin,
      uncertaintyRadiusNm: uncertaintyNm,
    ));
  }

  return DriftResult(
    mobPosition: mobPos,
    trail: trail,
    inputs: inputs,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Screen
// ─────────────────────────────────────────────────────────────────────────────

class MobDriftScreen extends ConsumerStatefulWidget {
  /// If provided, used as the initial MOB position.
  final LatLng? initialMobPosition;

  const MobDriftScreen({super.key, this.initialMobPosition});

  @override
  ConsumerState<MobDriftScreen> createState() => _MobDriftScreenState();
}

class _MobDriftScreenState extends ConsumerState<MobDriftScreen>
    with SingleTickerProviderStateMixin {
  // Inputs
  late final TextEditingController _mobLatCtrl;
  late final TextEditingController _mobLonCtrl;
  final _windSpeedCtrl = TextEditingController(text: '10');
  final _windDirCtrl = TextEditingController(text: '180');
  final _tidalSpeedCtrl = TextEditingController(text: '0.5');
  final _tidalDirCtrl = TextEditingController(text: '90');

  PersonType _personType = PersonType.consciousSwimmer;
  bool _inputsExpanded = true;
  DriftResult? _driftResult;

  Timer? _ticker;
  LatLng? _mobPosition;

  @override
  void initState() {
    super.initState();

    final initPos = widget.initialMobPosition;
    _mobLatCtrl = TextEditingController(
        text: initPos?.latitude.toStringAsFixed(6) ?? '');
    _mobLonCtrl = TextEditingController(
        text: initPos?.longitude.toStringAsFixed(6) ?? '');

    if (initPos != null) {
      _mobPosition = initPos;
    }

    // Refresh bearing/distance display every 10 seconds
    _ticker = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) setState(() {});
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _prefillFromSignalK();
      if (_mobPosition != null) _recalculate();
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _mobLatCtrl.dispose();
    _mobLonCtrl.dispose();
    _windSpeedCtrl.dispose();
    _windDirCtrl.dispose();
    _tidalSpeedCtrl.dispose();
    _tidalDirCtrl.dispose();
    super.dispose();
  }

  void _prefillFromSignalK() {
    final vessel = ref.read(vesselProvider);
    final skEnv = ref.read(signalKEnvironmentProvider);

    // True wind speed preferred; fall back to apparent
    final tws = vessel.trueWindSpeed ?? vessel.windSpeed;
    if (tws != null) {
      _windSpeedCtrl.text = tws.toStringAsFixed(1);
    }

    // True wind direction (FROM, degrees true)
    // signalKEnvironmentProvider gives windAngleTrueGround (relative)
    // We need COG + windAngleTrueGround to get absolute true wind direction
    final twa = skEnv.windAngleTrueGround;
    final cog = vessel.cog;
    if (twa != null && cog != null) {
      final twd = (cog + twa + 360) % 360;
      _windDirCtrl.text = twd.toStringAsFixed(0);
    } else if (twa != null) {
      _windDirCtrl.text = twa.toStringAsFixed(0);
    }

    // If no MOB position set yet, use own vessel position
    if (_mobPosition == null && vessel.position != null) {
      _mobLatCtrl.text = vessel.position!.latitude.toStringAsFixed(6);
      _mobLonCtrl.text = vessel.position!.longitude.toStringAsFixed(6);
      _mobPosition = vessel.position;
    }

    setState(() {});
  }

  void _recalculate() {
    final lat = double.tryParse(_mobLatCtrl.text.trim());
    final lon = double.tryParse(_mobLonCtrl.text.trim());
    if (lat == null || lon == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Enter valid MOB position')));
      return;
    }

    final windSpd = double.tryParse(_windSpeedCtrl.text.trim()) ?? 10.0;
    final windDir = double.tryParse(_windDirCtrl.text.trim()) ?? 180.0;
    final tidalSpd = double.tryParse(_tidalSpeedCtrl.text.trim()) ?? 0.5;
    final tidalDir = double.tryParse(_tidalDirCtrl.text.trim()) ?? 90.0;

    final mobPos = LatLng(lat, lon);
    final inputs = DriftInputs(
      windSpeedKt: windSpd.clamp(0, 100),
      windDirectionDeg: windDir % 360,
      tidalSpeedKt: tidalSpd.clamp(0, 10),
      tidalDirectionDeg: tidalDir % 360,
      personType: _personType,
    );

    setState(() {
      _mobPosition = mobPos;
      _driftResult = calculateDrift(mobPos, inputs);
      _inputsExpanded = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final vessel = ref.watch(vesselProvider);
    final ownPos = vessel.position;
    final result = _driftResult;

    return Scaffold(
      backgroundColor: const Color(0xFF0A1628),
      appBar: AppBar(
        backgroundColor: Colors.red.shade900,
        foregroundColor: Colors.white,
        title: const Row(
          children: [
            Icon(Icons.warning_rounded, size: 20),
            SizedBox(width: 8),
            Text('MOB Drift Prediction',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          if (result != null)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Recalculate',
              onPressed: _recalculate,
            ),
        ],
      ),
      body: Column(
        children: [
          // ── MOB bearing/distance banner ──────────────────────────
          if (_mobPosition != null && ownPos != null)
            _BearingBanner(
              mobPosition: _mobPosition!,
              ownPosition: ownPos,
              ownSog: vessel.sog,
            ),

          // ── Map canvas ──────────────────────────────────────────
          Expanded(
            child: result == null
                ? _NoDataPlaceholder(onSetup: () {
                    setState(() => _inputsExpanded = true);
                  })
                : _DriftMapCanvas(
                    result: result,
                    ownPosition: ownPos,
                    ownHeading: vessel.heading ?? vessel.cog,
                  ),
          ),

          // ── Collapsible inputs panel ─────────────────────────────
          _InputsPanel(
            expanded: _inputsExpanded,
            onToggle: () =>
                setState(() => _inputsExpanded = !_inputsExpanded),
            mobLatCtrl: _mobLatCtrl,
            mobLonCtrl: _mobLonCtrl,
            windSpeedCtrl: _windSpeedCtrl,
            windDirCtrl: _windDirCtrl,
            tidalSpeedCtrl: _tidalSpeedCtrl,
            tidalDirCtrl: _tidalDirCtrl,
            personType: _personType,
            onPersonTypeChanged: (t) => setState(() => _personType = t),
            onFillFromGps: _prefillFromSignalK,
            onCalculate: _recalculate,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Bearing banner
// ─────────────────────────────────────────────────────────────────────────────

class _BearingBanner extends StatelessWidget {
  final LatLng mobPosition;
  final LatLng ownPosition;
  final double? ownSog;

  const _BearingBanner({
    required this.mobPosition,
    required this.ownPosition,
    this.ownSog,
  });

  @override
  Widget build(BuildContext context) {
    final dist = _distanceNm(ownPosition, mobPosition);
    final brng = _bearing(ownPosition, mobPosition);

    // ETE
    String eteStr = '--';
    if (ownSog != null && ownSog! > 0.1) {
      final hours = dist / ownSog!;
      final totalMin = (hours * 60).round();
      if (totalMin < 60) {
        eteStr = '${totalMin}m';
      } else {
        eteStr = '${totalMin ~/ 60}h ${totalMin % 60}m';
      }
    }

    return Container(
      color: Colors.red.shade900,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          _BannerStat(
            label: 'BEARING',
            value: '${brng.toStringAsFixed(0)}°T',
            icon: Icons.navigation,
          ),
          const SizedBox(width: 16),
          _BannerStat(
            label: 'DISTANCE',
            value: dist < 1
                ? '${(dist * 1000).toStringAsFixed(0)}m'
                : '${dist.toStringAsFixed(2)} NM',
            icon: Icons.straighten,
          ),
          const SizedBox(width: 16),
          _BannerStat(
            label: 'ETE',
            value: eteStr,
            icon: Icons.timer,
          ),
        ],
      ),
    );
  }
}

class _BannerStat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _BannerStat(
      {required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 12, color: Colors.red.shade200),
              const SizedBox(width: 3),
              Text(label,
                  style: TextStyle(
                      color: Colors.red.shade200,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.8)),
            ],
          ),
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// No-data placeholder
// ─────────────────────────────────────────────────────────────────────────────

class _NoDataPlaceholder extends StatelessWidget {
  final VoidCallback onSetup;
  const _NoDataPlaceholder({required this.onSetup});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.person_off, size: 72, color: Colors.red.shade300),
          const SizedBox(height: 16),
          const Text('Enter MOB position and drift inputs',
              style: TextStyle(color: Colors.white70, fontSize: 16)),
          const SizedBox(height: 12),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            icon: const Icon(Icons.tune),
            label: const Text('Set Drift Inputs'),
            onPressed: onSetup,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Drift map canvas (CustomPaint)
// ─────────────────────────────────────────────────────────────────────────────

class _DriftMapCanvas extends StatelessWidget {
  final DriftResult result;
  final LatLng? ownPosition;
  final double? ownHeading;

  const _DriftMapCanvas({
    required this.result,
    this.ownPosition,
    this.ownHeading,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DriftPainter(
        result: result,
        ownPosition: ownPosition,
        ownHeading: ownHeading,
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _DriftPainter extends CustomPainter {
  final DriftResult result;
  final LatLng? ownPosition;
  final double? ownHeading;

  _DriftPainter({
    required this.result,
    this.ownPosition,
    this.ownHeading,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Collect all positions for bounds
    final allPts = <LatLng>[...result.trail.map((p) => p.position)];
    if (ownPosition != null) allPts.add(ownPosition!);

    if (allPts.isEmpty) return;

    double minLat = allPts.map((p) => p.latitude).reduce(math.min);
    double maxLat = allPts.map((p) => p.latitude).reduce(math.max);
    double minLon = allPts.map((p) => p.longitude).reduce(math.min);
    double maxLon = allPts.map((p) => p.longitude).reduce(math.max);

    // Ensure minimum bounds
    final latRange = math.max((maxLat - minLat).abs(), 0.005);
    final lonRange = math.max((maxLon - minLon).abs(), 0.005);
    final latPad = latRange * 0.25;
    final lonPad = lonRange * 0.25;
    minLat -= latPad;
    maxLat += latPad;
    minLon -= lonPad;
    maxLon += lonPad;

    Offset toScreen(LatLng p) {
      final x = (p.longitude - minLon) / (maxLon - minLon) * size.width;
      final y =
          size.height - (p.latitude - minLat) / (maxLat - minLat) * size.height;
      return Offset(x, y);
    }

    double toScreenDistance(double nm) {
      // Convert NM to pixels based on lat scale
      final degPerNm = 1.0 / 60.0;
      final latFraction = (degPerNm * nm) / (maxLat - minLat);
      return latFraction * size.height;
    }

    // ── Background ──────────────────────────────────────────────
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = const Color(0xFF0A1628),
    );

    // ── Search area sector (last point, largest uncertainty) ─────
    final lastPoint = result.trail.last;
    final lastScreenPt = toScreen(lastPoint.position);
    final sectorRadius =
        toScreenDistance(lastPoint.uncertaintyRadiusNm * 1.5);
    canvas.drawCircle(
      lastScreenPt,
      sectorRadius,
      Paint()
        ..color = Colors.orange.withValues(alpha: 0.08)
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      lastScreenPt,
      sectorRadius,
      Paint()
        ..color = Colors.orange.withValues(alpha: 0.2)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // ── Uncertainty ellipses at each point ───────────────────────
    for (final pt in result.trail) {
      if (pt.minutesFromMob == 0) continue;
      final screenPt = toScreen(pt.position);
      final radius = toScreenDistance(pt.uncertaintyRadiusNm);
      if (radius < 5) continue;
      canvas.drawCircle(
        screenPt,
        radius,
        Paint()
          ..color = Colors.orange.withValues(alpha: 0.06)
          ..style = PaintingStyle.fill,
      );
      canvas.drawCircle(
        screenPt,
        radius,
        Paint()
          ..color = Colors.orange.withValues(alpha: 0.15)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0,
      );
    }

    // ── Dashed trail ─────────────────────────────────────────────
    if (result.trail.length > 1) {
      final trailPaint = Paint()
        ..color = Colors.orange.withValues(alpha: 0.85)
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      for (int i = 0; i < result.trail.length - 1; i++) {
        final a = toScreen(result.trail[i].position);
        final b = toScreen(result.trail[i + 1].position);
        _drawDashedLine(canvas, a, b, trailPaint, dashLen: 8, gapLen: 6);
      }
    }

    // ── Own vessel → MOB bearing line ────────────────────────────
    if (ownPosition != null) {
      final ownScreenPt = toScreen(ownPosition!);
      final mobScreenPt = toScreen(result.mobPosition);
      canvas.drawLine(
        ownScreenPt,
        mobScreenPt,
        Paint()
          ..color = Colors.cyan.withValues(alpha: 0.5)
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke,
      );
    }

    // ── Orange circles at each drift point ──────────────────────
    for (final pt in result.trail) {
      if (pt.minutesFromMob == 0) continue;
      final screenPt = toScreen(pt.position);
      canvas.drawCircle(
          screenPt,
          8,
          Paint()
            ..color = Colors.orange.withValues(alpha: 0.9)
            ..style = PaintingStyle.fill);
      canvas.drawCircle(
          screenPt,
          8,
          Paint()
            ..color = Colors.orange
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5);

      // Time label
      final label = pt.minutesFromMob < 60
          ? '${pt.minutesFromMob}m'
          : '${pt.minutesFromMob ~/ 60}h${pt.minutesFromMob % 60 > 0 ? '${pt.minutesFromMob % 60}m' : ''}';
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: const TextStyle(
              color: Colors.orange,
              fontSize: 10,
              fontWeight: FontWeight.bold),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, screenPt.translate(10, -6));
    }

    // ── MOB position: red X ──────────────────────────────────────
    final mobPt = toScreen(result.mobPosition);
    final xPaint = Paint()
      ..color = Colors.red
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    const xSize = 10.0;
    canvas.drawLine(
        mobPt.translate(-xSize, -xSize), mobPt.translate(xSize, xSize), xPaint);
    canvas.drawLine(
        mobPt.translate(xSize, -xSize), mobPt.translate(-xSize, xSize), xPaint);

    // MOB label
    final mobTp = TextPainter(
      text: const TextSpan(
        text: 'MOB',
        style: TextStyle(
            color: Colors.red, fontSize: 11, fontWeight: FontWeight.bold),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    mobTp.paint(canvas, mobPt.translate(12, -6));

    // ── Own vessel triangle ───────────────────────────────────────
    if (ownPosition != null) {
      final ownPt = toScreen(ownPosition!);
      final heading = ownHeading ?? 0.0;
      _drawVesselTriangle(canvas, ownPt, heading, Colors.cyan);
    }

    // ── Grid labels (lat/lon corners) ────────────────────────────
    _drawCornerLabel(canvas, size,
        '${minLat.toStringAsFixed(3)}°N  ${minLon.toStringAsFixed(3)}°E',
        Offset(4, size.height - 14));
  }

  void _drawDashedLine(
      Canvas canvas, Offset a, Offset b, Paint paint,
      {double dashLen = 8, double gapLen = 4}) {
    final dx = b.dx - a.dx;
    final dy = b.dy - a.dy;
    final dist = math.sqrt(dx * dx + dy * dy);
    if (dist == 0) return;
    final nx = dx / dist;
    final ny = dy / dist;
    double traveled = 0;
    bool drawing = true;
    while (traveled < dist) {
      final segLen = drawing ? dashLen : gapLen;
      final end = math.min(traveled + segLen, dist);
      if (drawing) {
        canvas.drawLine(
          Offset(a.dx + nx * traveled, a.dy + ny * traveled),
          Offset(a.dx + nx * end, a.dy + ny * end),
          paint,
        );
      }
      traveled = end;
      drawing = !drawing;
    }
  }

  void _drawVesselTriangle(
      Canvas canvas, Offset pos, double headingDeg, Color color) {
    const h = 14.0, w = 8.0;
    final rad = _degToRad(headingDeg);
    final tip = Offset(pos.dx + h * math.sin(rad), pos.dy - h * math.cos(rad));
    final portBase = Offset(pos.dx + w * math.cos(rad), pos.dy + w * math.sin(rad));
    final stbdBase = Offset(pos.dx - w * math.cos(rad), pos.dy - w * math.sin(rad));

    final path = ui.Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(portBase.dx, portBase.dy)
      ..lineTo(stbdBase.dx, stbdBase.dy)
      ..close();

    canvas.drawPath(
        path, Paint()..color = color.withValues(alpha: 0.25)..style = PaintingStyle.fill);
    canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5);

    final tp = TextPainter(
      text: TextSpan(
        text: 'OWN',
        style: TextStyle(
            color: color, fontSize: 9, fontWeight: FontWeight.bold),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, pos.translate(12, -5));
  }

  void _drawCornerLabel(
      Canvas canvas, Size size, String text, Offset offset) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(color: Colors.white30, fontSize: 9),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(_DriftPainter old) =>
      old.result != result ||
      old.ownPosition != ownPosition ||
      old.ownHeading != ownHeading;
}

// ─────────────────────────────────────────────────────────────────────────────
// Collapsible inputs panel
// ─────────────────────────────────────────────────────────────────────────────

class _InputsPanel extends StatelessWidget {
  final bool expanded;
  final VoidCallback onToggle;
  final TextEditingController mobLatCtrl;
  final TextEditingController mobLonCtrl;
  final TextEditingController windSpeedCtrl;
  final TextEditingController windDirCtrl;
  final TextEditingController tidalSpeedCtrl;
  final TextEditingController tidalDirCtrl;
  final PersonType personType;
  final ValueChanged<PersonType> onPersonTypeChanged;
  final VoidCallback onFillFromGps;
  final VoidCallback onCalculate;

  const _InputsPanel({
    required this.expanded,
    required this.onToggle,
    required this.mobLatCtrl,
    required this.mobLonCtrl,
    required this.windSpeedCtrl,
    required this.windDirCtrl,
    required this.tidalSpeedCtrl,
    required this.tidalDirCtrl,
    required this.personType,
    required this.onPersonTypeChanged,
    required this.onFillFromGps,
    required this.onCalculate,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0F1F35),
        border: Border(
            top: BorderSide(color: Colors.red.shade900, width: 2)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          InkWell(
            onTap: onToggle,
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Icon(Icons.tune, size: 18, color: Colors.orange.shade300),
                  const SizedBox(width: 8),
                  Text('Drift Inputs',
                      style: TextStyle(
                          color: Colors.orange.shade300,
                          fontWeight: FontWeight.bold,
                          fontSize: 14)),
                  const Spacer(),
                  Icon(
                    expanded ? Icons.expand_more : Icons.expand_less,
                    color: Colors.white54,
                  ),
                ],
              ),
            ),
          ),

          if (expanded) ...[
            const Divider(height: 1, color: Colors.white12),
            SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── MOB Position ─────────────────────────────
                  _label(context, 'MOB Position'),
                  Row(
                    children: [
                      Expanded(
                        child: _field('Latitude', mobLatCtrl,
                            hint: '59.123456'),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _field('Longitude', mobLonCtrl,
                            hint: '18.123456'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.cyan,
                        side: BorderSide(color: Colors.cyan.withValues(alpha: 0.15))),
                    icon: const Icon(Icons.my_location, size: 16),
                    label: const Text('Fill from Signal K / GPS',
                        style: TextStyle(fontSize: 12)),
                    onPressed: onFillFromGps,
                  ),
                  const SizedBox(height: 12),

                  // ── Wind ────────────────────────────────────
                  _label(context, 'Wind (auto-filled from Signal K)'),
                  Row(
                    children: [
                      Expanded(
                        child: _field('Speed (kt)', windSpeedCtrl,
                            hint: '10'),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _field('Direction FROM (°T)', windDirCtrl,
                            hint: '180'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // ── Tidal ───────────────────────────────────
                  _label(context, 'Tidal Current'),
                  Row(
                    children: [
                      Expanded(
                        child: _field('Speed (kt)', tidalSpeedCtrl,
                            hint: '0.5'),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _field('Direction TO (°T)', tidalDirCtrl,
                            hint: '90'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // ── Person type ─────────────────────────────
                  _label(context, 'Person Type (IAMSAR leeway)'),
                  Wrap(
                    spacing: 8,
                    children: PersonType.values.map((t) {
                      return ChoiceChip(
                        label: Text(t.label,
                            style: const TextStyle(fontSize: 12)),
                        selected: personType == t,
                        selectedColor: Colors.orange.shade800,
                        onSelected: (_) => onPersonTypeChanged(t),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 8),
                  _LeewayHint(personType: personType),
                  const SizedBox(height: 14),

                  // ── Calculate button ─────────────────────────
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                          backgroundColor: Colors.red.shade700),
                      icon: const Icon(Icons.calculate),
                      label: const Text('Calculate Drift'),
                      onPressed: onCalculate,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _label(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text,
            style: TextStyle(
                color: Colors.white54, fontSize: 11, letterSpacing: 0.5)),
      );

  Widget _field(String label, TextEditingController ctrl,
      {String? hint}) =>
      TextField(
        controller: ctrl,
        keyboardType:
            const TextInputType.numberWithOptions(decimal: true, signed: true),
        style: const TextStyle(color: Colors.white, fontSize: 13),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white54, fontSize: 12),
          hintText: hint,
          hintStyle: const TextStyle(color: Colors.white24),
          isDense: true,
          border: const OutlineInputBorder(),
          enabledBorder: OutlineInputBorder(
            borderSide:
                BorderSide(color: Colors.white.withValues(alpha: 0.2)),
          ),
          focusedBorder: OutlineInputBorder(
            borderSide: BorderSide(color: Colors.orange.shade400),
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Leeway hint
// ─────────────────────────────────────────────────────────────────────────────

class _LeewayHint extends StatelessWidget {
  final PersonType personType;
  const _LeewayHint({required this.personType});

  @override
  Widget build(BuildContext context) {
    final String text;
    switch (personType) {
      case PersonType.consciousSwimmer:
        text = 'Leeway: 3% wind speed + tidal current';
      case PersonType.unconscious:
        text = 'Leeway: 4.5% wind speed only (no self-correction)';
      case PersonType.liferaft:
        text = 'Leeway: 4% wind speed + tidal current';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
      ),
      child: Text(text,
          style: const TextStyle(color: Colors.orange, fontSize: 11)),
    );
  }
}
