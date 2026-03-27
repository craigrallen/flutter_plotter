import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/weather_forecast.dart';
import '../../data/providers/weather_provider.dart';

class WeatherScreen extends ConsumerWidget {
  const WeatherScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final grid = ref.watch(weatherGridProvider);
    final overlay = ref.watch(weatherOverlayProvider);
    final timeIdx = ref.watch(weatherTimeIndexProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Weather')),
      body: grid.when(
        data: (forecasts) {
          if (forecasts.isEmpty) {
            return const Center(child: Text('No position available'));
          }

          // Use center point forecast (index 4 in 3x3 grid).
          final center = forecasts.length > 4 ? forecasts[4] : forecasts.first;
          final maxIdx = center.hourly.length - 1;

          return Column(
            children: [
              // Overlay toggle buttons.
              Padding(
                padding: const EdgeInsets.all(12),
                child: SegmentedButton<WeatherOverlay>(
                  segments: const [
                    ButtonSegment(
                      value: WeatherOverlay.off,
                      label: Text('Off'),
                      icon: Icon(Icons.visibility_off),
                    ),
                    ButtonSegment(
                      value: WeatherOverlay.wind,
                      label: Text('Wind'),
                      icon: Icon(Icons.air),
                    ),
                    ButtonSegment(
                      value: WeatherOverlay.waves,
                      label: Text('Waves'),
                      icon: Icon(Icons.waves),
                    ),
                  ],
                  selected: {overlay},
                  onSelectionChanged: (s) {
                    ref.read(weatherOverlayProvider.notifier).state = s.first;
                  },
                ),
              ),

              // Time slider.
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Text(_formatHour(center, timeIdx),
                        style: Theme.of(context).textTheme.labelLarge),
                    Expanded(
                      child: Slider(
                        value: timeIdx.toDouble(),
                        min: 0,
                        max: maxIdx.toDouble(),
                        divisions: maxIdx > 0 ? maxIdx : 1,
                        onChanged: (v) {
                          ref.read(weatherTimeIndexProvider.notifier).state =
                              v.round();
                        },
                      ),
                    ),
                    Text('+${timeIdx}h',
                        style: Theme.of(context).textTheme.labelMedium),
                  ],
                ),
              ),

              const Divider(),

              // 48h forecast chart.
              Expanded(
                child: _ForecastChart(forecast: center),
              ),

              // Current conditions summary.
              if (timeIdx < center.hourly.length)
                _ConditionsSummary(point: center.hourly[timeIdx]),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }

  String _formatHour(WeatherForecast fc, int idx) {
    if (idx >= fc.hourly.length) return '--';
    final t = fc.hourly[idx].time.toLocal();
    return '${t.day}/${t.month} ${t.hour.toString().padLeft(2, '0')}:00';
  }
}

class _ConditionsSummary extends StatelessWidget {
  final WeatherPoint point;

  const _ConditionsSummary({required this.point});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _item(context, 'Wind', '${point.windSpeedKn.toStringAsFixed(0)} kn'),
          _item(context, 'Dir', '${point.windDirectionDeg.toStringAsFixed(0)}°'),
          _item(context, 'Rain', '${point.precipitationMm.toStringAsFixed(1)} mm'),
          if (point.waveHeightM != null)
            _item(context, 'Waves', '${point.waveHeightM!.toStringAsFixed(1)} m'),
        ],
      ),
    );
  }

  Widget _item(BuildContext context, String label, String value) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: 2),
        Text(value,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold)),
      ],
    );
  }
}

class _ForecastChart extends StatelessWidget {
  final WeatherForecast forecast;

  const _ForecastChart({required this.forecast});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: CustomPaint(
        size: Size.infinite,
        painter: _ForecastPainter(
          points: forecast.hourly,
          isDark: Theme.of(context).brightness == Brightness.dark,
        ),
      ),
    );
  }
}

class _ForecastPainter extends CustomPainter {
  final List<WeatherPoint> points;
  final bool isDark;

  _ForecastPainter({required this.points, required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;

    final margin = 40.0;
    final plotW = size.width - margin * 2;
    final plotH = size.height - margin;

    // Find max wind speed.
    double maxWind = 0;
    for (final p in points) {
      if (p.windSpeedKn > maxWind) maxWind = p.windSpeedKn;
    }
    maxWind = max(maxWind, 10); // Minimum scale 10kn.

    final textColor = isDark ? const Color(0xFFCCCCCC) : const Color(0xFF333333);

    // Y-axis labels.
    final labelStyle = TextStyle(color: textColor, fontSize: 10);
    for (int i = 0; i <= 4; i++) {
      final y = margin / 2 + plotH - (plotH * i / 4);
      final val = (maxWind * i / 4).round();
      _drawText(canvas, '$val kn', Offset(2, y - 6), labelStyle);

      final gridPaint = Paint()
        ..color = textColor.withValues(alpha: 0.2)
        ..strokeWidth = 0.5;
      canvas.drawLine(
        Offset(margin, y),
        Offset(size.width - margin, y),
        gridPaint,
      );
    }

    // Wind speed line.
    final windPaint = Paint()
      ..color = const Color(0xFF2196F3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final windPath = Path();
    for (int i = 0; i < points.length; i++) {
      final x = margin + (plotW * i / (points.length - 1));
      final y = margin / 2 + plotH - (plotH * points[i].windSpeedKn / maxWind);
      if (i == 0) {
        windPath.moveTo(x, y);
      } else {
        windPath.lineTo(x, y);
      }
    }
    canvas.drawPath(windPath, windPaint);

    // Wave height line (if available), on same scale normalised.
    final hasWaves = points.any((p) => p.waveHeightM != null && p.waveHeightM! > 0);
    if (hasWaves) {
      double maxWave = 0;
      for (final p in points) {
        if (p.waveHeightM != null && p.waveHeightM! > maxWave) {
          maxWave = p.waveHeightM!;
        }
      }
      maxWave = max(maxWave, 1);

      final wavePaint = Paint()
        ..color = const Color(0xFF4CAF50)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;

      final wavePath = Path();
      bool started = false;
      for (int i = 0; i < points.length; i++) {
        final h = points[i].waveHeightM ?? 0;
        final x = margin + (plotW * i / (points.length - 1));
        final y = margin / 2 + plotH - (plotH * h / (maxWave * 2));
        if (!started) {
          wavePath.moveTo(x, y);
          started = true;
        } else {
          wavePath.lineTo(x, y);
        }
      }
      canvas.drawPath(wavePath, wavePaint);
    }

    // X-axis time labels (every 6h).
    for (int i = 0; i < points.length; i += 6) {
      final x = margin + (plotW * i / (points.length - 1));
      final t = points[i].time.toLocal();
      final label = '${t.hour.toString().padLeft(2, '0')}:00';
      _drawText(canvas, label, Offset(x - 14, size.height - 14), labelStyle);
    }

    // Legend.
    final legendY = 4.0;
    final windLegend = Paint()
      ..color = const Color(0xFF2196F3)
      ..strokeWidth = 2;
    canvas.drawLine(Offset(margin, legendY + 6), Offset(margin + 20, legendY + 6), windLegend);
    _drawText(canvas, 'Wind', Offset(margin + 24, legendY), labelStyle);

    if (hasWaves) {
      final waveLegend = Paint()
        ..color = const Color(0xFF4CAF50)
        ..strokeWidth = 2;
      canvas.drawLine(Offset(margin + 70, legendY + 6), Offset(margin + 90, legendY + 6), waveLegend);
      _drawText(canvas, 'Waves', Offset(margin + 94, legendY), labelStyle);
    }
  }

  void _drawText(Canvas canvas, String text, Offset offset, TextStyle style) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(_ForecastPainter old) => true;
}
