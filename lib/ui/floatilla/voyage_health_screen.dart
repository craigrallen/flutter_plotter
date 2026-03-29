import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/floatilla/voyage_logger_service.dart';
import '../../data/providers/voyage_logger_provider.dart';

// ── Analysis models ───────────────────────────────────────────────────────────

class _MetricScore {
  final String label;
  final double score; // 0-100
  final String value; // display value
  final String advice;
  final IconData icon;

  const _MetricScore({
    required this.label,
    required this.score,
    required this.value,
    required this.advice,
    required this.icon,
  });
}

class _VoyageHealth {
  final double overall; // 0-100
  final String grade; // A-F
  final List<_MetricScore> metrics;
  final int tackCount;
  final int gybeCount;
  final int windShiftsTotal;
  final int windShiftsResponded;

  const _VoyageHealth({
    required this.overall,
    required this.grade,
    required this.metrics,
    required this.tackCount,
    required this.gybeCount,
    required this.windShiftsTotal,
    required this.windShiftsResponded,
  });
}

// ── Analysis functions ────────────────────────────────────────────────────────

String _grade(double score) {
  if (score >= 90) return 'A';
  if (score >= 80) return 'B';
  if (score >= 70) return 'C';
  if (score >= 60) return 'D';
  return 'F';
}

Color _scoreColor(double score) {
  if (score >= 80) return Colors.green;
  if (score >= 60) return Colors.orange;
  return Colors.red;
}

double _stdDev(List<double> values) {
  if (values.isEmpty) return 0;
  final mean = values.reduce((a, b) => a + b) / values.length;
  final variance =
      values.map((v) => pow(v - mean, 2)).reduce((a, b) => a + b) / values.length;
  return sqrt(variance);
}

double _haversineNm(double lat1, double lon1, double lat2, double lon2) {
  const R = 3440.065; // nm
  final dLat = (lat2 - lat1) * pi / 180;
  final dLon = (lon2 - lon1) * pi / 180;
  final a = sin(dLat / 2) * sin(dLat / 2) +
      cos(lat1 * pi / 180) *
          cos(lat2 * pi / 180) *
          sin(dLon / 2) *
          sin(dLon / 2);
  return R * 2 * atan2(sqrt(a), sqrt(1 - a));
}

_VoyageHealth _analyzeVoyage(
    VoyageRecord voyage, List<VoyageLogEntry> entries) {
  if (entries.isEmpty) {
    return const _VoyageHealth(
      overall: 0,
      grade: 'N/A',
      metrics: [],
      tackCount: 0,
      gybeCount: 0,
      windShiftsTotal: 0,
      windShiftsResponded: 0,
    );
  }

  final metrics = <_MetricScore>[];

  // ── VMG Efficiency ────────────────────────────────────────────────────────
  double vmgScore = 70;
  String vmgValue = 'N/A';
  {
    final withWind = entries.where((e) => e.sog != null && e.twd != null && e.cog != null).toList();
    if (withWind.isNotEmpty) {
      double totalVmg = 0;
      double totalPolarVmg = 0;
      for (final e in withWind) {
        final twa = ((e.cog! - e.twd!).abs() % 360);
        final twaDeg = twa > 180 ? 360 - twa : twa;
        final twaRad = twaDeg * pi / 180;
        final vmg = e.sog! * cos(twaRad).abs();
        final polarVmg = e.sog! * 0.85 * cos(twaRad).abs();
        totalVmg += vmg;
        totalPolarVmg += polarVmg;
      }
      if (totalPolarVmg > 0) {
        final eff = (totalVmg / totalPolarVmg * 100).clamp(0.0, 100.0);
        vmgScore = eff.toDouble();
        vmgValue = '${eff.toStringAsFixed(0)}%';
      }
    }
    metrics.add(_MetricScore(
      label: 'VMG Efficiency',
      score: vmgScore,
      value: vmgValue,
      advice: vmgScore >= 80
          ? 'Good VMG — well-trimmed upwind sailing'
          : 'VMG below polar target. Review pointing angle and sail trim.',
      icon: Icons.arrow_upward,
    ));
  }

  // ── Tack Count ────────────────────────────────────────────────────────────
  int tackCount = 0;
  int gybeCount = 0;
  {
    final withCog = entries.where((e) => e.cog != null).toList();
    for (int i = 0; i < withCog.length - 1; i++) {
      final curr = withCog[i];
      final next = withCog[i + 1];
      final dt = next.timestamp.difference(curr.timestamp).inSeconds;
      if (dt > 120) continue; // ignore large gaps
      double delta = (next.cog! - curr.cog!).abs() % 360;
      if (delta > 180) delta = 360 - delta;
      if (delta > 60) {
        // Determine upwind vs downwind by TWA if available
        final twaMid = curr.twd != null
            ? ((curr.cog! - curr.twd!).abs() % 360)
            : 90.0;
        final twaNorm = twaMid > 180 ? 360 - twaMid : twaMid;
        if (twaNorm < 90) {
          tackCount++;
        } else {
          gybeCount++;
        }
      }
    }

    // Score: too many tacks = bad, too few could also be (stuck in header)
    // Roughly: 0-5 tacks = good, 6-15 = ok, >15 = bad
    final tackScore = tackCount <= 5
        ? 95.0
        : tackCount <= 15
            ? max(0.0, 95.0 - (tackCount - 5) * 3.0)
            : max(0.0, 65.0 - (tackCount - 15) * 2.0);
    metrics.add(_MetricScore(
      label: 'Tack Count',
      score: tackScore,
      value: '$tackCount tacks',
      advice: tackCount > 15
          ? 'High tack count — consider longer laylines or less conservative routing'
          : 'Tack count looks reasonable',
      icon: Icons.compare_arrows,
    ));
  }

  // ── Wind Shift Response ───────────────────────────────────────────────────
  int windShiftsTotal = 0;
  int windShiftsResponded = 0;
  double windShiftScore = 75;
  {
    final withWind = entries.where((e) => e.twd != null).toList();
    final lookback = const Duration(minutes: 10);
    for (int i = 5; i < withWind.length; i++) {
      final curr = withWind[i];
      final prev = withWind[i - 1];
      // Wind direction change
      double dWind = (curr.twd! - prev.twd!).abs() % 360;
      if (dWind > 180) dWind = 360 - dWind;
      if (dWind < 15) continue;

      // Accumulate shift over 10 min window
      final tenprev = withWind
          .where((e) => e.timestamp.isAfter(
                curr.timestamp.subtract(lookback),
              ) && e.timestamp.isBefore(curr.timestamp))
          .toList();
      if (tenprev.isEmpty) continue;
      double totalShift = (curr.twd! - tenprev.first.twd!).abs() % 360;
      if (totalShift > 180) totalShift = 360 - totalShift;
      if (totalShift < 15) continue;

      windShiftsTotal++;

      // Check if boat changed COG within 5 min after shift
      final after = entries
          .where((e) =>
              e.timestamp.isAfter(curr.timestamp) &&
              e.timestamp
                  .isBefore(curr.timestamp.add(const Duration(minutes: 5))) &&
              e.cog != null)
          .toList();
      if (after.length >= 2) {
        double cogChange = (after.last.cog! - after.first.cog!).abs() % 360;
        if (cogChange > 180) cogChange = 360 - cogChange;
        if (cogChange > 10) windShiftsResponded++;
      }
    }

    if (windShiftsTotal > 0) {
      final rate = windShiftsResponded / windShiftsTotal;
      windShiftScore = (rate * 100).clamp(0.0, 100.0);
    }

    metrics.add(_MetricScore(
      label: 'Wind Shift Response',
      score: windShiftScore,
      value: windShiftsTotal > 0
          ? '$windShiftsResponded / $windShiftsTotal responded'
          : 'No major shifts',
      advice: windShiftsTotal > 0 && windShiftsResponded < windShiftsTotal
          ? 'Missed some wind shifts — watch for headers and lifts'
          : 'Good wind shift awareness',
      icon: Icons.rotate_right,
    ));
  }

  // ── Speed Consistency ─────────────────────────────────────────────────────
  {
    final sogs = entries.where((e) => e.sog != null).map((e) => e.sog!).toList();
    double consistencyScore = 80;
    String consistencyValue = 'N/A';
    if (sogs.isNotEmpty) {
      final stdDevVal = _stdDev(sogs);
      // Low stddev = consistent. Target < 1 kn = excellent, < 2 = ok, > 3 = poor
      consistencyScore = stdDevVal < 1.0
          ? 100.0
          : stdDevVal < 2.0
              ? max(0.0, 100.0 - (stdDevVal - 1.0) * 20)
              : max(0.0, 80.0 - (stdDevVal - 2.0) * 20);
      consistencyValue = stdDevVal.toStringAsFixed(1) + ' kn σ';
    }
    metrics.add(_MetricScore(
      label: 'Speed Consistency',
      score: consistencyScore,
      value: consistencyValue,
      advice: consistencyScore >= 80
          ? 'Good speed consistency throughout passage'
          : 'High speed variation — check for lulls, squalls, or tactical losses',
      icon: Icons.show_chart,
    ));
  }

  // ── Fuel Efficiency ───────────────────────────────────────────────────────
  {
    final motorEntries = entries.where((e) => e.engineRpm != null && e.engineRpm! > 100).toList();
    if (motorEntries.length >= 2) {
      // Estimate distance under engine
      double distNm = 0;
      for (int i = 1; i < motorEntries.length; i++) {
        final a = motorEntries[i - 1];
        final b = motorEntries[i];
        if (a.lat != null && a.lng != null && b.lat != null && b.lng != null) {
          distNm += _haversineNm(a.lat!, a.lng!, b.lat!, b.lng!);
        }
      }
      // Engine hours
      final engineSeconds = motorEntries.last.timestamp
          .difference(motorEntries.first.timestamp)
          .inSeconds;
      final engineHours = engineSeconds / 3600.0;
      // Assume ~4 L/h at cruising RPM as rough estimate
      const fuelRateLh = 4.0;
      final fuelUsed = engineHours * fuelRateLh;
      final lPerNm = distNm > 0 ? fuelUsed / distNm : 0.0;

      // Score: < 1 L/nm = great, 1-2 = ok, > 3 = poor
      final fuelScore = lPerNm < 1
          ? 100.0
          : lPerNm < 2
              ? max(0.0, 100.0 - (lPerNm - 1) * 30)
              : max(0.0, 70.0 - (lPerNm - 2) * 20);
      metrics.add(_MetricScore(
        label: 'Fuel Efficiency',
        score: fuelScore,
        value: '${lPerNm.toStringAsFixed(1)} L/nm',
        advice: fuelScore >= 80
            ? 'Efficient motoring'
            : 'Consider optimising RPM for better fuel economy',
        icon: Icons.local_gas_station,
      ));
    }
  }

  // ── Max Performance ───────────────────────────────────────────────────────
  {
    final sogValues =
        entries.where((e) => e.sog != null).map((e) => e.sog!).toList();
    if (sogValues.isNotEmpty) {
      sogValues.sort();
      final top20Threshold =
          sogValues[(sogValues.length * 0.8).floor().clamp(0, sogValues.length - 1)];
      final topEntries =
          entries.where((e) => e.sog != null && e.sog! >= top20Threshold).toList();
      final totalEntries = entries.length;
      final topPct = totalEntries > 0 ? topEntries.length / totalEntries * 100 : 0.0;

      metrics.add(_MetricScore(
        label: 'Max Performance',
        score: topPct.toDouble().clamp(0.0, 100.0),
        value: '${topPct.toStringAsFixed(0)}% in top tier',
        advice: topPct >= 20
            ? 'Good time in high-performance window'
            : 'Try to sustain peak performance longer',
        icon: Icons.rocket_launch,
      ));
    }
  }

  // ── Overall ───────────────────────────────────────────────────────────────
  final overall = metrics.isEmpty
      ? 0.0
      : metrics.map((m) => m.score).reduce((a, b) => a + b) / metrics.length;

  return _VoyageHealth(
    overall: overall,
    grade: _grade(overall),
    metrics: metrics,
    tackCount: tackCount,
    gybeCount: gybeCount,
    windShiftsTotal: windShiftsTotal,
    windShiftsResponded: windShiftsResponded,
  );
}

// ── Providers ─────────────────────────────────────────────────────────────────

final _selectedVoyageProvider = StateProvider<VoyageRecord?>((_) => null);
final _healthProvider =
    StateNotifierProvider<_HealthNotifier, AsyncValue<_VoyageHealth>>(
        (_) => _HealthNotifier());

class _HealthNotifier
    extends StateNotifier<AsyncValue<_VoyageHealth>> {
  _HealthNotifier() : super(const AsyncValue.data(_VoyageHealth(
    overall: 0,
    grade: 'N/A',
    metrics: [],
    tackCount: 0,
    gybeCount: 0,
    windShiftsTotal: 0,
    windShiftsResponded: 0,
  )));

  Future<void> analyze(VoyageRecord voyage) async {
    state = const AsyncValue.loading();
    try {
      final entries =
          await VoyageLoggerService.instance.loadEntriesForVoyage(voyage.voyageId);
      final health = _analyzeVoyage(voyage, entries);
      state = AsyncValue.data(health);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}

// ── Screen ────────────────────────────────────────────────────────────────────

class VoyageHealthScreen extends ConsumerWidget {
  const VoyageHealthScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loggerState = ref.watch(voyageLoggerProvider);
    final selected = ref.watch(_selectedVoyageProvider);
    final healthAsync = ref.watch(_healthProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Voyage Health Score'),
        actions: [
          if (selected != null)
            IconButton(
              icon: const Icon(Icons.share),
              tooltip: 'Share summary',
              onPressed: () => _share(context, selected, healthAsync),
            ),
        ],
      ),
      body: Column(
        children: [
          // Voyage selector
          _VoyageSelector(
            voyages: loggerState.pastVoyages,
            selected: selected,
            onSelected: (voyage) {
              ref.read(_selectedVoyageProvider.notifier).state = voyage;
              ref.read(_healthProvider.notifier).analyze(voyage);
            },
          ),

          // Content
          Expanded(
            child: selected == null
                ? const Center(
                    child: Text('Select a past voyage to analyse'),
                  )
                : healthAsync.when(
                    loading: () => const Center(
                        child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('Analysing voyage data...'),
                      ],
                    )),
                    error: (e, _) => Center(child: Text('Error: $e')),
                    data: (health) => _HealthBody(
                      health: health,
                      voyage: selected,
                      pastVoyages: loggerState.pastVoyages,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  void _share(
      BuildContext context,
      VoyageRecord voyage,
      AsyncValue<_VoyageHealth> healthAsync) {
    healthAsync.whenData((health) {
      final fmt = DateFormat('dd MMM yyyy HH:mm');
      final buf = StringBuffer();
      buf.writeln('Voyage Health Score — ${fmt.format(voyage.startTime)}');
      buf.writeln('Overall: ${health.overall.toStringAsFixed(0)} / 100 (${health.grade})');
      buf.writeln();
      for (final m in health.metrics) {
        buf.writeln('${m.label}: ${m.value} (${m.score.toStringAsFixed(0)}/100)');
      }
      buf.writeln();
      buf.writeln('Tacks: ${health.tackCount}  Gybes: ${health.gybeCount}');
      buf.writeln(
          'Wind shifts: ${health.windShiftsResponded}/${health.windShiftsTotal} responded');
      Share.share(buf.toString(), subject: 'Voyage Health Score');
    });
  }
}

// ── Voyage selector ───────────────────────────────────────────────────────────

class _VoyageSelector extends StatelessWidget {
  final List<VoyageRecord> voyages;
  final VoyageRecord? selected;
  final ValueChanged<VoyageRecord> onSelected;

  const _VoyageSelector({
    required this.voyages,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd MMM yyyy');
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.directions_boat, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButton<VoyageRecord>(
              value: selected,
              isExpanded: true,
              underline: const SizedBox(),
              hint: const Text('Select a voyage'),
              items: voyages
                  .where((v) => v.endTime != null)
                  .map((v) => DropdownMenuItem(
                        value: v,
                        child: Text(
                          '${fmt.format(v.startTime)} — ${fmt.format(v.endTime!)}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ))
                  .toList(),
              onChanged: (v) {
                if (v != null) onSelected(v);
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── Health body ───────────────────────────────────────────────────────────────

class _HealthBody extends ConsumerWidget {
  final _VoyageHealth health;
  final VoyageRecord voyage;
  final List<VoyageRecord> pastVoyages;

  const _HealthBody({
    required this.health,
    required this.voyage,
    required this.pastVoyages,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // Overall score card
        _OverallCard(health: health, voyage: voyage),
        const SizedBox(height: 12),

        // Quick stats row
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _StatChip(
              icon: Icons.compare_arrows,
              label: 'Tacks',
              value: '${health.tackCount}',
            ),
            _StatChip(
              icon: Icons.swap_horiz,
              label: 'Gybes',
              value: '${health.gybeCount}',
            ),
            _StatChip(
              icon: Icons.rotate_right,
              label: 'Shift Response',
              value: health.windShiftsTotal > 0
                  ? '${health.windShiftsResponded}/${health.windShiftsTotal}'
                  : 'N/A',
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Metric breakdown cards
        for (final m in health.metrics) ...[
          _MetricCard(metric: m),
          const SizedBox(height: 8),
        ],

        // Trend chart comparing past voyages
        if (pastVoyages.length > 1) ...[
          const SizedBox(height: 4),
          _TrendSection(
            currentVoyageId: voyage.voyageId,
            pastVoyages: pastVoyages,
          ),
        ],
      ],
    );
  }
}

// ── Overall score card ────────────────────────────────────────────────────────

class _OverallCard extends StatelessWidget {
  final _VoyageHealth health;
  final VoyageRecord voyage;

  const _OverallCard({required this.health, required this.voyage});

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd MMM yyyy HH:mm');
    final color = _scoreColor(health.overall);
    final dur = voyage.endTime != null
        ? voyage.endTime!.difference(voyage.startTime)
        : null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Column(
                  children: [
                    Text(
                      health.overall.toStringAsFixed(0),
                      style: Theme.of(context)
                          .textTheme
                          .displayLarge
                          ?.copyWith(color: color, fontWeight: FontWeight.bold),
                    ),
                    Text('Voyage Health',
                        style: Theme.of(context).textTheme.titleMedium),
                  ],
                ),
                const SizedBox(width: 24),
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color.withValues(alpha: 0.15),
                    border: Border.all(color: color, width: 3),
                  ),
                  child: Center(
                    child: Text(
                      health.grade,
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            color: color,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              fmt.format(voyage.startTime),
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Colors.grey),
            ),
            if (dur != null)
              Text(
                'Duration: ${_formatDuration(dur)}',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Colors.grey),
              ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    return h > 0 ? '${h}h ${m}m' : '${m}m';
  }
}

// ── Metric card ───────────────────────────────────────────────────────────────

class _MetricCard extends StatelessWidget {
  final _MetricScore metric;
  const _MetricCard({required this.metric});

  @override
  Widget build(BuildContext context) {
    final color = _scoreColor(metric.score);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(metric.icon, size: 20, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(metric.label,
                      style: Theme.of(context).textTheme.titleSmall),
                ),
                Text(
                  metric.value,
                  style: TextStyle(fontWeight: FontWeight.bold, color: color),
                ),
                const SizedBox(width: 8),
                Text(
                  '${metric.score.toStringAsFixed(0)}/100',
                  style: TextStyle(color: color),
                ),
              ],
            ),
            const SizedBox(height: 6),
            LinearProgressIndicator(
              value: metric.score / 100,
              color: color,
              backgroundColor: color.withValues(alpha: 0.15),
              minHeight: 6,
            ),
            const SizedBox(height: 6),
            Text(metric.advice,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}

// ── Stat chip ─────────────────────────────────────────────────────────────────

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _StatChip({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          children: [
            Icon(icon, size: 20),
            const SizedBox(height: 2),
            Text(label, style: Theme.of(context).textTheme.labelSmall),
            Text(value,
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}

// ── Trend chart ───────────────────────────────────────────────────────────────

class _TrendSection extends ConsumerStatefulWidget {
  final String currentVoyageId;
  final List<VoyageRecord> pastVoyages;

  const _TrendSection({
    required this.currentVoyageId,
    required this.pastVoyages,
  });

  @override
  ConsumerState<_TrendSection> createState() => _TrendSectionState();
}

class _TrendSectionState extends ConsumerState<_TrendSection> {
  List<_TrendPoint> _trendData = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadTrend();
  }

  Future<void> _loadTrend() async {
    setState(() => _loading = true);
    final completed = widget.pastVoyages
        .where((v) => v.endTime != null)
        .toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));

    final last5 = completed.length > 5
        ? completed.sublist(completed.length - 5)
        : completed;

    final points = <_TrendPoint>[];
    for (final v in last5) {
      final entries = await VoyageLoggerService.instance
          .loadEntriesForVoyage(v.voyageId);
      final health = _analyzeVoyage(v, entries);
      points.add(_TrendPoint(
        date: v.startTime,
        score: health.overall,
        isCurrent: v.voyageId == widget.currentVoyageId,
      ));
    }

    if (mounted) setState(() {
      _trendData = points;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Score Trend — Last Voyages',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (_loading)
              const LinearProgressIndicator()
            else if (_trendData.length < 2)
              const Text('Not enough voyages for trend',
                  style: TextStyle(color: Colors.grey))
            else
              SizedBox(
                height: 120,
                child: CustomPaint(
                  painter: _TrendChartPainter(
                    points: _trendData,
                    lineColor: Theme.of(context).colorScheme.primary,
                    gridColor: Theme.of(context).dividerColor,
                    currentColor: Theme.of(context).colorScheme.secondary,
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TrendPoint {
  final DateTime date;
  final double score;
  final bool isCurrent;
  const _TrendPoint({
    required this.date,
    required this.score,
    required this.isCurrent,
  });
}

class _TrendChartPainter extends CustomPainter {
  final List<_TrendPoint> points;
  final Color lineColor;
  final Color gridColor;
  final Color currentColor;

  const _TrendChartPainter({
    required this.points,
    required this.lineColor,
    required this.gridColor,
    required this.currentColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;

    final gridPaint = Paint()
      ..color = gridColor.withValues(alpha: 0.4)
      ..strokeWidth = 0.5;

    for (final v in [25.0, 50.0, 75.0, 100.0]) {
      final y = size.height - (v / 100) * size.height;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final n = points.length;

    Offset toOffset(int i) {
      final x = n > 1 ? i / (n - 1) * size.width : size.width / 2;
      final y = size.height - (points[i].score / 100) * size.height;
      return Offset(x, y);
    }

    final path = Path();
    path.moveTo(toOffset(0).dx, toOffset(0).dy);
    for (int i = 1; i < n; i++) {
      path.lineTo(toOffset(i).dx, toOffset(i).dy);
    }
    canvas.drawPath(path, linePaint);

    // Draw dots
    for (int i = 0; i < n; i++) {
      final o = toOffset(i);
      final dotPaint = Paint()
        ..color = points[i].isCurrent ? currentColor : lineColor
        ..style = PaintingStyle.fill;
      canvas.drawCircle(o, points[i].isCurrent ? 6 : 4, dotPaint);

      // Score label
      final tp = TextPainter(
        text: TextSpan(
          text: points[i].score.toStringAsFixed(0),
          style: TextStyle(
            fontSize: 9,
            color: points[i].isCurrent ? currentColor : lineColor,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: ui.TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(o.dx - tp.width / 2, o.dy - 18));
    }
  }

  @override
  bool shouldRepaint(_TrendChartPainter old) => old.points != points;
}
