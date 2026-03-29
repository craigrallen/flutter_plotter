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

class _LatLng {
  const _LatLng(this.lat, this.lng);
  final double lat;
  final double lng;
}

enum _SailScore { excellent, good, marginal, poor }

class _HourlyRow {
  const _HourlyRow({
    required this.time,
    required this.windSpeed,
    required this.windDir,
    required this.windGust,
    required this.waveHeight,
  });
  final DateTime time;
  final double windSpeed;
  final double windDir;
  final double windGust;
  final double waveHeight;
}

class _DayForecast {
  const _DayForecast({
    required this.date,
    required this.maxWind,
    required this.minWind,
    required this.dominantDir,
    required this.maxWave,
    required this.hourly,
    required this.weatherCode,
  });
  final DateTime date;
  final double maxWind;
  final double minWind;
  final double dominantDir;
  final double maxWave;
  final List<_HourlyRow> hourly;
  final int weatherCode;

  _SailScore get score {
    int s = 0;
    if (maxWind < 15) {
      s += 3;
    } else if (maxWind < 25) {
      s += 1;
    } else {
      s -= 2;
    }
    if (maxWave < 1.0) {
      s += 3;
    } else if (maxWave < 2.0) {
      s += 1;
    } else {
      s -= 2;
    }
    if (s >= 5) return _SailScore.excellent;
    if (s >= 3) return _SailScore.good;
    if (s >= 1) return _SailScore.marginal;
    return _SailScore.poor;
  }
}

// ---------------------------------------------------------------------------
// API helpers
// ---------------------------------------------------------------------------

Future<_LatLng?> _geocode(String query) async {
  final lat = double.tryParse(query.split(',').first.trim());
  final lng = double.tryParse(query.split(',').last.trim());
  if (lat != null && lng != null && query.contains(',')) {
    return _LatLng(lat, lng);
  }
  final uri = Uri.parse(
    'https://geocoding-api.open-meteo.com/v1/search?name=${Uri.encodeComponent(query)}&count=1&format=json',
  );
  final res = await http.get(uri).timeout(const Duration(seconds: 10));
  if (res.statusCode != 200) return null;
  final data = jsonDecode(res.body) as Map<String, dynamic>;
  final results = data['results'] as List<dynamic>?;
  if (results == null || results.isEmpty) return null;
  final r = results.first as Map<String, dynamic>;
  return _LatLng(
      (r['latitude'] as num).toDouble(), (r['longitude'] as num).toDouble());
}

Future<List<_DayForecast>> _fetchForecast(_LatLng pos) async {
  // Fetch wind forecast
  final windUri = Uri.parse(
    'https://api.open-meteo.com/v1/forecast'
    '?latitude=${pos.lat}&longitude=${pos.lng}'
    '&hourly=wind_speed_10m,wind_direction_10m,wind_gusts_10m,weathercode'
    '&wind_speed_unit=kn'
    '&forecast_days=7',
  );
  // Fetch marine forecast
  final marineUri = Uri.parse(
    'https://marine-api.open-meteo.com/v1/marine'
    '?latitude=${pos.lat}&longitude=${pos.lng}'
    '&hourly=wave_height'
    '&forecast_days=7',
  );

  final results = await Future.wait([
    http.get(windUri).timeout(const Duration(seconds: 15)),
    http.get(marineUri).timeout(const Duration(seconds: 15)),
  ]);

  if (results[0].statusCode != 200) {
    throw Exception('Wind API error ${results[0].statusCode}');
  }

  final windData = jsonDecode(results[0].body) as Map<String, dynamic>;
  final windHourly = windData['hourly'] as Map<String, dynamic>;
  final times = (windHourly['time'] as List).cast<String>();
  final speeds = (windHourly['wind_speed_10m'] as List)
      .map((e) => (e as num?)?.toDouble() ?? 0.0)
      .toList();
  final dirs = (windHourly['wind_direction_10m'] as List)
      .map((e) => (e as num?)?.toDouble() ?? 0.0)
      .toList();
  final gusts = (windHourly['wind_gusts_10m'] as List)
      .map((e) => (e as num?)?.toDouble() ?? 0.0)
      .toList();
  final codes = (windHourly['weathercode'] as List)
      .map((e) => (e as num?)?.toInt() ?? 0)
      .toList();

  Map<DateTime, double> waveMap = {};
  if (results[1].statusCode == 200) {
    final marineData = jsonDecode(results[1].body) as Map<String, dynamic>;
    final marineHourly = marineData['hourly'] as Map<String, dynamic>;
    final marineTimes = (marineHourly['time'] as List).cast<String>();
    final waveHeights = (marineHourly['wave_height'] as List)
        .map((e) => (e as num?)?.toDouble() ?? 0.0)
        .toList();
    for (var i = 0; i < marineTimes.length; i++) {
      waveMap[DateTime.parse(marineTimes[i])] = waveHeights[i];
    }
  }

  // Group by day
  final Map<String, List<int>> dayGroups = {};
  for (var i = 0; i < times.length; i++) {
    final dayKey = times[i].substring(0, 10);
    dayGroups.putIfAbsent(dayKey, () => []).add(i);
  }

  final days = <_DayForecast>[];
  for (final entry in dayGroups.entries) {
    final indices = entry.value;
    final hourly = indices.map((i) {
      final t = DateTime.parse(times[i]);
      return _HourlyRow(
        time: t,
        windSpeed: speeds[i],
        windDir: dirs[i],
        windGust: gusts[i],
        waveHeight: waveMap[t] ?? 0.0,
      );
    }).toList();

    final maxWind = hourly.map((h) => h.windSpeed).reduce(math.max);
    final minWind = hourly.map((h) => h.windSpeed).reduce(math.min);
    final maxWave = hourly.map((h) => h.waveHeight).reduce(math.max);

    // Dominant direction: average by circular mean
    double sinSum = 0, cosSum = 0;
    for (final h in hourly) {
      final rad = h.windDir * math.pi / 180.0;
      sinSum += math.sin(rad);
      cosSum += math.cos(rad);
    }
    final dominantDir =
        (math.atan2(sinSum, cosSum) * 180.0 / math.pi + 360) % 360;

    // Representative weather code (most common)
    final Map<int, int> codeCounts = {};
    for (final i in indices) {
      codeCounts[codes[i]] = (codeCounts[codes[i]] ?? 0) + 1;
    }
    final dominantCode =
        codeCounts.entries.reduce((a, b) => a.value > b.value ? a : b).key;

    days.add(_DayForecast(
      date: DateTime.parse(entry.key),
      maxWind: maxWind,
      minWind: minWind,
      dominantDir: dominantDir,
      maxWave: maxWave,
      hourly: hourly,
      weatherCode: dominantCode,
    ));
  }

  return days;
}

// ---------------------------------------------------------------------------
// Score helpers
// ---------------------------------------------------------------------------

Color _scoreColor(_SailScore s) {
  switch (s) {
    case _SailScore.excellent:
      return Colors.green;
    case _SailScore.good:
      return Colors.lightGreen;
    case _SailScore.marginal:
      return Colors.orange;
    case _SailScore.poor:
      return Colors.red;
  }
}

String _scoreLabel(_SailScore s) {
  switch (s) {
    case _SailScore.excellent:
      return 'Excellent';
    case _SailScore.good:
      return 'Good';
    case _SailScore.marginal:
      return 'Marginal';
    case _SailScore.poor:
      return 'Poor';
  }
}

IconData _weatherIcon(int code) {
  if (code == 0 || code == 1) return Icons.wb_sunny;
  if (code <= 3) return Icons.cloud;
  if (code >= 95) return Icons.thunderstorm;
  if (code >= 51) return Icons.grain;
  return Icons.air;
}

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class DailyBriefingScreen extends ConsumerStatefulWidget {
  const DailyBriefingScreen({super.key});

  @override
  ConsumerState<DailyBriefingScreen> createState() =>
      _DailyBriefingScreenState();
}

class _DailyBriefingScreenState extends ConsumerState<DailyBriefingScreen> {
  final _locationCtrl = TextEditingController();
  bool _loading = false;
  String? _error;
  List<_DayForecast>? _days;
  String? _locationLabel;
  final Set<int> _expanded = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadCurrentLocation());
  }

  Future<void> _loadCurrentLocation() async {
    final vessel = ref.read(vesselProvider);
    final pos = vessel.position;
    if (pos != null) {
      _locationCtrl.text =
          '${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)}';
      _locationLabel = 'Current location';
      await _fetch();
    }
  }

  Future<void> _fetch() async {
    final query = _locationCtrl.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _loading = true;
      _error = null;
      _days = null;
      _expanded.clear();
    });

    try {
      final pos = await _geocode(query);
      if (pos == null) throw Exception('Could not geocode: $query');
      final days = await _fetchForecast(pos);
      setState(() {
        _days = days;
        _loading = false;
        _locationLabel ??= query;
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
    _locationCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Daily Briefing'),
        actions: [
          if (_days != null)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _fetch,
            ),
        ],
      ),
      body: Column(
        children: [
          _LocationBar(
            controller: _locationCtrl,
            onSearch: _fetch,
          ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
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
    if (_days == null) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wb_cloudy, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('Enter a location to see the 7-day briefing'),
          ],
        ),
      );
    }

    // Find best day
    final bestIdx = _days!.indexWhere((d) =>
        d.score ==
        _days!.map((d) => d.score).reduce((a, b) {
          final order = [
            _SailScore.excellent,
            _SailScore.good,
            _SailScore.marginal,
            _SailScore.poor
          ];
          return order.indexOf(a) <= order.indexOf(b) ? a : b;
        }));

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      itemCount: _days!.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return _BestDayBanner(day: _days![bestIdx]);
        }
        final dayIdx = index - 1;
        final day = _days![dayIdx];
        return _DayCard(
          day: day,
          isBest: dayIdx == bestIdx,
          isExpanded: _expanded.contains(dayIdx),
          onToggle: () {
            setState(() {
              if (_expanded.contains(dayIdx)) {
                _expanded.remove(dayIdx);
              } else {
                _expanded.add(dayIdx);
              }
            });
          },
          onTapChart: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => _HourlyChartScreen(day: day),
              ),
            );
          },
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Location bar
// ---------------------------------------------------------------------------

class _LocationBar extends StatelessWidget {
  const _LocationBar({required this.controller, required this.onSearch});
  final TextEditingController controller;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              decoration: InputDecoration(
                hintText: 'Location or lat, lng',
                prefixIcon: const Icon(Icons.place),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                isDense: true,
              ),
              onSubmitted: (_) => onSearch(),
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: onSearch,
            icon: const Icon(Icons.search),
            label: const Text('Search'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Best day banner
// ---------------------------------------------------------------------------

class _BestDayBanner extends StatelessWidget {
  const _BestDayBanner({required this.day});
  final _DayForecast day;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      color: Colors.green.shade900,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.star, color: Colors.amber, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Best day this week',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: Colors.green.shade200,
                        ),
                  ),
                  Text(
                    DateFormat('EEEE, MMM d').format(day.date),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  Text(
                    '${day.minWind.round()}-${day.maxWind.round()} kn  |  waves ${day.maxWave.toStringAsFixed(1)} m',
                    style: TextStyle(color: Colors.green.shade100),
                  ),
                ],
              ),
            ),
            Chip(
              label: Text(
                _scoreLabel(day.score),
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold),
              ),
              backgroundColor: _scoreColor(day.score),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Day card
// ---------------------------------------------------------------------------

class _DayCard extends StatelessWidget {
  const _DayCard({
    required this.day,
    required this.isBest,
    required this.isExpanded,
    required this.onToggle,
    required this.onTapChart,
  });

  final _DayForecast day;
  final bool isBest;
  final bool isExpanded;
  final VoidCallback onToggle;
  final VoidCallback onTapChart;

  @override
  Widget build(BuildContext context) {
    final scoreColor = _scoreColor(day.score);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isBest
            ? BorderSide(color: Colors.green.shade400, width: 2)
            : BorderSide.none,
      ),
      child: Column(
        children: [
          ListTile(
            leading: Icon(_weatherIcon(day.weatherCode), size: 32),
            title: Text(
              DateFormat('EEEE, MMM d').format(day.date),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Row(
              children: [
                _WindDirIcon(dir: day.dominantDir),
                const SizedBox(width: 4),
                Text(
                    '${day.minWind.round()}-${day.maxWind.round()} kn  |  ${day.maxWave.toStringAsFixed(1)} m'),
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: scoreColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: scoreColor),
                  ),
                  child: Text(
                    _scoreLabel(day.score),
                    style: TextStyle(
                      color: scoreColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  isExpanded ? Icons.expand_less : Icons.expand_more,
                ),
              ],
            ),
            onTap: onToggle,
          ),
          if (isExpanded) ...[
            const Divider(height: 1),
            _HourlyTable(rows: day.hourly),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: onTapChart,
                  icon: const Icon(Icons.show_chart),
                  label: const Text('Hourly chart'),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Wind direction icon
// ---------------------------------------------------------------------------

class _WindDirIcon extends StatelessWidget {
  const _WindDirIcon({required this.dir});
  final double dir;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: dir * math.pi / 180.0,
      child: const Icon(Icons.navigation, size: 16),
    );
  }
}

// ---------------------------------------------------------------------------
// Hourly table
// ---------------------------------------------------------------------------

class _HourlyTable extends StatelessWidget {
  const _HourlyTable({required this.rows});
  final List<_HourlyRow> rows;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: DataTable(
        headingRowHeight: 32,
        dataRowMinHeight: 28,
        dataRowMaxHeight: 36,
        columnSpacing: 16,
        columns: const [
          DataColumn(label: Text('Time')),
          DataColumn(label: Text('Wind'), numeric: true),
          DataColumn(label: Text('Dir')),
          DataColumn(label: Text('Gust'), numeric: true),
          DataColumn(label: Text('Wave'), numeric: true),
        ],
        rows: rows.map((r) {
          return DataRow(cells: [
            DataCell(Text(DateFormat('HH:mm').format(r.time))),
            DataCell(Text('${r.windSpeed.round()} kn')),
            DataCell(Row(children: [
              _WindDirIcon(dir: r.windDir),
              const SizedBox(width: 2),
              Text('${r.windDir.round()}°'),
            ])),
            DataCell(Text('${r.windGust.round()} kn')),
            DataCell(Text('${r.waveHeight.toStringAsFixed(1)} m')),
          ]);
        }).toList(),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Hourly chart screen
// ---------------------------------------------------------------------------

class _HourlyChartScreen extends StatelessWidget {
  const _HourlyChartScreen({required this.day});
  final _DayForecast day;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(DateFormat('EEEE, MMM d').format(day.date)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Wind speed & wave height',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Container(width: 16, height: 3, color: Colors.blue),
                const SizedBox(width: 4),
                const Text('Wind speed (kn)', style: TextStyle(fontSize: 12)),
                const SizedBox(width: 16),
                Container(width: 16, height: 12,
                    color: Colors.teal.withValues(alpha: 0.4)),
                const SizedBox(width: 4),
                const Text('Wave height (m)', style: TextStyle(fontSize: 12)),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: CustomPaint(
                painter: _HourlyChartPainter(rows: day.hourly),
                size: Size.infinite,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Chart painter
// ---------------------------------------------------------------------------

class _HourlyChartPainter extends CustomPainter {
  _HourlyChartPainter({required this.rows});
  final List<_HourlyRow> rows;

  @override
  void paint(Canvas canvas, Size size) {
    if (rows.isEmpty) return;

    final maxWind = rows.map((r) => r.windSpeed).reduce(math.max);
    final maxWave = rows.map((r) => r.waveHeight).reduce(math.max);
    final n = rows.length;
    const padLeft = 40.0;
    const padBottom = 30.0;
    final chartW = size.width - padLeft;
    final chartH = size.height - padBottom;

    // Draw grid
    final gridPaint = Paint()
      ..color = Colors.grey.withValues(alpha: 0.2)
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final y = padLeft + chartH - chartH * i / 4;
      canvas.drawLine(Offset(padLeft, y), Offset(size.width, y), gridPaint);
    }

    // Wave fill
    final waveFill = Paint()..color = Colors.teal.withValues(alpha: 0.3);
    final wavePath = Path();
    final waveMax = maxWave > 0 ? maxWave : 1.0;
    for (var i = 0; i < n; i++) {
      final x = padLeft + chartW * i / (n - 1);
      final y = padLeft + chartH - chartH * rows[i].waveHeight / waveMax;
      if (i == 0) {
        wavePath.moveTo(x, padLeft + chartH);
        wavePath.lineTo(x, y);
      } else {
        wavePath.lineTo(x, y);
      }
    }
    wavePath.lineTo(padLeft + chartW, padLeft + chartH);
    wavePath.close();
    canvas.drawPath(wavePath, waveFill);

    // Wind line
    final windPaint = Paint()
      ..color = Colors.blue
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;
    final windPath = Path();
    final windMax = maxWind > 0 ? maxWind : 1.0;
    for (var i = 0; i < n; i++) {
      final x = padLeft + chartW * i / (n - 1);
      final y = padLeft + chartH - chartH * rows[i].windSpeed / windMax;
      if (i == 0) {
        windPath.moveTo(x, y);
      } else {
        windPath.lineTo(x, y);
      }
    }
    canvas.drawPath(windPath, windPaint);

    // X-axis labels (every 3 hours)
    final textPainter = TextPainter(textDirection: ui.TextDirection.ltr);
    for (var i = 0; i < n; i += 3) {
      final x = padLeft + chartW * i / (n - 1);
      final label = DateFormat('HH').format(rows[i].time);
      textPainter.text = TextSpan(
        text: label,
        style: const TextStyle(fontSize: 10, color: Colors.grey),
      );
      textPainter.layout();
      textPainter.paint(
          canvas, Offset(x - textPainter.width / 2, size.height - 18));
    }

    // Y-axis labels (wind)
    for (var i = 0; i <= 4; i++) {
      final value = windMax * i / 4;
      final y = padLeft + chartH - chartH * i / 4;
      textPainter.text = TextSpan(
        text: value.round().toString(),
        style: const TextStyle(fontSize: 10, color: Colors.blue),
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(0, y - 6));
    }
  }

  @override
  bool shouldRepaint(covariant _HourlyChartPainter old) =>
      old.rows != rows;
}
