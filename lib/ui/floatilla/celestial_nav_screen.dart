import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/signalk/signalk_source.dart';
import '../../data/providers/signalk_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Astronomical constants & helpers
// ─────────────────────────────────────────────────────────────────────────────

double _toRad(double deg) => deg * math.pi / 180.0;
double _toDeg(double rad) => rad * 180.0 / math.pi;

// Julian Date from DateTime
double _julianDate(DateTime dt) {
  final utc = dt.toUtc();
  final y = utc.year;
  final m = utc.month;
  final d = utc.day +
      utc.hour / 24.0 +
      utc.minute / 1440.0 +
      utc.second / 86400.0;
  if (m <= 2) {
    return _jd(y - 1, m + 12, d);
  }
  return _jd(y, m, d);
}

double _jd(int y, int m, double d) {
  final a = (y / 100).floor();
  final b = 2 - a + (a / 4).floor();
  return (365.25 * (y + 4716)).floor() +
      (30.6001 * (m + 1)).floor() +
      d +
      b -
      1524.5;
}

// ─────────────────────────────────────────────────────────────────────────────
// Sun position (Astronomical Algorithms, Meeus)
// ─────────────────────────────────────────────────────────────────────────────

class _CelestialPosition {
  final double gha; // Greenwich Hour Angle (degrees)
  final double dec; // Declination (degrees, +N)
  final double sd; // Semi-diameter (arc-minutes)
  final double hp; // Horizontal Parallax (arc-minutes)

  const _CelestialPosition({
    required this.gha,
    required this.dec,
    required this.sd,
    required this.hp,
  });
}

_CelestialPosition _sunPosition(DateTime dt) {
  final jd = _julianDate(dt);
  final t = (jd - 2451545.0) / 36525.0;

  // Geometric mean longitude of the Sun (degrees)
  double l0 = 280.46646 + 36000.76983 * t + 0.0003032 * t * t;
  l0 = l0 % 360;

  // Mean anomaly of the Sun (degrees)
  double m = 357.52911 + 35999.05029 * t - 0.0001537 * t * t;
  m = m % 360;
  final mRad = _toRad(m);

  // Equation of centre
  final c = (1.914602 - 0.004817 * t - 0.000014 * t * t) * math.sin(mRad) +
      (0.019993 - 0.000101 * t) * math.sin(2 * mRad) +
      0.000289 * math.sin(3 * mRad);

  // Sun's true longitude
  final sunLon = l0 + c;

  // Apparent longitude
  final omega = 125.04 - 1934.136 * t;
  final appLon = sunLon - 0.00569 - 0.00478 * math.sin(_toRad(omega));

  // Mean obliquity of ecliptic
  final eps0 = 23 +
      (26 +
              (21.448 -
                      t *
                          (46.8150 +
                              t * (0.00059 - t * 0.001813))) /
                  60) /
          60;
  final eps = eps0 + 0.00256 * math.cos(_toRad(omega));

  // Declination
  final dec = _toDeg(math.asin(
      math.sin(_toRad(eps)) * math.sin(_toRad(appLon))));

  // Right Ascension
  final raRad = math.atan2(
      math.cos(_toRad(eps)) * math.sin(_toRad(appLon)),
      math.cos(_toRad(appLon)));
  final ra = _toDeg(raRad) / 15.0; // hours

  // Greenwich Mean Sidereal Time (hours)
  final gmst =
      6.697375 + 2400.0513369 * t + 0.0000258622 * t * t - 1.7222e-9 * t * t * t;
  final ut = dt.toUtc().hour + dt.toUtc().minute / 60.0 + dt.toUtc().second / 3600.0;
  final gast = (gmst + ut * 1.00273791) % 24;

  // GHA = GAST - RA (in degrees)
  double gha = (gast - ra) * 15.0;
  gha = gha % 360;
  if (gha < 0) gha += 360;

  return _CelestialPosition(gha: gha, dec: dec, sd: 16.0, hp: 0.15);
}

_CelestialPosition _moonPosition(DateTime dt) {
  final jd = _julianDate(dt);
  final t = (jd - 2451545.0) / 36525.0;

  // Fundamental arguments (degrees)
  double l = 218.3164477 + 481267.88123421 * t; // Mean longitude
  double m = 357.5291092 + 35999.0502909 * t; // Sun's mean anomaly
  double mp = 134.9633964 + 477198.8675055 * t; // Moon's mean anomaly
  double d = 297.8501921 + 445267.1114034 * t; // Moon's mean elongation
  double f = 93.2720950 + 483202.0175233 * t; // Moon's arg of latitude

  l = l % 360;
  m = m % 360;
  mp = mp % 360;
  d = d % 360;
  f = f % 360;

  // Main longitude corrections (abridged)
  double dl = 6288774 * math.sin(_toRad(mp)) +
      1274027 * math.sin(_toRad(2 * d - mp)) +
      658314 * math.sin(_toRad(2 * d)) +
      213618 * math.sin(_toRad(2 * mp)) -
      185116 * math.sin(_toRad(m)) -
      114332 * math.sin(_toRad(2 * f)) +
      58793 * math.sin(_toRad(2 * d - 2 * mp)) +
      57066 * math.sin(_toRad(2 * d - m - mp)) +
      53322 * math.sin(_toRad(2 * d + mp)) +
      45758 * math.sin(_toRad(2 * d - m));

  // Main latitude corrections (abridged)
  double db = 5128122 * math.sin(_toRad(f)) +
      280602 * math.sin(_toRad(mp + f)) +
      277693 * math.sin(_toRad(mp - f)) +
      173237 * math.sin(_toRad(2 * d - f)) +
      55413 * math.sin(_toRad(2 * d + f - mp)) +
      46271 * math.sin(_toRad(2 * d + f));

  // Distance correction
  double dr = -20905355 * math.cos(_toRad(mp)) -
      3699111 * math.cos(_toRad(2 * d - mp)) -
      2955968 * math.cos(_toRad(2 * d)) -
      569925 * math.cos(_toRad(2 * mp)) +
      48888 * math.cos(_toRad(m)) -
      3149 * math.cos(_toRad(2 * f));

  final moonLon = l + dl / 1000000;
  final moonLat = db / 1000000;
  final dist = 385000560 + dr; // metres

  // Convert to equatorial coordinates
  final eps = 23.4393 - 0.0000004 * t;
  final sinLon = math.sin(_toRad(moonLon));
  final cosLon = math.cos(_toRad(moonLon));
  final sinLat = math.sin(_toRad(moonLat));
  final cosLat = math.cos(_toRad(moonLat));
  final sinEps = math.sin(_toRad(eps));
  final cosEps = math.cos(_toRad(eps));

  final dec = _toDeg(math.asin(sinLat * cosEps + cosLat * sinEps * sinLon));
  final raRad = math.atan2(sinLon * cosEps - (sinLat / cosLat) * sinEps, cosLon);
  final ra = (_toDeg(raRad) / 15.0 + 24) % 24;

  // Greenwich Mean Sidereal Time
  final gmst =
      6.697375 + 2400.0513369 * t + 0.0000258622 * t * t;
  final ut = dt.toUtc().hour + dt.toUtc().minute / 60.0 + dt.toUtc().second / 3600.0;
  final gast = (gmst + ut * 1.00273791) % 24;

  double gha = (gast - ra) * 15.0;
  gha = gha % 360;
  if (gha < 0) gha += 360;

  // Horizontal parallax and semi-diameter
  final hp = _toDeg(math.asin(6378140 / dist)) * 60; // arc-min
  final sd = 0.2725 * hp; // arc-min

  return _CelestialPosition(gha: gha, dec: dec, sd: sd, hp: hp);
}

// ─────────────────────────────────────────────────────────────────────────────
// Sight Reduction (intercept method)
// ─────────────────────────────────────────────────────────────────────────────

class SightResult {
  final double lha; // Local Hour Angle
  final double hc; // Computed altitude (degrees)
  final double hcDeg;
  final double hcMin;
  final double zn; // Azimuth (degrees True)
  final double intercept; // Ho − Hc in nautical miles (+ = toward)
  final bool toward; // true if Ho > Hc

  const SightResult({
    required this.lha,
    required this.hc,
    required this.hcDeg,
    required this.hcMin,
    required this.zn,
    required this.intercept,
    required this.toward,
  });
}

SightResult reduceSight({
  required double assumedLat, // degrees (+ N)
  required double assumedLon, // degrees (+ E)
  required double gha,
  required double dec,
  required double ho, // Observed altitude (degrees)
}) {
  // Local Hour Angle
  double lha = (gha + assumedLon) % 360;
  if (lha < 0) lha += 360;

  final latRad = _toRad(assumedLat);
  final decRad = _toRad(dec);
  final lhaRad = _toRad(lha);

  // Computed altitude (Hc)
  final sinHc = math.sin(latRad) * math.sin(decRad) +
      math.cos(latRad) * math.cos(decRad) * math.cos(lhaRad);
  final hc = _toDeg(math.asin(sinHc));

  // Azimuth angle (Z)
  final cosZ = (math.sin(decRad) - math.sin(latRad) * sinHc) /
      (math.cos(latRad) * math.cos(_toRad(hc)));
  double z = _toDeg(math.acos(cosZ.clamp(-1.0, 1.0)));

  // True Azimuth (Zn)
  double zn;
  if (lha > 180) {
    zn = z;
  } else {
    zn = 360 - z;
  }

  // Intercept (nautical miles)
  final a = (ho - hc) * 60.0;
  final toward = a >= 0;

  final hcDeg = hc.floor().toDouble();
  final hcMin = (hc - hcDeg) * 60.0;

  return SightResult(
    lha: lha,
    hc: hc,
    hcDeg: hcDeg,
    hcMin: hcMin,
    zn: zn,
    intercept: a.abs(),
    toward: toward,
  );
}

// Dip correction (height of eye in metres → arc-minutes)
double _dip(double heightM) => 1.758 * math.sqrt(heightM);

// Refraction correction (altitude in degrees → arc-minutes, subtract from sextant alt)
double _refraction(double altDeg) {
  if (altDeg < 5) return 0; // below 5° refraction is unreliable
  final a = _toRad(altDeg + 7.31 / (altDeg + 4.4));
  return 1.0 / math.tan(a); // arc-minutes
}

// ─────────────────────────────────────────────────────────────────────────────
// State
// ─────────────────────────────────────────────────────────────────────────────

enum _Body { sun, moon }

class _CelestialState {
  final _Body body;
  final DateTime obsTime;
  final double? assumedLat;
  final double? assumedLon;
  final double? sextantAlt; // degrees
  final double heightOfEyeM;
  final bool upperLimb;

  const _CelestialState({
    this.body = _Body.sun,
    required this.obsTime,
    this.assumedLat,
    this.assumedLon,
    this.sextantAlt,
    this.heightOfEyeM = 3.0,
    this.upperLimb = false,
  });

  _CelestialState copyWith({
    _Body? body,
    DateTime? obsTime,
    double? assumedLat,
    double? assumedLon,
    double? sextantAlt,
    double? heightOfEyeM,
    bool? upperLimb,
    bool clearLat = false,
    bool clearLon = false,
    bool clearAlt = false,
  }) {
    return _CelestialState(
      body: body ?? this.body,
      obsTime: obsTime ?? this.obsTime,
      assumedLat: clearLat ? null : (assumedLat ?? this.assumedLat),
      assumedLon: clearLon ? null : (assumedLon ?? this.assumedLon),
      sextantAlt: clearAlt ? null : (sextantAlt ?? this.sextantAlt),
      heightOfEyeM: heightOfEyeM ?? this.heightOfEyeM,
      upperLimb: upperLimb ?? this.upperLimb,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Screen
// ─────────────────────────────────────────────────────────────────────────────

class CelestialNavScreen extends ConsumerStatefulWidget {
  const CelestialNavScreen({super.key});

  @override
  ConsumerState<CelestialNavScreen> createState() => _CelestialNavScreenState();
}

class _CelestialNavScreenState extends ConsumerState<CelestialNavScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  late _CelestialState _state;

  final _latCtrl = TextEditingController();
  final _lonCtrl = TextEditingController();
  final _altDegCtrl = TextEditingController();
  final _altMinCtrl = TextEditingController();
  final _hoeCtrl = TextEditingController(text: '3.0');

  SightResult? _result;
  _CelestialPosition? _bodyPos;

  static final _timeFmt = DateFormat('HH:mm:ss');
  static final _dateFmt = DateFormat('yyyy-MM-dd');

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _state = _CelestialState(obsTime: DateTime.now().toUtc());
  }

  @override
  void dispose() {
    _tabs.dispose();
    _latCtrl.dispose();
    _lonCtrl.dispose();
    _altDegCtrl.dispose();
    _altMinCtrl.dispose();
    _hoeCtrl.dispose();
    super.dispose();
  }

  void _fillFromSignalK() {
    final sk = ref.read(signalKProvider);
    final pos = sk.ownVessel.navigation.position;
    if (pos != null) {
      _latCtrl.text = pos.latitude.toStringAsFixed(4);
      _lonCtrl.text = pos.longitude.toStringAsFixed(4);
      setState(() {
        _state = _state.copyWith(
          assumedLat: pos.latitude,
          assumedLon: pos.longitude,
        );
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Assumed position filled from Signal K'),
            duration: Duration(seconds: 2)),
      );
    }
  }

  void _setTimeNow() {
    setState(() {
      _state = _state.copyWith(obsTime: DateTime.now().toUtc());
    });
  }

  void _compute() {
    final lat = double.tryParse(_latCtrl.text.trim());
    final lon = double.tryParse(_lonCtrl.text.trim());
    final altDeg = double.tryParse(_altDegCtrl.text.trim()) ?? 0;
    final altMin = double.tryParse(_altMinCtrl.text.trim()) ?? 0;
    final hoe = double.tryParse(_hoeCtrl.text.trim()) ?? 3.0;

    if (lat == null || lon == null) {
      _showError('Enter assumed latitude and longitude');
      return;
    }
    if (_altDegCtrl.text.trim().isEmpty) {
      _showError('Enter sextant altitude');
      return;
    }

    final hs = altDeg + altMin / 60.0; // sextant altitude in degrees

    // Observed altitude (Ho) = Hs − dip − refraction ± SD
    final dipCorr = _dip(hoe); // arc-min
    final ha = hs - dipCorr / 60.0; // apparent altitude (after dip)
    final refCorr = _refraction(ha); // arc-min
    double ho = ha - refCorr / 60.0;

    // Semi-diameter correction
    final bp = _state.body == _Body.sun
        ? _sunPosition(_state.obsTime)
        : _moonPosition(_state.obsTime);

    if (_state.body == _Body.sun || _state.body == _Body.moon) {
      // Horizontal parallax correction for moon
      final additionalHP = _state.body == _Body.moon
          ? (bp.hp / 60.0) *
              math.cos(_toRad(ha))
          : 0.0;
      // SD: upper limb subtracts, lower limb adds
      final sdCorr = bp.sd / 60.0;
      ho = _state.upperLimb ? ho - sdCorr + additionalHP : ho + sdCorr + additionalHP;
    }

    final result = reduceSight(
      assumedLat: lat,
      assumedLon: lon,
      gha: bp.gha,
      dec: bp.dec,
      ho: ho,
    );

    setState(() {
      _bodyPos = bp;
      _result = result;
      _state = _state.copyWith(
        assumedLat: lat,
        assumedLon: lon,
        sextantAlt: hs,
        heightOfEyeM: hoe,
      );
      _tabs.animateTo(2);
    });
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  // ── Live ephemeris tab ────────────────────────────────────────────────────

  Widget _buildEphemerisTab() {
    final now = DateTime.now().toUtc();
    final sun = _sunPosition(now);
    final moon = _moonPosition(now);

    String ghaStr(double gha) {
      final d = gha.floor();
      final m = (gha - d) * 60;
      return '$d° ${m.toStringAsFixed(1)}\'';
    }

    String decStr(double dec) {
      final dir = dec >= 0 ? 'N' : 'S';
      final abs = dec.abs();
      final d = abs.floor();
      final m = (abs - d) * 60;
      return '$d° ${m.toStringAsFixed(1)}\' $dir';
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader('UTC Time', '${_dateFmt.format(now)}  ${_timeFmt.format(now)}'),
          const SizedBox(height: 16),

          _bodyCard(
            icon: Icons.wb_sunny,
            color: Colors.orange,
            name: 'Sun',
            gha: ghaStr(sun.gha),
            dec: decStr(sun.dec),
            extras: {
              'Semi-diameter': '${sun.sd.toStringAsFixed(1)}\' (lower limb)',
              'Parallax': '${sun.hp.toStringAsFixed(2)}\'',
            },
          ),
          const SizedBox(height: 12),

          _bodyCard(
            icon: Icons.nightlight_round,
            color: Colors.blueGrey,
            name: 'Moon',
            gha: ghaStr(moon.gha),
            dec: decStr(moon.dec),
            extras: {
              'Semi-diameter': '${moon.sd.toStringAsFixed(1)}\'',
              'Horiz. parallax': '${moon.hp.toStringAsFixed(1)}\'',
            },
          ),
          const SizedBox(height: 16),
          Text(
            'GHA and Dec computed for current UTC time using Meeus algorithms (accuracy ~1 arc-minute).',
            style: TextStyle(fontSize: 11, color: Theme.of(context).hintColor),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String label, String value) {
    return Row(
      children: [
        Text('$label: ',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        Text(value, style: const TextStyle(fontSize: 13)),
      ],
    );
  }

  Widget _bodyCard({
    required IconData icon,
    required Color color,
    required String name,
    required String gha,
    required String dec,
    required Map<String, String> extras,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(width: 8),
              Text(name,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16)),
            ]),
            const SizedBox(height: 10),
            _DataRow('GHA', gha),
            _DataRow('Dec', dec),
            ...extras.entries.map((e) => _DataRow(e.key, e.value)),
          ],
        ),
      ),
    );
  }

  // ── Sight input tab ───────────────────────────────────────────────────────

  Widget _buildInputTab(bool skConnected) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Body selector
          Text('Body', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          SegmentedButton<_Body>(
            segments: const [
              ButtonSegment(
                  value: _Body.sun,
                  icon: Icon(Icons.wb_sunny),
                  label: Text('Sun')),
              ButtonSegment(
                  value: _Body.moon,
                  icon: Icon(Icons.nightlight_round),
                  label: Text('Moon')),
            ],
            selected: {_state.body},
            onSelectionChanged: (s) =>
                setState(() => _state = _state.copyWith(body: s.first)),
          ),

          const SizedBox(height: 16),

          // Limb (sun/moon only)
          Text('Limb observed', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Lower')),
              ButtonSegment(value: true, label: Text('Upper')),
            ],
            selected: {_state.upperLimb},
            onSelectionChanged: (s) =>
                setState(() => _state = _state.copyWith(upperLimb: s.first)),
          ),

          const SizedBox(height: 16),

          // Observation time
          Text('Observation time (UTC)',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  decoration: BoxDecoration(
                    border: Border.all(
                        color: Theme.of(context).colorScheme.outline),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${_dateFmt.format(_state.obsTime)}  ${_timeFmt.format(_state.obsTime)} Z',
                    style: const TextStyle(fontSize: 15),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: _setTimeNow,
                child: const Text('Now'),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Assumed position
          Text('Assumed position',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          if (skConnected) ...[
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.download, size: 16),
                label: const Text('Fill from Signal K'),
                onPressed: _fillFromSignalK,
              ),
            ),
            const SizedBox(height: 8),
          ],
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _latCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true, signed: true),
                  decoration: const InputDecoration(
                    labelText: 'Lat (°)',
                    hintText: '59.33',
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
                    labelText: 'Lon (°)',
                    hintText: '18.07',
                    border: OutlineInputBorder(),
                    suffixText: '°',
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Sextant altitude
          Text('Sextant altitude (Hs)',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _altDegCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: false),
                  decoration: const InputDecoration(
                    labelText: 'Degrees',
                    hintText: '42',
                    border: OutlineInputBorder(),
                    suffixText: '°',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _altMinCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Minutes',
                    hintText: '30.5',
                    border: OutlineInputBorder(),
                    suffixText: '\'',
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Height of eye
          TextField(
            controller: _hoeCtrl,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Height of eye (metres)',
              hintText: '3.0',
              border: OutlineInputBorder(),
              suffixText: 'm',
              helperText: 'Your eye height above sea level',
            ),
          ),

          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              icon: const Icon(Icons.calculate),
              label: const Text('Reduce Sight'),
              onPressed: _compute,
            ),
          ),
        ],
      ),
    );
  }

  // ── Result tab ────────────────────────────────────────────────────────────

  Widget _buildResultTab() {
    if (_result == null || _bodyPos == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.star_border,
                  size: 64, color: Theme.of(context).hintColor),
              const SizedBox(height: 16),
              const Text('No sight reduced yet.',
                  style: TextStyle(fontSize: 16)),
              const SizedBox(height: 8),
              Text(
                'Enter your observed altitude and assumed position in the Sight tab, then tap Reduce Sight.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Theme.of(context).hintColor, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    final r = _result!;
    final bp = _bodyPos!;

    String ghaStr(double gha) {
      final d = gha.floor();
      final m = (gha - d) * 60;
      return '$d° ${m.toStringAsFixed(1)}\'';
    }

    String decStr(double dec) {
      final dir = dec >= 0 ? 'N' : 'S';
      final abs = dec.abs();
      final d = abs.floor();
      final m = (abs - d) * 60;
      return '$d° ${m.toStringAsFixed(1)}\' $dir';
    }

    final interceptDir = r.toward ? 'TOWARD' : 'AWAY';
    final interceptColor =
        r.toward ? Colors.green.shade700 : Colors.red.shade700;
    final bodyName = _state.body == _Body.sun ? 'Sun' : 'Moon';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Body position at sight time
          Text('$bodyName at ${_timeFmt.format(_state.obsTime)} UTC',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  _DataRow('GHA', ghaStr(bp.gha)),
                  _DataRow('Dec', decStr(bp.dec)),
                  _DataRow('LHA',
                      '${ghaStr(r.lha)} (${r.lha.toStringAsFixed(1)}°)'),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Reduction results
          Text('Sight Reduction',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  _DataRow(
                    'Hc (computed)',
                    '${r.hcDeg.toStringAsFixed(0)}° ${r.hcMin.toStringAsFixed(1)}\'',
                  ),
                  _DataRow(
                    'Zn (azimuth)',
                    '${r.zn.toStringAsFixed(1)}° T',
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Intercept — highlighted
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: r.toward
                  ? Colors.green.withValues(alpha: 0.1)
                  : Colors.red.withValues(alpha: 0.1),
              border: Border.all(color: interceptColor),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                Text(
                  '${r.intercept.toStringAsFixed(1)} nm',
                  style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: interceptColor),
                ),
                Text(
                  interceptDir,
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: interceptColor),
                ),
                const SizedBox(height: 6),
                Text(
                  'Intercept (a): plot ${r.intercept.toStringAsFixed(1)} nm '
                  '${r.toward ? "toward" : "away from"} ${r.zn.toStringAsFixed(0)}°',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Plotting note
          Card(
            color: Theme.of(context).colorScheme.secondaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(children: [
                    Icon(Icons.info_outline, size: 16),
                    SizedBox(width: 6),
                    Text('How to plot',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ]),
                  const SizedBox(height: 6),
                  Text(
                    '1. Mark assumed position (AP) on chart.\n'
                    '2. Draw azimuth line from AP at ${r.zn.toStringAsFixed(0)}°T.\n'
                    '3. Plot intercept: ${r.intercept.toStringAsFixed(1)} nm '
                    '${r.toward ? "toward" : "away from"} the body.\n'
                    '4. Draw LOP perpendicular to the azimuth through the intercept point.',
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 8),
          Text(
            'Note: For best accuracy, use the closest whole-degree assumed position. Accuracy is ~1 arc-min for body position, ±5 nm on the LOP.',
            style: TextStyle(
                fontSize: 11, color: Theme.of(context).hintColor),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final skState = ref.watch(signalKProvider);
    final skConnected =
        skState.connectionState == SignalKConnectionState.connected;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Celestial Navigation'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(icon: Icon(Icons.auto_awesome), text: 'Ephemeris'),
            Tab(icon: Icon(Icons.edit), text: 'Sight'),
            Tab(icon: Icon(Icons.calculate), text: 'Result'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _buildEphemerisTab(),
          _buildInputTab(skConnected),
          _buildResultTab(),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared widget
// ─────────────────────────────────────────────────────────────────────────────

class _DataRow extends StatelessWidget {
  final String label;
  final String value;
  const _DataRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
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
