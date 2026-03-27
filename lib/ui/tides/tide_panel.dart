import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/tide_prediction.dart';
import '../../data/providers/tide_provider.dart';

class TidePanel extends ConsumerWidget {
  final String stationId;
  final String stationName;

  const TidePanel({
    super.key,
    required this.stationId,
    required this.stationName,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final predictions = ref.watch(tidePredictionsProvider(stationId));

    return Scaffold(
      appBar: AppBar(title: Text(stationName)),
      body: predictions.when(
        data: (preds) => _TidePanelBody(predictions: preds),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }
}

class _TidePanelBody extends StatelessWidget {
  final List<TidePrediction> predictions;

  const _TidePanelBody({required this.predictions});

  @override
  Widget build(BuildContext context) {
    if (predictions.isEmpty) {
      return const Center(child: Text('No predictions available'));
    }

    final now = DateTime.now().toUtc();

    // Find next event.
    TidePrediction? nextEvent;
    Duration? timeToNext;
    for (final p in predictions) {
      if (p.time.isAfter(now)) {
        nextEvent = p;
        timeToNext = p.time.difference(now);
        break;
      }
    }

    return Column(
      children: [
        // Tide curve.
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: CustomPaint(
              size: Size.infinite,
              painter: _TideCurvePainter(
                predictions: predictions,
                now: now,
              ),
            ),
          ),
        ),
        // Next hi/lo info.
        if (nextEvent != null)
          Container(
            padding: const EdgeInsets.all(16),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _InfoTile(
                  label: 'Next ${nextEvent.type == TideType.high ? 'HIGH' : 'LOW'}',
                  value: '${nextEvent.heightM.toStringAsFixed(2)} m',
                ),
                _InfoTile(
                  label: 'In',
                  value: _formatDuration(timeToNext!),
                ),
                _InfoTile(
                  label: 'At',
                  value: _formatTime(nextEvent.time.toLocal()),
                ),
              ],
            ),
          ),
        // Hi/Lo table.
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: predictions.length,
            itemBuilder: (context, i) {
              final p = predictions[i];
              final isPast = p.time.isBefore(now);
              return ListTile(
                leading: Icon(
                  p.type == TideType.high
                      ? Icons.arrow_upward
                      : Icons.arrow_downward,
                  color: p.type == TideType.high
                      ? Colors.blue
                      : Colors.orange,
                ),
                title: Text(
                  '${p.type == TideType.high ? 'High' : 'Low'}: '
                  '${p.heightM.toStringAsFixed(2)} m',
                  style: TextStyle(
                    color: isPast
                        ? Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.color
                            ?.withValues(alpha: 0.5)
                        : null,
                  ),
                ),
                subtitle: Text(
                  _formatDateTime(p.time.toLocal()),
                  style: TextStyle(
                    color: isPast
                        ? Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.color
                            ?.withValues(alpha: 0.5)
                        : null,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  String _formatDuration(Duration d) {
    if (d.inHours > 0) {
      return '${d.inHours}h ${d.inMinutes.remainder(60)}m';
    }
    return '${d.inMinutes}m';
  }

  String _formatTime(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  String _formatDateTime(DateTime t) =>
      '${t.day}/${t.month} ${_formatTime(t)}';
}

class _InfoTile extends StatelessWidget {
  final String label;
  final String value;

  const _InfoTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: 4),
        Text(value,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold)),
      ],
    );
  }
}

class _TideCurvePainter extends CustomPainter {
  final List<TidePrediction> predictions;
  final DateTime now;

  _TideCurvePainter({required this.predictions, required this.now});

  @override
  void paint(Canvas canvas, Size size) {
    if (predictions.length < 2) return;

    final firstTime = predictions.first.time;
    final lastTime = predictions.last.time;
    final totalSeconds = lastTime.difference(firstTime).inSeconds.toDouble();
    if (totalSeconds <= 0) return;

    double minH = double.infinity;
    double maxH = -double.infinity;
    for (final p in predictions) {
      if (p.heightM < minH) minH = p.heightM;
      if (p.heightM > maxH) maxH = p.heightM;
    }
    final hRange = maxH - minH;
    if (hRange <= 0) return;

    final margin = 20.0;
    final plotW = size.width - margin * 2;
    final plotH = size.height - margin * 2;

    double timeToX(DateTime t) {
      final s = t.difference(firstTime).inSeconds.toDouble();
      return margin + (s / totalSeconds) * plotW;
    }

    double heightToY(double h) {
      return margin + plotH - ((h - minH) / hRange) * plotH;
    }

    // Draw grid.
    final gridPaint = Paint()
      ..color = const Color(0x33888888)
      ..strokeWidth = 0.5;
    for (int i = 0; i <= 4; i++) {
      final y = margin + plotH * i / 4;
      canvas.drawLine(Offset(margin, y), Offset(size.width - margin, y), gridPaint);
    }

    // Build sinusoidal curve by interpolating between hi/lo points.
    final curvePaint = Paint()
      ..color = const Color(0xFF2196F3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    final path = Path();
    const steps = 200;
    for (int i = 0; i <= steps; i++) {
      final t = firstTime.add(Duration(
        seconds: (totalSeconds * i / steps).round(),
      ));

      // Find bracketing predictions.
      TidePrediction? prev;
      TidePrediction? next;
      for (final p in predictions) {
        if (p.time.isBefore(t) || p.time.isAtSameMomentAs(t)) {
          prev = p;
        } else {
          next = p;
          break;
        }
      }

      double h;
      if (prev == null) {
        h = predictions.first.heightM;
      } else if (next == null) {
        h = prev.heightM;
      } else {
        final segDur = next.time.difference(prev.time).inSeconds.toDouble();
        final elapsed = t.difference(prev.time).inSeconds.toDouble();
        final frac = elapsed / segDur;
        final cosT = (1 - cos(frac * pi)) / 2;
        h = prev.heightM + (next.heightM - prev.heightM) * cosT;
      }

      final x = timeToX(t);
      final y = heightToY(h);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, curvePaint);

    // Draw hi/lo markers.
    for (final p in predictions) {
      final x = timeToX(p.time);
      final y = heightToY(p.heightM);
      final dotPaint = Paint()
        ..color = p.type == TideType.high
            ? const Color(0xFF2196F3)
            : const Color(0xFFFF9800)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(x, y), 5, dotPaint);
    }

    // Current time marker.
    if (now.isAfter(firstTime) && now.isBefore(lastTime)) {
      final nx = timeToX(now);
      final nowPaint = Paint()
        ..color = const Color(0xFFE53935)
        ..strokeWidth = 2;
      canvas.drawLine(
        Offset(nx, margin),
        Offset(nx, size.height - margin),
        nowPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_TideCurvePainter old) => true;
}
