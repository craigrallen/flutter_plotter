import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../../data/providers/signalk_provider.dart';
import '../../core/signalk/signalk_models.dart';
import '../../core/signalk/signalk_source.dart';
import '../../data/models/signalk_state.dart';
import '../../data/providers/data_source_provider.dart';

// ── Models ────────────────────────────────────────────────────────────────────

class _Advice {
  final String message;
  final double impact; // 0-1
  final IconData icon;
  const _Advice({required this.message, required this.impact, required this.icon});
}

class _ScorePoint {
  final DateTime time;
  final double score;
  const _ScorePoint(this.time, this.score);
}

// ── Providers ─────────────────────────────────────────────────────────────────

final _scoreHistoryProvider =
    StateNotifierProvider<_ScoreHistoryNotifier, List<_ScorePoint>>(
        (_) => _ScoreHistoryNotifier());

class _ScoreHistoryNotifier extends StateNotifier<List<_ScorePoint>> {
  static const _maxPoints = 60;
  _ScoreHistoryNotifier() : super([]);

  void add(double score) {
    final now = DateTime.now();
    final cutoff = now.subtract(const Duration(minutes: 10));
    final updated = [...state.where((p) => p.time.isAfter(cutoff)), _ScorePoint(now, score)];
    state = updated.length > _maxPoints ? updated.sublist(updated.length - _maxPoints) : updated;
  }
}

// Heel angle provider — fetches attitude.roll from Signal K REST API
final _heelProvider = StateNotifierProvider<_HeelNotifier, double?>(
    (ref) => _HeelNotifier(ref));

class _HeelNotifier extends StateNotifier<double?> {
  final Ref _ref;
  Timer? _timer;

  _HeelNotifier(this._ref) : super(null) {
    _start();
  }

  void _start() {
    _fetch();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _fetch());
  }

  Future<void> _fetch() async {
    try {
      final ds = _ref.read(dataSourceProvider);
      final host = ds.host;
      final port = ds.port;
      if (host.isEmpty) return;
      final uri = Uri.parse('http://$host:$port/signalk/v1/api/vessels/self/navigation/attitude/roll');
      final resp = await http.get(uri).timeout(const Duration(seconds: 2));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final val = data['value'];
        if (val != null) {
          // Signal K roll is in radians
          state = (val as num).toDouble() * 180 / pi;
        }
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

// ── Scoring ───────────────────────────────────────────────────────────────────

class _TrimScores {
  final double overall;
  final double upwind;
  final double downwind;
  final double heelScore;
  final double vmgEfficiency;
  final List<_Advice> topAdvice;

  const _TrimScores({
    required this.overall,
    required this.upwind,
    required this.downwind,
    required this.heelScore,
    required this.vmgEfficiency,
    required this.topAdvice,
  });
}

_TrimScores _computeScores({
  double? heelDeg,
  double? twaDeg,
  double? twsKn,
  double? awaDeg,
  double? bsp,
}) {
  final advice = <_Advice>[];

  double heelScore = 80;
  if (heelDeg != null) {
    final absHeel = heelDeg.abs();
    if (twaDeg != null && twaDeg < 90) {
      if (absHeel >= 12 && absHeel <= 20) {
        heelScore = 100;
      } else if (absHeel > 25) {
        heelScore = max(0, 100 - (absHeel - 20) * 5).toDouble();
      } else {
        heelScore = 85;
      }
    } else {
      heelScore = max(0, 100 - absHeel * 2).toDouble();
    }
  }

  double vmgEfficiency = 80;
  if (bsp != null && twaDeg != null && bsp > 0) {
    final twaRad = twaDeg * pi / 180;
    final vmg = bsp * cos(twaRad).abs();
    final polarVmg = bsp * 0.85 * cos(twaRad).abs();
    vmgEfficiency = polarVmg > 0 ? (vmg / polarVmg * 100).clamp(0.0, 100.0) : 80;
  }

  final upwind = twaDeg != null && twaDeg < 90
      ? (heelScore * 0.4 + vmgEfficiency * 0.6).clamp(0.0, 100.0)
      : 80.0;

  final downwind = twaDeg != null && twaDeg >= 90
      ? vmgEfficiency.clamp(0.0, 100.0)
      : 80.0;

  if (heelDeg != null && heelDeg.abs() > 20 && twaDeg != null && twaDeg < 60) {
    advice.add(const _Advice(
      message: 'Consider reefing — excessive heel',
      impact: 0.9,
      icon: Icons.warning_amber,
    ));
  }
  if (awaDeg != null && awaDeg < 30) {
    advice.add(const _Advice(
      message: "Too close to wind — you're in the no-sail zone",
      impact: 0.95,
      icon: Icons.block,
    ));
  }
  if (awaDeg != null && awaDeg > 150 && twaDeg != null && twaDeg > 150) {
    advice.add(const _Advice(
      message: 'Consider gybing for better VMG',
      impact: 0.6,
      icon: Icons.swap_horiz,
    ));
  }
  if (vmgEfficiency < 80 && twaDeg != null && twaDeg < 90) {
    advice.add(const _Advice(
      message: 'VMG below target — bear away 5° or ease sheets',
      impact: 0.75,
      icon: Icons.turn_slight_right,
    ));
  }
  if (heelDeg != null && heelDeg.abs() < 5 && twsKn != null && twsKn >= 10) {
    advice.add(const _Advice(
      message: "More sail — you're under-canvased",
      impact: 0.65,
      icon: Icons.add_circle_outline,
    ));
  }

  if (advice.isEmpty) {
    advice.add(const _Advice(
      message: 'Trim looks good — maintain current settings',
      impact: 0.0,
      icon: Icons.check_circle_outline,
    ));
  }

  advice.sort((a, b) => b.impact.compareTo(a.impact));

  final overall = ((heelScore + upwind + downwind + vmgEfficiency) / 4).clamp(0.0, 100.0);

  return _TrimScores(
    overall: overall,
    upwind: upwind,
    downwind: downwind,
    heelScore: heelScore,
    vmgEfficiency: vmgEfficiency,
    topAdvice: advice.take(3).toList(),
  );
}

Color _scoreColor(double score) {
  if (score >= 80) return Colors.green;
  if (score >= 60) return Colors.orange;
  return Colors.red;
}

String _scoreGrade(double score) {
  if (score >= 90) return 'A';
  if (score >= 80) return 'B';
  if (score >= 70) return 'C';
  if (score >= 60) return 'D';
  return 'F';
}

// ── Screen ────────────────────────────────────────────────────────────────────

class TrimAssistantScreen extends ConsumerStatefulWidget {
  const TrimAssistantScreen({super.key});

  @override
  ConsumerState<TrimAssistantScreen> createState() => _TrimAssistantScreenState();
}

class _TrimAssistantScreenState extends ConsumerState<TrimAssistantScreen> {
  @override
  Widget build(BuildContext context) {
    final sk = ref.watch(signalKProvider);
    final env = sk.ownVessel.environment;
    final nav = sk.ownVessel.navigation;
    final heelDeg = ref.watch(_heelProvider);

    final twaDeg = env.windAngleTrueWater;
    final twsKn = env.windSpeedTrue;
    final awaDeg = env.windAngleApparent;
    final bsp = nav.sog; // use SOG as proxy for BSP when no BSP sensor

    final scores = _computeScores(
      heelDeg: heelDeg,
      twaDeg: twaDeg,
      twsKn: twsKn,
      awaDeg: awaDeg,
      bsp: bsp,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(_scoreHistoryProvider.notifier).add(scores.overall);
    });

    final history = ref.watch(_scoreHistoryProvider);
    final connected = sk.connectionState == SignalKConnectionState.connected;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Trim Assistant'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Chip(
              label: Text(connected ? 'Live' : 'No Signal K'),
              backgroundColor: connected
                  ? Colors.green.withValues(alpha: 0.2)
                  : Theme.of(context).colorScheme.errorContainer,
              labelStyle: TextStyle(
                color: connected
                    ? Colors.green
                    : Theme.of(context).colorScheme.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _OverallScoreCard(scores: scores),
            const SizedBox(height: 12),
            _InstrumentRow(
              heel: heelDeg,
              twa: twaDeg,
              tws: twsKn,
              awa: awaDeg,
              bsp: bsp,
            ),
            const SizedBox(height: 12),
            _ScoreBreakdownCard(scores: scores),
            const SizedBox(height: 12),
            _AdvicePanel(advice: scores.topAdvice),
            if (history.length > 1) ...[
              const SizedBox(height: 12),
              _TrimHistoryChart(history: history),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Widgets ───────────────────────────────────────────────────────────────────

class _OverallScoreCard extends StatelessWidget {
  final _TrimScores scores;
  const _OverallScoreCard({super.key, required this.scores});

  @override
  Widget build(BuildContext context) {
    final color = _scoreColor(scores.overall);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Column(
              children: [
                Text(
                  scores.overall.toStringAsFixed(0),
                  style: Theme.of(context)
                      .textTheme
                      .displayLarge
                      ?.copyWith(color: color, fontWeight: FontWeight.bold),
                ),
                Text('Overall Trim Score',
                    style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(width: 32),
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
                  _scoreGrade(scores.overall),
                  style: Theme.of(context)
                      .textTheme
                      .headlineMedium
                      ?.copyWith(color: color, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InstrumentRow extends StatelessWidget {
  final double? heel;
  final double? twa;
  final double? tws;
  final double? awa;
  final double? bsp;

  const _InstrumentRow({
    required this.heel,
    required this.twa,
    required this.tws,
    required this.awa,
    required this.bsp,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _InstrumentChip(
          label: 'Heel',
          value: heel != null ? '${heel!.toStringAsFixed(1)}°' : '--',
          icon: Icons.rotate_90_degrees_ccw,
        ),
        _InstrumentChip(
          label: 'TWA',
          value: twa != null ? '${twa!.toStringAsFixed(0)}°' : '--',
          icon: Icons.air,
        ),
        _InstrumentChip(
          label: 'TWS',
          value: tws != null ? '${tws!.toStringAsFixed(1)} kn' : '--',
          icon: Icons.wind_power,
        ),
        _InstrumentChip(
          label: 'AWA',
          value: awa != null ? '${awa!.toStringAsFixed(0)}°' : '--',
          icon: Icons.compass_calibration,
        ),
        _InstrumentChip(
          label: 'BSP',
          value: bsp != null ? '${bsp!.toStringAsFixed(1)} kn' : '--',
          icon: Icons.speed,
        ),
      ],
    );
  }
}

class _InstrumentChip extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  const _InstrumentChip(
      {required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          children: [
            Icon(icon, size: 18),
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

class _ScoreBreakdownCard extends StatelessWidget {
  final _TrimScores scores;
  const _ScoreBreakdownCard({super.key, required this.scores});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Score Breakdown',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            _ScoreRow(label: 'Upwind Trim', score: scores.upwind),
            _ScoreRow(label: 'Downwind Trim', score: scores.downwind),
            _ScoreRow(label: 'Heel Angle', score: scores.heelScore),
            _ScoreRow(label: 'VMG Efficiency', score: scores.vmgEfficiency),
          ],
        ),
      ),
    );
  }
}

class _ScoreRow extends StatelessWidget {
  final String label;
  final double score;
  const _ScoreRow({required this.label, required this.score});

  @override
  Widget build(BuildContext context) {
    final color = _scoreColor(score);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: Text(label)),
              Text(
                '${score.toStringAsFixed(0)}%',
                style: TextStyle(color: color, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 4),
          LinearProgressIndicator(
            value: score / 100,
            color: color,
            backgroundColor: color.withValues(alpha: 0.15),
            minHeight: 8,
          ),
        ],
      ),
    );
  }
}

class _AdvicePanel extends StatelessWidget {
  final List<_Advice> advice;
  const _AdvicePanel({super.key, required this.advice});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Top Suggestions',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            for (int i = 0; i < advice.length; i++) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    advice[i].icon,
                    size: 20,
                    color: advice[i].impact > 0.8
                        ? Colors.red
                        : advice[i].impact > 0.5
                            ? Colors.orange
                            : Colors.green,
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(advice[i].message)),
                ],
              ),
              if (i < advice.length - 1) const Divider(height: 16),
            ],
          ],
        ),
      ),
    );
  }
}

class _TrimHistoryChart extends StatelessWidget {
  final List<_ScorePoint> history;
  const _TrimHistoryChart({super.key, required this.history});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Trim Score — Last 10 min',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SizedBox(
              height: 120,
              child: CustomPaint(
                painter: _LineChartPainter(
                  points: history,
                  lineColor: Theme.of(context).colorScheme.primary,
                  gridColor: Theme.of(context).dividerColor,
                ),
                child: const SizedBox.expand(),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('10 min ago', style: Theme.of(context).textTheme.labelSmall),
                Text('Now', style: Theme.of(context).textTheme.labelSmall),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LineChartPainter extends CustomPainter {
  final List<_ScorePoint> points;
  final Color lineColor;
  final Color gridColor;

  const _LineChartPainter({
    required this.points,
    required this.lineColor,
    required this.gridColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;

    final gridPaint = Paint()
      ..color = gridColor.withValues(alpha: 0.5)
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

    final fillPaint = Paint()
      ..color = lineColor.withValues(alpha: 0.1)
      ..style = PaintingStyle.fill;

    final earliest = points.first.time.millisecondsSinceEpoch.toDouble();
    final latest = points.last.time.millisecondsSinceEpoch.toDouble();
    final timeRange = latest - earliest;
    if (timeRange == 0) return;

    Offset toOffset(_ScorePoint p) {
      final x = (p.time.millisecondsSinceEpoch - earliest) / timeRange * size.width;
      final y = size.height - (p.score / 100) * size.height;
      return Offset(x, y);
    }

    final path = Path();
    final fill = Path();
    final first = toOffset(points.first);
    path.moveTo(first.dx, first.dy);
    fill.moveTo(first.dx, size.height);
    fill.lineTo(first.dx, first.dy);

    for (int i = 1; i < points.length; i++) {
      final o = toOffset(points[i]);
      path.lineTo(o.dx, o.dy);
      fill.lineTo(o.dx, o.dy);
    }

    final lastOffset = toOffset(points.last);
    fill.lineTo(lastOffset.dx, size.height);
    fill.close();

    canvas.drawPath(fill, fillPaint);
    canvas.drawPath(path, linePaint);
  }

  @override
  bool shouldRepaint(_LineChartPainter old) => old.points != points;
}
