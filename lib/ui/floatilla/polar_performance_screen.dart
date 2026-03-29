import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/providers/signalk_provider.dart';
import '../../core/signalk/signalk_source.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Polar data model
// ─────────────────────────────────────────────────────────────────────────────

/// A single polar row: true wind speed → list of (TWA °, boat speed kn).
class PolarRow {
  final double tws; // knots
  final List<(double twa, double bsp)> entries; // twa in degrees, bsp in knots

  const PolarRow({required this.tws, required this.entries});
}

/// Parsed boat polar from CSV.
class PolarData {
  final List<double> twsValues; // header wind speeds
  final List<double> twaValues; // row angles
  /// matrix[twaIndex][twsIndex] = bsp (kn), or null if missing
  final List<List<double?>> matrix;

  const PolarData({
    required this.twsValues,
    required this.twaValues,
    required this.matrix,
  });

  /// Return target BSP for given TWA and TWS using bilinear interpolation.
  /// Returns null if outside table range.
  double? targetBsp(double twa, double tws) {
    if (twaValues.isEmpty || twsValues.isEmpty) return null;

    final absTwa = twa.abs();

    // Find bracketing TWA indices
    int twaLow = -1;
    for (int i = 0; i < twaValues.length - 1; i++) {
      if (twaValues[i] <= absTwa && absTwa <= twaValues[i + 1]) {
        twaLow = i;
        break;
      }
    }
    if (twaLow == -1) {
      // Clamp to nearest
      if (absTwa <= twaValues.first) twaLow = 0;
      else twaLow = twaValues.length - 2;
    }
    final twaHigh = (twaLow + 1).clamp(0, twaValues.length - 1);

    // Find bracketing TWS indices
    int twsLow = -1;
    for (int i = 0; i < twsValues.length - 1; i++) {
      if (twsValues[i] <= tws && tws <= twsValues[i + 1]) {
        twsLow = i;
        break;
      }
    }
    if (twsLow == -1) {
      if (tws <= twsValues.first) twsLow = 0;
      else twsLow = twsValues.length - 2;
    }
    final twsHigh = (twsLow + 1).clamp(0, twsValues.length - 1);

    final v00 = matrix[twaLow][twsLow];
    final v01 = matrix[twaLow][twsHigh];
    final v10 = matrix[twaHigh][twsLow];
    final v11 = matrix[twaHigh][twsHigh];

    if (v00 == null || v01 == null || v10 == null || v11 == null) {
      return v00 ?? v01 ?? v10 ?? v11;
    }

    final twsRange = twsValues[twsHigh] - twsValues[twsLow];
    final twaRange = twaValues[twaHigh] - twaValues[twaLow];
    final tF = twsRange == 0 ? 0.0 : (tws - twsValues[twsLow]) / twsRange;
    final aF = twaRange == 0 ? 0.0 : (absTwa - twaValues[twaLow]) / twaRange;

    final v0 = v00 + (v01 - v00) * tF;
    final v1 = v10 + (v11 - v10) * tF;
    return v0 + (v1 - v0) * aF;
  }

  /// Find optimal VMG angle for given TWS (upwind or downwind).
  /// [upwind] = true for beats, false for runs.
  (double optAngle, double optVmg)? optimalVmg(double tws, {required bool upwind}) {
    double bestVmg = -1;
    double bestAngle = upwind ? 45 : 150;

    for (int i = 0; i < twaValues.length; i++) {
      final angle = twaValues[i];
      final isUp = angle < 90;
      if (upwind && !isUp) continue;
      if (!upwind && isUp) continue;

      // Find bracketing TWS
      int twsLow = 0;
      for (int j = 0; j < twsValues.length - 1; j++) {
        if (twsValues[j] <= tws) twsLow = j;
      }
      final twsHigh = (twsLow + 1).clamp(0, twsValues.length - 1);
      final v0 = matrix[i][twsLow];
      final v1 = matrix[i][twsHigh];
      if (v0 == null) continue;
      double bsp = v0;
      if (v1 != null && twsValues[twsHigh] != twsValues[twsLow]) {
        final f = (tws - twsValues[twsLow]) / (twsValues[twsHigh] - twsValues[twsLow]);
        bsp = v0 + (v1 - v0) * f;
      }

      final rad = angle * math.pi / 180;
      final vmg = bsp * math.cos(rad).abs();
      if (vmg > bestVmg) {
        bestVmg = vmg;
        bestAngle = angle;
      }
    }

    return bestVmg > 0 ? (bestAngle, bestVmg) : null;
  }
}

/// Parse a CSV polar.
/// Expected format (ORC-style):
///   twa/tws,6,8,10,12,14,16,20
///   52,5.2,6.1,...
///   60,5.5,...
PolarData? parsePolarCsv(String csv) {
  final lines = csv
      .split(RegExp(r'[\r\n]+'))
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();

  if (lines.length < 2) return null;

  // Header
  final headerParts = lines[0].split(',');
  if (headerParts.length < 2) return null;

  final twsValues = <double>[];
  for (int i = 1; i < headerParts.length; i++) {
    final v = double.tryParse(headerParts[i].trim());
    if (v != null) twsValues.add(v);
  }
  if (twsValues.isEmpty) return null;

  final twaValues = <double>[];
  final matrix = <List<double?>>[];

  for (int r = 1; r < lines.length; r++) {
    final parts = lines[r].split(',');
    final twa = double.tryParse(parts[0].trim());
    if (twa == null) continue;

    twaValues.add(twa);
    final row = <double?>[];
    for (int c = 0; c < twsValues.length; c++) {
      final idx = c + 1;
      final v = idx < parts.length ? double.tryParse(parts[idx].trim()) : null;
      row.add(v);
    }
    matrix.add(row);
  }

  if (twaValues.isEmpty) return null;
  return PolarData(twsValues: twsValues, twaValues: twaValues, matrix: matrix);
}

// ─────────────────────────────────────────────────────────────────────────────
// Provider
// ─────────────────────────────────────────────────────────────────────────────

const _kPolarPrefsKey = 'floatilla_polar_csv';

final polarDataProvider =
    StateNotifierProvider<PolarNotifier, PolarData?>((ref) {
  return PolarNotifier();
});

class PolarNotifier extends StateNotifier<PolarData?> {
  PolarNotifier() : super(null) {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final csv = prefs.getString(_kPolarPrefsKey);
      if (csv != null && csv.isNotEmpty) {
        state = parsePolarCsv(csv);
      }
    } catch (_) {}
  }

  Future<void> load(String csv) async {
    final parsed = parsePolarCsv(csv);
    state = parsed;
    if (parsed != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kPolarPrefsKey, csv);
    }
  }

  Future<void> clear() async {
    state = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kPolarPrefsKey);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Main screen
// ─────────────────────────────────────────────────────────────────────────────

class PolarPerformanceScreen extends ConsumerStatefulWidget {
  const PolarPerformanceScreen({super.key});

  @override
  ConsumerState<PolarPerformanceScreen> createState() =>
      _PolarPerformanceScreenState();
}

class _PolarPerformanceScreenState
    extends ConsumerState<PolarPerformanceScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _pickCsv() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv', 'txt', 'pol'],
      );
      if (result == null || result.files.isEmpty) return;

      final bytes = result.files.first.bytes;
      String? content;
      if (bytes != null) {
        content = utf8.decode(bytes);
      } else {
        final path = result.files.first.path;
        if (path == null) return;
        final file = await _readFile(path);
        content = file;
      }
      if (content == null || content.isEmpty) return;

      await ref.read(polarDataProvider.notifier).load(content);

      if (!mounted) return;
      final polar = ref.read(polarDataProvider);
      if (polar == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not parse CSV. Check format.')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Polar loaded: ${polar.twaValues.length} angles × '
              '${polar.twsValues.length} wind speeds',
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error loading file: $e')));
    }
  }

  Future<String?> _readFile(String path) async {
    try {
      return await File(path).readAsString();
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final polar = ref.watch(polarDataProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Polar Performance'),
        actions: [
          if (polar != null)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Remove polar',
              onPressed: () => ref.read(polarDataProvider.notifier).clear(),
            ),
          IconButton(
            icon: const Icon(Icons.upload_file),
            tooltip: 'Load polar CSV',
            onPressed: _pickCsv,
          ),
        ],
        bottom: polar != null
            ? TabBar(
                controller: _tabs,
                tabs: const [
                  Tab(text: 'Live'),
                  Tab(text: 'Polar'),
                ],
              )
            : null,
      ),
      body: polar == null
          ? _buildEmpty()
          : TabBarView(
              controller: _tabs,
              children: [
                _LiveTab(polar: polar),
                _PolarChartTab(polar: polar),
              ],
            ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.sailing, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              'No polar loaded',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text(
              'Upload a boat polar CSV to see VMG targets\n'
              'and live performance against polar.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              icon: const Icon(Icons.upload_file),
              label: const Text('Load polar CSV'),
              onPressed: _pickCsv,
            ),
            const SizedBox(height: 16),
            const _CsvFormatHint(),
          ],
        ),
      ),
    );
  }
}

class _CsvFormatHint extends StatelessWidget {
  const _CsvFormatHint();

  @override
  Widget build(BuildContext context) {
    return Card(
      color:
          Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.5),
      child: const Padding(
        padding: EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Expected CSV format:',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
            SizedBox(height: 6),
            Text(
              'twa/tws,6,8,10,12,14,16,20\n'
              '52,5.2,6.1,6.8,7.1,7.3,7.4,7.5\n'
              '60,5.5,6.4,7.0,7.4,7.5,7.6,7.7\n'
              '...',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                color: Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Live tab — shows live TWA/TWS/BSP vs target
// ─────────────────────────────────────────────────────────────────────────────

class _LiveTab extends ConsumerWidget {
  final PolarData polar;

  const _LiveTab({required this.polar});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final skState = ref.watch(signalKProvider);
    final env = skState.ownVessel.environment;
    final nav = skState.ownVessel.navigation;
    final connected =
        skState.connectionState == SignalKConnectionState.connected;

    if (!connected) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.link_off, size: 48, color: Colors.grey),
            SizedBox(height: 12),
            Text('No Signal K connection',
                style: TextStyle(color: Colors.grey)),
            SizedBox(height: 6),
            Text(
              'Connect to Signal K in Settings to see live polar data.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    // Signal K parser already converts: m/s → kn, radians → degrees
    final twaDeg = env.windAngleTrueWater;   // degrees
    final twsKn = env.windSpeedTrue;          // knots
    final sogKn = nav.sog;                    // knots
    final awsKn = env.windSpeedApparent;      // knots
    final awaDeg = env.windAngleApparent;     // degrees

    // Target BSP from polar
    double? targetBsp;
    double? perfPct;
    (double, double)? upwindVmg;
    (double, double)? downwindVmg;

    if (twaDeg != null && twsKn != null) {
      targetBsp = polar.targetBsp(twaDeg, twsKn);
      if (targetBsp != null && sogKn != null && targetBsp > 0) {
        perfPct = (sogKn / targetBsp * 100).clamp(0, 200);
      }
      upwindVmg = polar.optimalVmg(twsKn, upwind: true);
      downwindVmg = polar.optimalVmg(twsKn, upwind: false);
    }

    final Color perfColor;
    if (perfPct == null) {
      perfColor = Colors.grey;
    } else if (perfPct >= 95) {
      perfColor = Colors.green;
    } else if (perfPct >= 80) {
      perfColor = Colors.orange;
    } else {
      perfColor = Colors.red;
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Performance % card
          if (perfPct != null)
            _PerfCard(pct: perfPct, color: perfColor)
          else
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: const [
                    Icon(Icons.info_outline, color: Colors.grey),
                    SizedBox(width: 8),
                    Text(
                      'Waiting for TWA + TWS data…',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),

          const SizedBox(height: 16),

          // Wind & speed gauges
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Live conditions',
                      style: TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 14)),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 20,
                    runSpacing: 14,
                    children: [
                      _DataCell(
                        label: 'TWA',
                        value: twaDeg != null
                            ? '${twaDeg.toStringAsFixed(0)}°'
                            : '—',
                        sub: twaDeg == null
                            ? null
                            : twaDeg.abs() < 90
                                ? 'Upwind'
                                : 'Downwind',
                        color: twaDeg == null
                            ? null
                            : twaDeg.abs() < 90
                                ? Colors.blue
                                : Colors.green,
                      ),
                      _DataCell(
                        label: 'TWS',
                        value: twsKn != null
                            ? '${twsKn.toStringAsFixed(1)} kn'
                            : '—',
                      ),
                      _DataCell(
                        label: 'AWS',
                        value: awsKn != null
                            ? '${awsKn.toStringAsFixed(1)} kn'
                            : '—',
                      ),
                      _DataCell(
                        label: 'AWA',
                        value: awaDeg != null
                            ? '${awaDeg.toStringAsFixed(0)}°'
                            : '—',
                      ),
                      _DataCell(
                        label: 'SOG',
                        value: sogKn != null
                            ? '${sogKn.toStringAsFixed(1)} kn'
                            : '—',
                      ),
                      _DataCell(
                        label: 'Target BSP',
                        value: targetBsp != null
                            ? '${targetBsp.toStringAsFixed(1)} kn'
                            : '—',
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // VMG targets
          if (twsKn != null) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'VMG targets @ ${twsKn.toStringAsFixed(0)} kn TWS',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _VmgCard(
                            label: '▲ Upwind',
                            angle: upwindVmg?.$1,
                            vmg: upwindVmg?.$2,
                            color: Colors.blue,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _VmgCard(
                            label: '▼ Downwind',
                            angle: downwindVmg?.$1,
                            vmg: downwindVmg?.$2,
                            color: Colors.green,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],

          const SizedBox(height: 16),

          // Polar table for current TWS
          if (twsKn != null) _PolarTableCard(polar: polar, tws: twsKn),
        ],
      ),
    );
  }
}

class _PerfCard extends StatelessWidget {
  final double pct;
  final Color color;

  const _PerfCard({required this.pct, required this.color});

  @override
  Widget build(BuildContext context) {
    final label = pct >= 100
        ? 'On or above polar!'
        : pct >= 95
            ? 'Near polar target'
            : pct >= 80
                ? 'Below target'
                : 'Well below target';

    return Card(
      color: color.withOpacity(0.1),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color.withOpacity(0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.show_chart, color: color),
                const SizedBox(width: 8),
                Text(
                  'Performance',
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: color),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '${pct.toStringAsFixed(0)}%',
              style: TextStyle(
                fontSize: 48,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(color: color, fontSize: 13)),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: (pct / 100).clamp(0, 1).toDouble(),
              backgroundColor: color.withOpacity(0.15),
              valueColor: AlwaysStoppedAnimation(color),
              minHeight: 8,
              borderRadius: BorderRadius.circular(4),
            ),
          ],
        ),
      ),
    );
  }
}

class _VmgCard extends StatelessWidget {
  final String label;
  final double? angle;
  final double? vmg;
  final Color color;

  const _VmgCard({
    required this.label,
    required this.angle,
    required this.vmg,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  fontWeight: FontWeight.w700, fontSize: 13, color: color)),
          const SizedBox(height: 8),
          if (angle != null && vmg != null) ...[
            Text(
              '${angle!.toStringAsFixed(0)}°',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            Text(
              'VMG ${vmg!.toStringAsFixed(2)} kn',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ] else
            const Text('—', style: TextStyle(fontSize: 22, color: Colors.grey)),
        ],
      ),
    );
  }
}

class _PolarTableCard extends StatelessWidget {
  final PolarData polar;
  final double tws;

  const _PolarTableCard({required this.polar, required this.tws});

  @override
  Widget build(BuildContext context) {
    // Find nearest TWS column
    int twsIdx = 0;
    double minDiff = double.infinity;
    for (int i = 0; i < polar.twsValues.length; i++) {
      final d = (polar.twsValues[i] - tws).abs();
      if (d < minDiff) {
        minDiff = d;
        twsIdx = i;
      }
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Polar column @ ${polar.twsValues[twsIdx].toStringAsFixed(0)} kn',
              style: const TextStyle(
                  fontWeight: FontWeight.w700, fontSize: 14),
            ),
            const SizedBox(height: 10),
            ...List.generate(polar.twaValues.length, (i) {
              final bsp = polar.matrix[i][twsIdx];
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    SizedBox(
                      width: 48,
                      child: Text(
                        '${polar.twaValues[i].toStringAsFixed(0)}°',
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                    ),
                    Expanded(
                      child: LinearProgressIndicator(
                        value: bsp != null
                            ? (bsp /
                                    (polar.matrix
                                            .map((r) => r[twsIdx] ?? 0.0)
                                            .reduce(math.max) +
                                        0.1))
                                .clamp(0, 1)
                                .toDouble()
                            : 0,
                        minHeight: 10,
                        borderRadius: BorderRadius.circular(5),
                        backgroundColor: Colors.grey.withOpacity(0.15),
                      ),
                    ),
                    SizedBox(
                      width: 56,
                      child: Text(
                        bsp != null ? '  ${bsp.toStringAsFixed(2)}kn' : '  —',
                        style: const TextStyle(fontSize: 12),
                        textAlign: TextAlign.right,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _DataCell extends StatelessWidget {
  final String label;
  final String value;
  final String? sub;
  final Color? color;

  const _DataCell({
    required this.label,
    required this.value,
    this.sub,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 11, color: Colors.grey)),
        const SizedBox(height: 2),
        Text(value,
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: color)),
        if (sub != null)
          Text(sub!,
              style: TextStyle(fontSize: 11, color: color ?? Colors.grey)),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Polar chart tab — spider/polar diagram
// ─────────────────────────────────────────────────────────────────────────────

class _PolarChartTab extends StatefulWidget {
  final PolarData polar;

  const _PolarChartTab({required this.polar});

  @override
  State<_PolarChartTab> createState() => _PolarChartTabState();
}

class _PolarChartTabState extends State<_PolarChartTab> {
  int _selectedTwsIdx = 0;

  @override
  Widget build(BuildContext context) {
    final polar = widget.polar;

    return Column(
      children: [
        // TWS selector
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: List.generate(polar.twsValues.length, (i) {
              final selected = i == _selectedTwsIdx;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: Text('${polar.twsValues[i].toStringAsFixed(0)} kn'),
                  selected: selected,
                  onSelected: (_) => setState(() => _selectedTwsIdx = i),
                ),
              );
            }),
          ),
        ),

        // Polar diagram
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: _PolarPainter(
              polar: polar,
              twsIdx: _selectedTwsIdx,
            ),
          ),
        ),
      ],
    );
  }
}

class _PolarPainter extends StatelessWidget {
  final PolarData polar;
  final int twsIdx;

  const _PolarPainter({required this.polar, required this.twsIdx});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _PolarDiagramPainter(
        polar: polar,
        twsIdx: twsIdx,
        color: Theme.of(context).colorScheme.primary,
        gridColor: Theme.of(context).colorScheme.onSurface.withOpacity(0.15),
        textColor: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _PolarDiagramPainter extends CustomPainter {
  final PolarData polar;
  final int twsIdx;
  final Color color;
  final Color gridColor;
  final Color textColor;

  const _PolarDiagramPainter({
    required this.polar,
    required this.twsIdx,
    required this.color,
    required this.gridColor,
    required this.textColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height * 0.55; // centre slightly below middle (upwind top)
    final maxR = math.min(cx, cy) * 0.88;

    // Max BSP for scale
    double maxBsp = 0;
    for (final row in polar.matrix) {
      final v = row[twsIdx];
      if (v != null && v > maxBsp) maxBsp = v;
    }
    if (maxBsp == 0) maxBsp = 1;

    final gridPaint = Paint()
      ..color = gridColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    // Draw concentric speed circles
    const rings = 4;
    final textStyle = TextStyle(color: textColor, fontSize: 10);
    for (int i = 1; i <= rings; i++) {
      final r = maxR * i / rings;
      canvas.drawCircle(Offset(cx, cy), r, gridPaint);

      // Label
      final speed = (maxBsp * i / rings).toStringAsFixed(1);
      final tp = TextPainter(
        text: TextSpan(text: '$speed kn', style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(cx + 4, cy - r - tp.height));
    }

    // Draw angle spokes (every 30°)
    for (int deg = 0; deg < 360; deg += 30) {
      final rad = (deg - 90) * math.pi / 180;
      final x2 = cx + maxR * math.cos(rad);
      final y2 = cy + maxR * math.sin(rad);
      canvas.drawLine(Offset(cx, cy), Offset(x2, y2), gridPaint);
    }

    // Label key angles
    const labelAngles = [0, 30, 60, 90, 120, 150, 180];
    for (final deg in labelAngles) {
      final rad = (deg - 90) * math.pi / 180;
      final lx = cx + (maxR + 16) * math.cos(rad);
      final ly = cy + (maxR + 16) * math.sin(rad);
      final tp = TextPainter(
        text: TextSpan(text: '$deg°', style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(lx - tp.width / 2, ly - tp.height / 2));
    }

    // Draw polar curve — both port and starboard
    final polarPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    Path buildHalfPath(bool starboard) {
      final path = Path();
      bool first = true;
      for (int i = 0; i < polar.twaValues.length; i++) {
        final bsp = polar.matrix[i][twsIdx];
        if (bsp == null || bsp <= 0) continue;
        final angleDeg = starboard ? polar.twaValues[i] : -polar.twaValues[i];
        final rad = (angleDeg - 90) * math.pi / 180;
        final r = maxR * bsp / maxBsp;
        final px = cx + r * math.cos(rad);
        final py = cy + r * math.sin(rad);
        if (first) {
          path.moveTo(px, py);
          first = false;
        } else {
          path.lineTo(px, py);
        }
      }
      return path;
    }

    canvas.drawPath(buildHalfPath(true), polarPaint);
    canvas.drawPath(buildHalfPath(false), polarPaint);

    // Centre dot
    canvas.drawCircle(
      Offset(cx, cy),
      4,
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_PolarDiagramPainter old) =>
      old.twsIdx != twsIdx || old.polar != polar;
}
