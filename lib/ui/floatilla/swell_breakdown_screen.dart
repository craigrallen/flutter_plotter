import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../../data/providers/vessel_provider.dart';

// ---------------------------------------------------------------------------
// Models
// ---------------------------------------------------------------------------

enum _ComfortRating { gentle, moderate, rough, veryRough, extreme }

class _SwellComponent {
  const _SwellComponent({
    required this.label,
    required this.height,
    required this.direction,
    required this.period,
  });
  final String label;
  final double height;
  final double direction;
  final double period;
}

class _SwellHour {
  const _SwellHour({
    required this.time,
    required this.totalHeight,
    required this.swellHeight,
    required this.windWaveHeight,
    required this.swellDir,
    required this.swellPeriod,
    required this.windWaveDir,
    required this.windWavePeriod,
    required this.waveDir,
    required this.wavePeriod,
  });
  final DateTime time;
  final double totalHeight;
  final double swellHeight;
  final double windWaveHeight;
  final double swellDir;
  final double swellPeriod;
  final double windWaveDir;
  final double windWavePeriod;
  final double waveDir;
  final double wavePeriod;

  _ComfortRating get comfort {
    // Steepness: height/period — rough proxy
    final steepness = wavePeriod > 0 ? totalHeight / wavePeriod : totalHeight;
    if (totalHeight < 0.5) return _ComfortRating.gentle;
    if (totalHeight < 1.5 && steepness < 0.15) return _ComfortRating.moderate;
    if (totalHeight < 2.5 && steepness < 0.25) return _ComfortRating.rough;
    if (totalHeight < 4.0) return _ComfortRating.veryRough;
    return _ComfortRating.extreme;
  }

  List<_SwellComponent> get components {
    final comps = <_SwellComponent>[];
    if (totalHeight > 0) {
      comps.add(_SwellComponent(
        label: 'Combined sea',
        height: totalHeight,
        direction: waveDir,
        period: wavePeriod,
      ));
    }
    if (swellHeight > 0.1) {
      comps.add(_SwellComponent(
        label: 'Primary swell',
        height: swellHeight,
        direction: swellDir,
        period: swellPeriod,
      ));
    }
    if (windWaveHeight > 0.1) {
      comps.add(_SwellComponent(
        label: 'Wind wave',
        height: windWaveHeight,
        direction: windWaveDir,
        period: windWavePeriod,
      ));
    }
    return comps;
  }
}

// ---------------------------------------------------------------------------
// API fetch
// ---------------------------------------------------------------------------

Future<List<_SwellHour>> _fetchSwell(double lat, double lng) async {
  final uri = Uri.parse(
    'https://marine-api.open-meteo.com/v1/marine'
    '?latitude=$lat&longitude=$lng'
    '&hourly=wave_height,wave_direction,wave_period'
    ',swell_wave_height,swell_wave_direction,swell_wave_period'
    ',wind_wave_height,wind_wave_direction,wind_wave_period'
    '&forecast_days=3',
  );
  final res = await http.get(uri).timeout(const Duration(seconds: 15));
  if (res.statusCode != 200) {
    throw Exception('Marine API error ${res.statusCode}');
  }

  final data = jsonDecode(res.body) as Map<String, dynamic>;
  final hourly = data['hourly'] as Map<String, dynamic>;

  double toDouble(dynamic v) => (v as num?)?.toDouble() ?? 0.0;
  List<double> listFor(String key) =>
      (hourly[key] as List).map(toDouble).toList();

  final times = (hourly['time'] as List).cast<String>();
  final waveH = listFor('wave_height');
  final waveD = listFor('wave_direction');
  final waveP = listFor('wave_period');
  final swellH = listFor('swell_wave_height');
  final swellD = listFor('swell_wave_direction');
  final swellP = listFor('swell_wave_period');
  final windWH = listFor('wind_wave_height');
  final windWD = listFor('wind_wave_direction');
  final windWP = listFor('wind_wave_period');

  return List.generate(math.min(times.length, 72), (i) {
    return _SwellHour(
      time: DateTime.parse(times[i]),
      totalHeight: waveH[i],
      swellHeight: swellH[i],
      windWaveHeight: windWH[i],
      swellDir: swellD[i],
      swellPeriod: swellP[i],
      windWaveDir: windWD[i],
      windWavePeriod: windWP[i],
      waveDir: waveD[i],
      wavePeriod: waveP[i],
    );
  });
}

// ---------------------------------------------------------------------------
// Comfort rating helpers
// ---------------------------------------------------------------------------

String _comfortLabel(_ComfortRating r) {
  switch (r) {
    case _ComfortRating.gentle:
      return 'Gentle';
    case _ComfortRating.moderate:
      return 'Moderate';
    case _ComfortRating.rough:
      return 'Rough';
    case _ComfortRating.veryRough:
      return 'Very Rough';
    case _ComfortRating.extreme:
      return 'Extreme';
  }
}

Color _comfortColor(_ComfortRating r) {
  switch (r) {
    case _ComfortRating.gentle:
      return Colors.green;
    case _ComfortRating.moderate:
      return Colors.lightGreen;
    case _ComfortRating.rough:
      return Colors.orange;
    case _ComfortRating.veryRough:
      return Colors.deepOrange;
    case _ComfortRating.extreme:
      return Colors.red;
  }
}

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class SwellBreakdownScreen extends ConsumerStatefulWidget {
  const SwellBreakdownScreen({super.key});

  @override
  ConsumerState<SwellBreakdownScreen> createState() =>
      _SwellBreakdownScreenState();
}

class _SwellBreakdownScreenState extends ConsumerState<SwellBreakdownScreen> {
  final _latCtrl = TextEditingController();
  final _lngCtrl = TextEditingController();
  bool _loading = false;
  String? _error;
  List<_SwellHour>? _data;
  int _selectedHour = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _preloadCurrentLocation());
  }

  void _preloadCurrentLocation() {
    final vessel = ref.read(vesselProvider);
    final pos = vessel.position;
    if (pos != null) {
      _latCtrl.text = pos.latitude.toStringAsFixed(4);
      _lngCtrl.text = pos.longitude.toStringAsFixed(4);
      _fetch();
    }
  }

  Future<void> _fetch() async {
    final lat = double.tryParse(_latCtrl.text.trim());
    final lng = double.tryParse(_lngCtrl.text.trim());
    if (lat == null || lng == null) {
      setState(() => _error = 'Enter valid latitude and longitude');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _data = null;
      _selectedHour = 0;
    });
    try {
      final data = await _fetchSwell(lat, lng);
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _latCtrl.dispose();
    _lngCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Swell Breakdown'),
        actions: [
          if (_data != null)
            IconButton(icon: const Icon(Icons.refresh), onPressed: _fetch),
        ],
      ),
      body: Column(
        children: [
          _LocationInput(
            latCtrl: _latCtrl,
            lngCtrl: _lngCtrl,
            onFetch: _fetch,
          ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: _fetch, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    if (_data == null) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.waves, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('Enter a location to see swell breakdown'),
          ],
        ),
      );
    }

    final current = _data![_selectedHour];

    return Column(
      children: [
        // Time slider
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Column(
            children: [
              Row(
                children: [
                  const Icon(Icons.access_time, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    DateFormat('EEE dd MMM HH:mm')
                        .format(current.time),
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                ],
              ),
              Slider(
                value: _selectedHour.toDouble(),
                min: 0,
                max: (_data!.length - 1).toDouble(),
                divisions: _data!.length - 1,
                onChanged: (v) => setState(() => _selectedHour = v.round()),
              ),
            ],
          ),
        ),
        // Component cards
        Expanded(
          flex: 3,
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              // Comfort badge
              _ComfortBadge(rating: current.comfort),
              const SizedBox(height: 8),
              // Component cards
              for (final comp in current.components)
                _SwellComponentCard(component: comp),
              const SizedBox(height: 8),
            ],
          ),
        ),
        // Stacked bar chart
        Container(
          height: 130,
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('72h swell timeline',
                  style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: 4),
              Expanded(
                child: CustomPaint(
                  painter: _SwellChartPainter(
                    data: _data!,
                    selectedHour: _selectedHour,
                  ),
                  size: Size.infinite,
                ),
              ),
            ],
          ),
        ),
        // Chart legend
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
          child: Row(
            children: [
              _LegendDot(Colors.blue, 'Swell'),
              const SizedBox(width: 12),
              _LegendDot(Colors.teal, 'Wind wave'),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Location input
// ---------------------------------------------------------------------------

class _LocationInput extends StatelessWidget {
  const _LocationInput({
    required this.latCtrl,
    required this.lngCtrl,
    required this.onFetch,
  });
  final TextEditingController latCtrl;
  final TextEditingController lngCtrl;
  final VoidCallback onFetch;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: latCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true, signed: true),
              decoration: InputDecoration(
                labelText: 'Latitude',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                isDense: true,
                contentPadding: const EdgeInsets.all(10),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: lngCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true, signed: true),
              decoration: InputDecoration(
                labelText: 'Longitude',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                isDense: true,
                contentPadding: const EdgeInsets.all(10),
              ),
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: onFetch,
            child: const Text('Fetch'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Comfort badge
// ---------------------------------------------------------------------------

class _ComfortBadge extends StatelessWidget {
  const _ComfortBadge({required this.rating});
  final _ComfortRating rating;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: _comfortColor(rating).withValues(alpha: 0.2),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: _comfortColor(rating)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(Icons.directions_boat, color: _comfortColor(rating)),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Comfort rating',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
                Text(
                  _comfortLabel(rating),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: _comfortColor(rating),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Swell component card
// ---------------------------------------------------------------------------

class _SwellComponentCard extends StatelessWidget {
  const _SwellComponentCard({required this.component});
  final _SwellComponent component;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            // Mini polar direction indicator
            SizedBox(
              width: 48,
              height: 48,
              child: CustomPaint(
                painter: _MiniPolarPainter(direction: component.direction),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    component.label,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      _Chip('${component.height.toStringAsFixed(1)} m'),
                      const SizedBox(width: 6),
                      _Chip('${component.direction.round()}°'),
                      const SizedBox(width: 6),
                      _Chip('${component.period.toStringAsFixed(1)} s'),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label, style: const TextStyle(fontSize: 12)),
    );
  }
}

// ---------------------------------------------------------------------------
// Mini polar painter
// ---------------------------------------------------------------------------

class _MiniPolarPainter extends CustomPainter {
  const _MiniPolarPainter({required this.direction});
  final double direction;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2 - 2;

    final circlePaint = Paint()
      ..color = Colors.grey.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(center, r, circlePaint);

    // Arrow pointing in wind direction
    final rad = direction * math.pi / 180.0 - math.pi / 2;
    final tipX = center.dx + r * 0.8 * math.cos(rad);
    final tipY = center.dy + r * 0.8 * math.sin(rad);
    final arrowPaint = Paint()
      ..color = Colors.blueAccent
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(center, Offset(tipX, tipY), arrowPaint);
    // dot at center
    canvas.drawCircle(
        center, 2.5, Paint()..color = Colors.blueAccent);
  }

  @override
  bool shouldRepaint(covariant _MiniPolarPainter old) =>
      old.direction != direction;
}

// ---------------------------------------------------------------------------
// Swell stacked bar chart painter
// ---------------------------------------------------------------------------

class _SwellChartPainter extends CustomPainter {
  const _SwellChartPainter({
    required this.data,
    required this.selectedHour,
  });
  final List<_SwellHour> data;
  final int selectedHour;

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    const padLeft = 28.0;
    const padBottom = 18.0;
    final chartW = size.width - padLeft;
    final chartH = size.height - padBottom;
    final barW = chartW / data.length;

    // Max height for scale
    final maxH = data.map((d) => d.totalHeight).reduce(math.max);
    if (maxH <= 0) return;

    final swellPaint = Paint()..color = Colors.blue.withValues(alpha: 0.7);
    final windWavePaint = Paint()..color = Colors.teal.withValues(alpha: 0.7);
    final selectedPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.15);

    for (var i = 0; i < data.length; i++) {
      final d = data[i];
      final x = padLeft + barW * i;
      final swellBarH = chartH * d.swellHeight / maxH;
      final windBarH = chartH * d.windWaveHeight / maxH;

      if (i == selectedHour) {
        canvas.drawRect(
          Rect.fromLTWH(x, 0, barW, size.height - padBottom),
          selectedPaint,
        );
      }

      // Swell (bottom)
      canvas.drawRect(
        Rect.fromLTWH(
            x + 1,
            padLeft + chartH - swellBarH,
            barW - 2,
            swellBarH),
        swellPaint,
      );
      // Wind wave (on top)
      canvas.drawRect(
        Rect.fromLTWH(
            x + 1,
            padLeft + chartH - swellBarH - windBarH,
            barW - 2,
            windBarH),
        windWavePaint,
      );
    }

    // Y axis
    final axisPaint = Paint()
      ..color = Colors.grey.withValues(alpha: 0.4)
      ..strokeWidth = 1;
    canvas.drawLine(
        Offset(padLeft, padLeft),
        Offset(padLeft, padLeft + chartH),
        axisPaint);
    canvas.drawLine(
        Offset(padLeft, padLeft + chartH),
        Offset(size.width, padLeft + chartH),
        axisPaint);

    // Labels
    final tp = TextPainter(textDirection: ui.TextDirection.ltr);
    for (var i = 0; i <= 2; i++) {
      final val = maxH * i / 2;
      final y = padLeft + chartH - chartH * i / 2;
      tp.text = TextSpan(
        text: val.toStringAsFixed(1),
        style: const TextStyle(fontSize: 8, color: Colors.grey),
      );
      tp.layout();
      tp.paint(canvas, Offset(0, y - 5));
    }

    // X labels every 6 hours
    for (var i = 0; i < data.length; i += 6) {
      final x = padLeft + barW * i;
      tp.text = TextSpan(
        text: DateFormat('HH').format(data[i].time),
        style: const TextStyle(fontSize: 8, color: Colors.grey),
      );
      tp.layout();
      tp.paint(canvas,
          Offset(x - tp.width / 2, size.height - padBottom + 2));
    }
  }

  @override
  bool shouldRepaint(covariant _SwellChartPainter old) =>
      old.data != data || old.selectedHour != selectedHour;
}

// ---------------------------------------------------------------------------
// Legend dot
// ---------------------------------------------------------------------------

class _LegendDot extends StatelessWidget {
  const _LegendDot(this.color, this.label);
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
            width: 12,
            height: 12,
            decoration:
                BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}
