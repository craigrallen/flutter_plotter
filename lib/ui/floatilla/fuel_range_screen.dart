import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/providers/vessel_provider.dart';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const double _kNmToMetres = 1852.0;
const double _kLitresToUsGal = 0.264172;
// const double _kUsGalToLitres = 3.78541; // reserved for future use

// Burn-rate estimates at different speeds (relative to cruising rate).
// Approximate power-law: fuel ~ speed^2.7 (simplified)
const List<double> _kSpeedTable = [4, 5, 6, 7, 8];

double _burnAtSpeed(double cruiseBurnLph, double cruiseKn, double targetKn) {
  if (cruiseKn <= 0) return cruiseBurnLph;
  final ratio = math.pow(targetKn / cruiseKn, 2.7).toDouble();
  return cruiseBurnLph * ratio;
}

// ---------------------------------------------------------------------------
// SharedPreferences keys
// ---------------------------------------------------------------------------

const String _kPrefCapacity = 'fuel_capacity_l';
const String _kPrefLevel = 'fuel_level_l';
const String _kPrefBurnLph = 'fuel_burn_lph';
const String _kPrefReserve = 'fuel_reserve_pct';
const String _kPrefCruiseKn = 'fuel_cruise_kn';
const String _kPrefUseGal = 'fuel_use_gal';
const String _kPrefBurnPerNm = 'fuel_burn_per_nm'; // vs per hour

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class FuelRangeScreen extends ConsumerStatefulWidget {
  const FuelRangeScreen({super.key});

  @override
  ConsumerState<FuelRangeScreen> createState() => _FuelRangeScreenState();
}

class _FuelRangeScreenState extends ConsumerState<FuelRangeScreen> {
  final _mapController = MapController();

  // Input values (always stored in litres / L/h internally)
  double _capacityL = 200.0;
  double _levelL = 120.0;
  double _burnLph = 8.0; // L/h at cruising speed
  double _cruiseKn = 6.0;
  double _reservePct = 20.0;

  // Display toggles
  bool _useGal = false;
  bool _burnPerNm = false; // vs per hour

  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _capacityL = prefs.getDouble(_kPrefCapacity) ?? 200.0;
      _levelL = prefs.getDouble(_kPrefLevel) ?? 120.0;
      _burnLph = prefs.getDouble(_kPrefBurnLph) ?? 8.0;
      _reservePct = prefs.getDouble(_kPrefReserve) ?? 20.0;
      _cruiseKn = prefs.getDouble(_kPrefCruiseKn) ?? 6.0;
      _useGal = prefs.getBool(_kPrefUseGal) ?? false;
      _burnPerNm = prefs.getBool(_kPrefBurnPerNm) ?? false;
      _loaded = true;
    });
  }

  Future<void> _savePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.setDouble(_kPrefCapacity, _capacityL),
      prefs.setDouble(_kPrefLevel, _levelL),
      prefs.setDouble(_kPrefBurnLph, _burnLph),
      prefs.setDouble(_kPrefReserve, _reservePct),
      prefs.setDouble(_kPrefCruiseKn, _cruiseKn),
      prefs.setBool(_kPrefUseGal, _useGal),
      prefs.setBool(_kPrefBurnPerNm, _burnPerNm),
    ]);
  }

  // ---------------------------------------------------------------------------
  // Calculations
  // ---------------------------------------------------------------------------

  double get _usableFuelL {
    final reserve = _levelL * (_reservePct / 100.0);
    return math.max(0.0, _levelL - reserve);
  }

  double get _rangeNm {
    if (_burnLph <= 0 || _cruiseKn <= 0) return 0;
    final hours = _usableFuelL / _burnLph;
    return hours * _cruiseKn;
  }

  double get _enduranceH {
    if (_burnLph <= 0) return 0;
    return _usableFuelL / _burnLph;
  }

  // Range-ring radius in metres
  double get _rangeRingM => _rangeNm * _kNmToMetres;

  String _fmt(double litres) {
    if (_useGal) {
      return '${(litres * _kLitresToUsGal).toStringAsFixed(1)} gal';
    }
    return '${litres.toStringAsFixed(1)} L';
  }

  String _fmtBurn(double lph) {
    if (_burnPerNm) {
      final perNm = _cruiseKn > 0 ? lph / _cruiseKn : 0;
      if (_useGal) {
        return '${(perNm * _kLitresToUsGal).toStringAsFixed(2)} gal/nm';
      }
      return '${perNm.toStringAsFixed(2)} L/nm';
    }
    if (_useGal) {
      return '${(lph * _kLitresToUsGal).toStringAsFixed(2)} gph';
    }
    return '${lph.toStringAsFixed(1)} L/h';
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final vessel = ref.watch(vesselProvider);
    final sog = vessel.sog ?? _cruiseKn;
    final pos = vessel.position;

    // ETE at current SOG
    final eteH = sog > 0 ? _usableFuelL / _burnLph : 0.0;
    final rangeSogNm = eteH * sog;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Fuel Range'),
        actions: [
          TextButton.icon(
            onPressed: () {
              setState(() => _useGal = !_useGal);
              _savePrefs();
            },
            icon: const Icon(Icons.swap_horiz, size: 18),
            label: Text(_useGal ? 'Switch to L' : 'Switch to gal'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Inputs
            _SectionHeader(label: 'Fuel Inputs'),
            const SizedBox(height: 12),
            _buildInputs(context),
            const SizedBox(height: 20),

            // Results
            _SectionHeader(label: 'Results'),
            const SizedBox(height: 12),
            _buildResults(context, rangeSogNm, eteH),
            const SizedBox(height: 20),

            // Map range ring
            if (pos != null) ...[
              _SectionHeader(label: 'Range Ring'),
              const SizedBox(height: 12),
              _buildMap(pos),
              const SizedBox(height: 20),
            ],

            // Speed table
            _SectionHeader(label: 'Range at Different Speeds'),
            const SizedBox(height: 12),
            _buildSpeedTable(context),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildInputs(BuildContext context) {
    return Column(
      children: [
        // Capacity
        _SliderRow(
          label: 'Total capacity',
          value: _useGal ? _capacityL * _kLitresToUsGal : _capacityL,
          min: _useGal ? 10 : 20,
          max: _useGal ? 400 : 1500,
          unit: _useGal ? 'gal' : 'L',
          onChanged: (v) {
            setState(() =>
                _capacityL = _useGal ? v / _kLitresToUsGal : v);
            _savePrefs();
          },
        ),
        const SizedBox(height: 12),
        // Current level
        _SliderRow(
          label: 'Current level',
          value: _useGal ? _levelL * _kLitresToUsGal : _levelL,
          min: 0,
          max: _useGal ? _capacityL * _kLitresToUsGal : _capacityL,
          unit: _useGal ? 'gal' : 'L',
          onChanged: (v) {
            setState(
                () => _levelL = _useGal ? v / _kLitresToUsGal : v.clamp(0, _capacityL));
            _savePrefs();
          },
        ),
        const SizedBox(height: 12),
        // Burn rate toggle label
        Row(
          children: [
            const Text('Burn rate'),
            const Spacer(),
            TextButton(
              onPressed: () {
                setState(() => _burnPerNm = !_burnPerNm);
                _savePrefs();
              },
              child: Text(_burnPerNm ? 'L/nm  switch to L/h' : 'L/h  switch to L/nm'),
            ),
          ],
        ),
        _SliderRow(
          label: _burnPerNm ? 'Burn (L/nm)' : 'Burn (L/h)',
          value: _burnPerNm
              ? (_cruiseKn > 0 ? _burnLph / _cruiseKn : 0)
              : _burnLph,
          min: 0.5,
          max: _burnPerNm ? 10 : 50,
          unit: _burnPerNm ? 'L/nm' : 'L/h',
          onChanged: (v) {
            setState(() {
              if (_burnPerNm) {
                _burnLph = v * _cruiseKn;
              } else {
                _burnLph = v;
              }
            });
            _savePrefs();
          },
        ),
        const SizedBox(height: 12),
        // Cruising speed
        _SliderRow(
          label: 'Cruising speed',
          value: _cruiseKn,
          min: 1,
          max: 20,
          unit: 'kn',
          onChanged: (v) {
            setState(() => _cruiseKn = v);
            _savePrefs();
          },
        ),
        const SizedBox(height: 12),
        // Reserve %
        _SliderRow(
          label: 'Reserve',
          value: _reservePct,
          min: 0,
          max: 50,
          unit: '%',
          onChanged: (v) {
            setState(() => _reservePct = v);
            _savePrefs();
          },
        ),
      ],
    );
  }

  Widget _buildResults(
      BuildContext context, double rangeSogNm, double eteH) {
    final enduranceH = _enduranceH;
    final endH = enduranceH.floor();
    final endM = ((enduranceH - endH) * 60).round();

    final eteHi = eteH.floor();
    final eteM = ((eteH - eteHi) * 60).round();

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _ResultChip(
          label: 'Usable fuel',
          value: _fmt(_usableFuelL),
          icon: Icons.local_gas_station,
          color: Colors.blue,
        ),
        _ResultChip(
          label: 'Range @ cruise',
          value: '${_rangeNm.toStringAsFixed(0)} nm',
          icon: Icons.straighten,
          color: Colors.green,
        ),
        _ResultChip(
          label: 'Endurance',
          value: '${endH}h ${endM}m',
          icon: Icons.timer,
          color: Colors.teal,
        ),
        _ResultChip(
          label: 'Range @ SOG',
          value: '${rangeSogNm.toStringAsFixed(0)} nm',
          icon: Icons.speed,
          color: Colors.orange,
        ),
        _ResultChip(
          label: 'ETE @ SOG',
          value: '${eteHi}h ${eteM}m',
          icon: Icons.access_time,
          color: Colors.purple,
        ),
      ],
    );
  }

  Widget _buildMap(LatLng pos) {
    const zoomFit = 9.0;
    return SizedBox(
      height: 280,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: pos,
            initialZoom: zoomFit,
          ),
          children: [
            TileLayer(
              urlTemplate:
                  'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.floatilla.app',
            ),
            CircleLayer(
              circles: [
                // Outer green ring
                CircleMarker(
                  point: pos,
                  radius: _rangeRingM,
                  useRadiusInMeter: true,
                  color: Colors.green.withValues(alpha: 0.08),
                  borderColor: Colors.green.withValues(alpha: 0.6),
                  borderStrokeWidth: 3,
                ),
                // 75% range — orange warning ring
                CircleMarker(
                  point: pos,
                  radius: _rangeRingM * 0.75,
                  useRadiusInMeter: true,
                  color: Colors.orange.withValues(alpha: 0.05),
                  borderColor: Colors.orange.withValues(alpha: 0.4),
                  borderStrokeWidth: 1.5,
                ),
                // 50% range — red inner ring
                CircleMarker(
                  point: pos,
                  radius: _rangeRingM * 0.5,
                  useRadiusInMeter: true,
                  color: Colors.red.withValues(alpha: 0.04),
                  borderColor: Colors.red.withValues(alpha: 0.3),
                  borderStrokeWidth: 1,
                ),
              ],
            ),
            MarkerLayer(
              markers: [
                Marker(
                  point: pos,
                  width: 20,
                  height: 20,
                  child: const Icon(
                    Icons.directions_boat,
                    color: Colors.blue,
                    size: 20,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSpeedTable(BuildContext context) {
    final rows = _kSpeedTable.map((kn) {
      final burn = _burnAtSpeed(_burnLph, _cruiseKn, kn);
      final endH = burn > 0 ? _usableFuelL / burn : 0.0;
      final range = endH * kn;
      return (kn: kn, burn: burn, range: range, endH: endH);
    }).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Table(
          columnWidths: const {
            0: FlexColumnWidth(1),
            1: FlexColumnWidth(2),
            2: FlexColumnWidth(2),
            3: FlexColumnWidth(2),
          },
          children: [
            TableRow(
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest,
              ),
              children: const [
                _TCell('Speed', header: true),
                _TCell('Burn rate', header: true),
                _TCell('Range', header: true),
                _TCell('Endurance', header: true),
              ],
            ),
            for (final r in rows)
              TableRow(
                children: [
                  _TCell('${r.kn.toStringAsFixed(0)} kn'),
                  _TCell(_fmtBurn(r.burn)),
                  _TCell('${r.range.toStringAsFixed(0)} nm'),
                  _TCell(
                      '${r.endH.floor()}h ${((r.endH - r.endH.floor()) * 60).round()}m'),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Helper widgets
// ---------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final String unit;
  final ValueChanged<double> onChanged;

  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.unit,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final safeValue = value.clamp(min, max);
    return Row(
      children: [
        SizedBox(
          width: 110,
          child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ),
        Expanded(
          child: Slider(
            value: safeValue,
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 80,
          child: Text(
            '${safeValue.toStringAsFixed(unit == '%' || unit == 'kn' ? 0 : 1)} $unit',
            textAlign: TextAlign.right,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

class _ResultChip extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _ResultChip({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TCell extends StatelessWidget {
  final String text;
  final bool header;
  const _TCell(this.text, {this.header = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      child: Text(
        text,
        style: TextStyle(
          fontWeight: header ? FontWeight.bold : FontWeight.normal,
          fontSize: header ? 12 : 13,
        ),
      ),
    );
  }
}
