import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ---------------------------------------------------------------------------
// Models
// ---------------------------------------------------------------------------

class _LatLng {
  const _LatLng(this.lat, this.lng);
  final double lat;
  final double lng;
}

enum _ConditionScore { excellent, good, marginal, poor }

class _HourlyPoint {
  const _HourlyPoint({
    required this.time,
    required this.windSpeed,
    required this.windDir,
    required this.windGust,
    required this.waveHeight,
    required this.waveDir,
  });
  final DateTime time;
  final double windSpeed;
  final double windDir;
  final double windGust;
  final double waveHeight;
  final double waveDir;
}

class _DepartureOption {
  _DepartureOption({required this.departureTime});
  DateTime departureTime;

  // fetched data
  bool loading = false;
  String? error;
  _HourlyPoint? atDeparture;
  _HourlyPoint? atMidpoint;
  _HourlyPoint? atDestination;
  List<_HourlyPoint> passageHourly = [];

  _ConditionScore get score {
    if (atDeparture == null) return _ConditionScore.poor;
    final maxWind = [
      atDeparture!.windSpeed,
      if (atMidpoint != null) atMidpoint!.windSpeed,
      if (atDestination != null) atDestination!.windSpeed,
    ].reduce(math.max);
    final maxWave = [
      atDeparture!.waveHeight,
      if (atMidpoint != null) atMidpoint!.waveHeight,
      if (atDestination != null) atDestination!.waveHeight,
    ].reduce(math.max);

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
    if (s >= 5) return _ConditionScore.excellent;
    if (s >= 3) return _ConditionScore.good;
    if (s >= 1) return _ConditionScore.marginal;
    return _ConditionScore.poor;
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
  return _LatLng((r['latitude'] as num).toDouble(), (r['longitude'] as num).toDouble());
}

Future<Map<DateTime, Map<String, double>>> _fetchMarineData(_LatLng pos) async {
  final uri = Uri.parse(
    'https://marine-api.open-meteo.com/v1/marine'
    '?latitude=${pos.lat}&longitude=${pos.lng}'
    '&hourly=wave_height,wave_direction'
    '&forecast_days=7',
  );
  final res = await http.get(uri).timeout(const Duration(seconds: 15));
  if (res.statusCode != 200) return {};
  final data = jsonDecode(res.body) as Map<String, dynamic>;
  final hourly = data['hourly'] as Map<String, dynamic>;
  final times = (hourly['time'] as List<dynamic>).cast<String>();
  final heights = hourly['wave_height'] as List<dynamic>;
  final dirs = hourly['wave_direction'] as List<dynamic>;
  final result = <DateTime, Map<String, double>>{};
  for (var i = 0; i < times.length; i++) {
    final t = DateTime.parse(times[i]);
    result[t] = {
      'height': (heights[i] as num?)?.toDouble() ?? 0.0,
      'dir': (dirs[i] as num?)?.toDouble() ?? 0.0,
    };
  }
  return result;
}

Future<Map<DateTime, Map<String, double>>> _fetchWindData(_LatLng pos) async {
  final uri = Uri.parse(
    'https://api.open-meteo.com/v1/forecast'
    '?latitude=${pos.lat}&longitude=${pos.lng}'
    '&hourly=wind_speed_10m,wind_direction_10m,wind_gusts_10m'
    '&wind_speed_unit=kn'
    '&forecast_days=7',
  );
  final res = await http.get(uri).timeout(const Duration(seconds: 15));
  if (res.statusCode != 200) return {};
  final data = jsonDecode(res.body) as Map<String, dynamic>;
  final hourly = data['hourly'] as Map<String, dynamic>;
  final times = (hourly['time'] as List<dynamic>).cast<String>();
  final speeds = hourly['wind_speed_10m'] as List<dynamic>;
  final dirs = hourly['wind_direction_10m'] as List<dynamic>;
  final gusts = hourly['wind_gusts_10m'] as List<dynamic>;
  final result = <DateTime, Map<String, double>>{};
  for (var i = 0; i < times.length; i++) {
    final t = DateTime.parse(times[i]);
    result[t] = {
      'speed': (speeds[i] as num?)?.toDouble() ?? 0.0,
      'dir': (dirs[i] as num?)?.toDouble() ?? 0.0,
      'gust': (gusts[i] as num?)?.toDouble() ?? 0.0,
    };
  }
  return result;
}

_HourlyPoint _interpolate(
  DateTime target,
  Map<DateTime, Map<String, double>> wind,
  Map<DateTime, Map<String, double>> wave,
) {
  // Find closest hour
  DateTime nearest = target;
  Duration bestDiff = const Duration(days: 9999);
  for (final k in wind.keys) {
    final diff = (k.difference(target)).abs();
    if (diff < bestDiff) {
      bestDiff = diff;
      nearest = k;
    }
  }
  final w = wind[nearest] ?? {'speed': 0, 'dir': 0, 'gust': 0};
  final wv = wave[nearest] ?? {'height': 0, 'dir': 0};
  return _HourlyPoint(
    time: target,
    windSpeed: w['speed'] ?? 0,
    windDir: w['dir'] ?? 0,
    windGust: w['gust'] ?? 0,
    waveHeight: wv['height'] ?? 0,
    waveDir: wv['dir'] ?? 0,
  );
}

// ---------------------------------------------------------------------------
// Main Screen
// ---------------------------------------------------------------------------

class DeparturePlannerScreen extends StatefulWidget {
  const DeparturePlannerScreen({super.key});

  @override
  State<DeparturePlannerScreen> createState() => _DeparturePlannerScreenState();
}

class _DeparturePlannerScreenState extends State<DeparturePlannerScreen> {
  final _fromCtrl = TextEditingController(text: '57.7,11.9'); // Gothenburg
  final _toCtrl = TextEditingController(text: '55.6,12.6');   // Copenhagen
  final _speedCtrl = TextEditingController(text: '6');
  final _durationCtrl = TextEditingController(text: '24');

  _LatLng? _fromPos;
  _LatLng? _toPos;
  String? _routeError;
  bool _routeLoading = false;

  final _pageCtrl = PageController();
  int _selectedOption = 0;

  late final List<_DepartureOption> _options;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _options = List.generate(4, (i) {
      return _DepartureOption(
        departureTime: DateTime(now.year, now.month, now.day, 6, 0)
            .add(Duration(days: i + 1)),
      );
    });
  }

  @override
  void dispose() {
    _fromCtrl.dispose();
    _toCtrl.dispose();
    _speedCtrl.dispose();
    _durationCtrl.dispose();
    _pageCtrl.dispose();
    super.dispose();
  }

  double get _durationHours => double.tryParse(_durationCtrl.text) ?? 24;
  double get _vesselSpeed => double.tryParse(_speedCtrl.text) ?? 6;

  Future<void> _resolveRoute() async {
    setState(() {
      _routeLoading = true;
      _routeError = null;
    });
    try {
      final from = await _geocode(_fromCtrl.text.trim());
      final to = await _geocode(_toCtrl.text.trim());
      if (from == null || to == null) {
        setState(() {
          _routeError = 'Could not resolve locations';
          _routeLoading = false;
        });
        return;
      }
      setState(() {
        _fromPos = from;
        _toPos = to;
        _routeLoading = false;
      });
      // Auto-fetch all options
      for (var i = 0; i < _options.length; i++) {
        _fetchOption(i);
      }
    } catch (e) {
      setState(() {
        _routeError = e.toString();
        _routeLoading = false;
      });
    }
  }

  Future<void> _fetchOption(int idx) async {
    if (_fromPos == null || _toPos == null) return;
    setState(() {
      _options[idx].loading = true;
      _options[idx].error = null;
    });
    try {
      final dep = _options[idx].departureTime;
      final mid = dep.add(Duration(hours: (_durationHours / 2).round()));
      final dest = dep.add(Duration(hours: _durationHours.round()));
      final midPos = _LatLng(
        (_fromPos!.lat + _toPos!.lat) / 2,
        (_fromPos!.lng + _toPos!.lng) / 2,
      );

      // Fetch wind and wave for from, mid, dest in parallel
      final windFrom = await _fetchWindData(_fromPos!);
      final waveFrom = await _fetchMarineData(_fromPos!);
      final windMid = await _fetchWindData(midPos);
      final waveMid = await _fetchMarineData(midPos);
      final windTo = await _fetchWindData(_toPos!);
      final waveTo = await _fetchMarineData(_toPos!);

      // Build hourly passage data (from departure to destination)
      final hourly = <_HourlyPoint>[];
      for (var h = 0; h <= _durationHours.round(); h++) {
        final t = dep.add(Duration(hours: h));
        // Use from wind/wave for first half, to for second half (simplified)
        final frac = h / _durationHours;
        final windData = frac <= 0.5 ? windFrom : windTo;
        final waveData = frac <= 0.5 ? waveFrom : waveTo;
        hourly.add(_interpolate(t, windData, waveData));
      }

      setState(() {
        _options[idx]
          ..atDeparture = _interpolate(dep, windFrom, waveFrom)
          ..atMidpoint = _interpolate(mid, windMid, waveMid)
          ..atDestination = _interpolate(dest, windTo, waveTo)
          ..passageHourly = hourly
          ..loading = false;
      });
    } catch (e) {
      setState(() {
        _options[idx].error = e.toString();
        _options[idx].loading = false;
      });
    }
  }

  Future<void> _pickDateTime(int idx) async {
    final opt = _options[idx];
    final date = await showDatePicker(
      context: context,
      initialDate: opt.departureTime,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 14)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(opt.departureTime),
    );
    if (time == null || !mounted) return;
    setState(() {
      _options[idx].departureTime =
          DateTime(date.year, date.month, date.day, time.hour, time.minute);
      _options[idx].atDeparture = null;
      _options[idx].atMidpoint = null;
      _options[idx].atDestination = null;
      _options[idx].passageHourly = [];
    });
    _fetchOption(idx);
  }

  Future<void> _saveOption(int idx) async {
    final opt = _options[idx];
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'departure_planner_selected',
      jsonEncode({
        'departure': opt.departureTime.toIso8601String(),
        'from': _fromCtrl.text,
        'to': _toCtrl.text,
        'speed': _vesselSpeed,
        'durationHours': _durationHours,
        'score': opt.score.name,
      }),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Departure ${DateFormat('d MMM HH:mm').format(opt.departureTime)} saved',
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isTablet = width >= 700;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Departure Planner'),
      ),
      body: Column(
        children: [
          _buildRouteInput(),
          if (_routeError != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(_routeError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          Expanded(
            child: isTablet ? _buildTabletCards() : _buildPhoneCards(),
          ),
          if (_selectedOption < _options.length &&
              (_options[_selectedOption].atDeparture != null ||
                  _options[_selectedOption].loading))
            _buildBottomPanel(_selectedOption),
        ],
      ),
    );
  }

  Widget _buildRouteInput() {
    return Card(
      margin: const EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _fromCtrl,
                    decoration: const InputDecoration(
                      labelText: 'From (name or lat,lng)',
                      isDense: true,
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.my_location, size: 18),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _toCtrl,
                    decoration: const InputDecoration(
                      labelText: 'To (name or lat,lng)',
                      isDense: true,
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.location_on, size: 18),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _speedCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Speed (kn)',
                      isDense: true,
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.speed, size: 18),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _durationCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Duration (h)',
                      isDense: true,
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.schedule, size: 18),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _routeLoading ? null : _resolveRoute,
                  icon: _routeLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.search, size: 18),
                  label: const Text('Go'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhoneCards() {
    return PageView.builder(
      controller: _pageCtrl,
      itemCount: _options.length,
      onPageChanged: (i) => setState(() => _selectedOption = i),
      itemBuilder: (ctx, i) => _DepartureCard(
        option: _options[i],
        index: i,
        isSelected: _selectedOption == i,
        onTap: () => setState(() => _selectedOption = i),
        onEditTime: () => _pickDateTime(i),
        onRefresh: () => _fetchOption(i),
      ),
    );
  }

  Widget _buildTabletCards() {
    final width = MediaQuery.of(context).size.width;
    final isWide = width >= 900;
    if (isWide) {
      // 4-column row
      return Row(
        children: List.generate(
          _options.length,
          (i) => Expanded(
            child: _DepartureCard(
              option: _options[i],
              index: i,
              isSelected: _selectedOption == i,
              onTap: () => setState(() => _selectedOption = i),
              onEditTime: () => _pickDateTime(i),
              onRefresh: () => _fetchOption(i),
            ),
          ),
        ),
      );
    }
    // 2×2 grid
    return GridView.builder(
      padding: const EdgeInsets.all(4),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 1.1,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
      ),
      itemCount: _options.length,
      itemBuilder: (ctx, i) => _DepartureCard(
        option: _options[i],
        index: i,
        isSelected: _selectedOption == i,
        onTap: () => setState(() => _selectedOption = i),
        onEditTime: () => _pickDateTime(i),
        onRefresh: () => _fetchOption(i),
      ),
    );
  }

  Widget _buildBottomPanel(int idx) {
    final opt = _options[idx];
    return Container(
      constraints: const BoxConstraints(maxHeight: 280),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: Border(
          top: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Option ${idx + 1}: ${DateFormat('EEE d MMM HH:mm').format(opt.departureTime)}',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                FilledButton.icon(
                  onPressed: () => _saveOption(idx),
                  icon: const Icon(Icons.check, size: 16),
                  label: const Text('Use this departure'),
                ),
              ],
            ),
          ),
          if (opt.loading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(),
            )
          else if (opt.atDeparture != null) ...[
            _buildWeatherBreakdown(opt),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: _WindChart(hourly: opt.passageHourly),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildWeatherBreakdown(_DepartureOption opt) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          _buildBreakdownColumn('Departure', opt.atDeparture),
          const SizedBox(width: 8),
          _buildBreakdownColumn('Midpoint', opt.atMidpoint),
          const SizedBox(width: 8),
          _buildBreakdownColumn('Arrival', opt.atDestination),
        ],
      ),
    );
  }

  Widget _buildBreakdownColumn(String label, _HourlyPoint? pt) {
    return Expanded(
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              if (pt == null) ...[
                const Icon(Icons.hourglass_empty, size: 16),
              ] else ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Transform.rotate(
                      angle: (pt.windDir * math.pi) / 180,
                      child: const Icon(Icons.navigation, size: 14),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${pt.windSpeed.toStringAsFixed(1)}kn',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.waves, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      '${pt.waveHeight.toStringAsFixed(1)}m',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Departure Card
// ---------------------------------------------------------------------------

class _DepartureCard extends StatelessWidget {
  const _DepartureCard({
    required this.option,
    required this.index,
    required this.isSelected,
    required this.onTap,
    required this.onEditTime,
    required this.onRefresh,
  });

  final _DepartureOption option;
  final int index;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onEditTime;
  final VoidCallback onRefresh;

  Color _scoreColor(BuildContext context, _ConditionScore score) {
    switch (score) {
      case _ConditionScore.excellent:
      case _ConditionScore.good:
        return Colors.green;
      case _ConditionScore.marginal:
        return Colors.amber.shade700;
      case _ConditionScore.poor:
        return Colors.red;
    }
  }

  IconData _scoreIcon(_ConditionScore score) {
    switch (score) {
      case _ConditionScore.excellent:
      case _ConditionScore.good:
        return Icons.check_circle;
      case _ConditionScore.marginal:
        return Icons.warning;
      case _ConditionScore.poor:
        return Icons.cancel;
    }
  }

  String _scoreLabel(_ConditionScore score) {
    switch (score) {
      case _ConditionScore.excellent:
        return 'Excellent';
      case _ConditionScore.good:
        return 'Good';
      case _ConditionScore.marginal:
        return 'Marginal';
      case _ConditionScore.poor:
        return 'Poor';
    }
  }

  IconData _weatherIcon(_HourlyPoint pt) {
    if (pt.windGust > 30) return Icons.thunderstorm;
    if (pt.windSpeed > 15) return Icons.cloud;
    return Icons.wb_sunny;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final score = option.score;
    final scoreColor =
        option.atDeparture != null ? _scoreColor(context, score) : Colors.grey;

    return GestureDetector(
      onTap: onTap,
      child: Card(
        margin: const EdgeInsets.all(6),
        color: isSelected
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.surface,
        elevation: isSelected ? 4 : 1,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: option number + score icon
              Row(
                children: [
                  Text(
                    'Option ${index + 1}',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  if (option.loading)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    Icon(
                      _scoreIcon(score),
                      color: scoreColor,
                      size: 22,
                    ),
                ],
              ),
              const SizedBox(height: 6),
              // Departure time
              InkWell(
                onTap: onEditTime,
                borderRadius: BorderRadius.circular(6),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_today, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      DateFormat('EEE d MMM').format(option.departureTime),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ],
                ),
              ),
              InkWell(
                onTap: onEditTime,
                borderRadius: BorderRadius.circular(6),
                child: Row(
                  children: [
                    const Icon(Icons.access_time, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      DateFormat('HH:mm').format(option.departureTime),
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.edit, size: 12, color: Colors.grey),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              if (option.error != null) ...[
                Row(
                  children: [
                    const Icon(Icons.error_outline, size: 16, color: Colors.red),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'Fetch failed',
                        style: TextStyle(
                            color: theme.colorScheme.error, fontSize: 12),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh, size: 18),
                      onPressed: onRefresh,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ] else if (option.atDeparture == null && !option.loading) ...[
                Text(
                  'Set route and tap Go',
                  style:
                      TextStyle(color: theme.colorScheme.outline, fontSize: 12),
                ),
              ] else if (option.atDeparture != null) ...[
                // Wind at departure
                _WeatherRow(
                  label: 'Dep wind',
                  pt: option.atDeparture!,
                  weatherIcon: _weatherIcon(option.atDeparture!),
                ),
                _WeatherRow(
                  label: 'Mid wind',
                  pt: option.atMidpoint,
                  weatherIcon: option.atMidpoint != null
                      ? _weatherIcon(option.atMidpoint!)
                      : Icons.hourglass_empty,
                ),
                _WeatherRow(
                  label: 'Arr wind',
                  pt: option.atDestination,
                  weatherIcon: option.atDestination != null
                      ? _weatherIcon(option.atDestination!)
                      : Icons.hourglass_empty,
                ),
                const SizedBox(height: 6),
                // Wave at departure
                Row(
                  children: [
                    const Icon(Icons.waves, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      '${option.atDeparture!.waveHeight.toStringAsFixed(1)}m',
                      style: const TextStyle(fontSize: 13),
                    ),
                    const Spacer(),
                    // Overall score badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: scoreColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border:
                            Border.all(color: scoreColor.withValues(alpha: 0.5)),
                      ),
                      child: Text(
                        _scoreLabel(score),
                        style: TextStyle(
                            color: scoreColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _WeatherRow extends StatelessWidget {
  const _WeatherRow({
    required this.label,
    required this.pt,
    required this.weatherIcon,
  });

  final String label;
  final _HourlyPoint? pt;
  final IconData weatherIcon;

  @override
  Widget build(BuildContext context) {
    if (pt == null) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          Icon(weatherIcon, size: 14),
          const SizedBox(width: 4),
          SizedBox(
            width: 56,
            child: Text(label, style: const TextStyle(fontSize: 11)),
          ),
          Transform.rotate(
            angle: (pt!.windDir * math.pi) / 180,
            child: const Icon(Icons.navigation, size: 13),
          ),
          const SizedBox(width: 3),
          Text(
            '${pt!.windSpeed.toStringAsFixed(0)}kn',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Wind Chart (CustomPainter)
// ---------------------------------------------------------------------------

class _WindChart extends StatelessWidget {
  const _WindChart({required this.hourly});
  final List<_HourlyPoint> hourly;

  @override
  Widget build(BuildContext context) {
    if (hourly.isEmpty) return const SizedBox.shrink();
    return CustomPaint(
      painter: _WindChartPainter(
        hourly: hourly,
        lineColor: Theme.of(context).colorScheme.primary,
        gridColor: Theme.of(context).dividerColor,
        labelColor: Theme.of(context).colorScheme.onSurface,
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _WindChartPainter extends CustomPainter {
  _WindChartPainter({
    required this.hourly,
    required this.lineColor,
    required this.gridColor,
    required this.labelColor,
  });

  final List<_HourlyPoint> hourly;
  final Color lineColor;
  final Color gridColor;
  final Color labelColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (hourly.isEmpty) return;
    const padLeft = 32.0;
    const padBottom = 20.0;
    const padTop = 8.0;
    const padRight = 8.0;
    final chartW = size.width - padLeft - padRight;
    final chartH = size.height - padBottom - padTop;

    final maxSpeed =
        hourly.map((p) => p.windSpeed).reduce(math.max).clamp(5, 60).toDouble();
    final minSpeed = 0.0;

    double xOf(int i) => padLeft + (i / (hourly.length - 1)) * chartW;
    double yOf(double v) =>
        padTop + chartH - ((v - minSpeed) / (maxSpeed - minSpeed)) * chartH;

    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 0.5;
    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final gustPaint = Paint()
      ..color = lineColor.withValues(alpha: 0.3)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    final labelStyle = TextStyle(color: labelColor, fontSize: 9);

    // Gridlines at 0, 10, 20, 30 kn
    for (final v in [0.0, 10.0, 20.0, 30.0]) {
      if (v > maxSpeed) continue;
      final y = yOf(v);
      canvas.drawLine(
          Offset(padLeft, y), Offset(size.width - padRight, y), gridPaint);
      final tp = TextPainter(
        text: TextSpan(text: '${v.toInt()}', style: labelStyle),
        textDirection: ui.TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(0, y - 5));
    }

    // Wind speed line
    final windPath = Path();
    for (var i = 0; i < hourly.length; i++) {
      final x = xOf(i);
      final y = yOf(hourly[i].windSpeed);
      if (i == 0) {
        windPath.moveTo(x, y);
      } else {
        windPath.lineTo(x, y);
      }
    }
    canvas.drawPath(windPath, linePaint);

    // Gust line
    final gustPath = Path();
    for (var i = 0; i < hourly.length; i++) {
      final x = xOf(i);
      final y = yOf(hourly[i].windGust);
      if (i == 0) {
        gustPath.moveTo(x, y);
      } else {
        gustPath.lineTo(x, y);
      }
    }
    canvas.drawPath(gustPath, gustPaint);

    // X axis hour labels every 6 hours
    final tickPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var i = 0; i < hourly.length; i += 6) {
      final x = xOf(i);
      canvas.drawLine(
          Offset(x, size.height - padBottom),
          Offset(x, size.height - padBottom + 3),
          tickPaint);
      final label = 'h$i';
      final tp = TextPainter(
        text: TextSpan(text: label, style: labelStyle),
        textDirection: ui.TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x - tp.width / 2, size.height - padBottom + 4));
    }
  }

  @override
  bool shouldRepaint(_WindChartPainter old) => old.hourly != hourly;
}
