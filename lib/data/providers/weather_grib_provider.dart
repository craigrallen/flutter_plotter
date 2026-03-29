import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ── Server base URL ──────────────────────────────────────────────────────────

const _kServerBase = 'https://floatilla-fleet-social-production.up.railway.app'; // override in debug with env

// ── Models ───────────────────────────────────────────────────────────────────

class WeatherHourlyEntry {
  const WeatherHourlyEntry({
    required this.time,
    required this.windSpeed,
    required this.windDir,
    this.pressure,
    this.waveHeight,
  });

  final DateTime time;
  final double windSpeed; // knots
  final double windDir; // degrees true
  final double? pressure; // hPa
  final double? waveHeight; // metres

  /// U/V wind components derived from speed + direction
  double get uWind =>
      -windSpeed * math.sin(windDir * math.pi / 180);
  double get vWind =>
      -windSpeed * math.cos(windDir * math.pi / 180);

  factory WeatherHourlyEntry.fromJson(Map<String, dynamic> j) {
    return WeatherHourlyEntry(
      time: DateTime.parse(j['time'] as String),
      windSpeed: (j['windSpeed'] as num?)?.toDouble() ?? 0,
      windDir: (j['windDir'] as num?)?.toDouble() ?? 0,
      pressure: (j['pressure'] as num?)?.toDouble(),
      waveHeight: (j['waveHeight'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
        'time': time.toIso8601String(),
        'windSpeed': windSpeed,
        'windDir': windDir,
        'pressure': pressure,
        'waveHeight': waveHeight,
      };
}

class WeatherGribEntry {
  const WeatherGribEntry({
    required this.lat,
    required this.lng,
    required this.hours,
  });

  final double lat;
  final double lng;
  final List<WeatherHourlyEntry> hours;

  LatLng get position => LatLng(lat, lng);

  /// Entry at a given forecast hour index (clamped).
  WeatherHourlyEntry atHour(int idx) =>
      hours[idx.clamp(0, hours.length - 1)];

  factory WeatherGribEntry.fromJson(Map<String, dynamic> j) {
    final rawHours = (j['hours'] as List<dynamic>?) ?? [];
    return WeatherGribEntry(
      lat: (j['lat'] as num).toDouble(),
      lng: (j['lng'] as num).toDouble(),
      hours: rawHours
          .map((h) => WeatherHourlyEntry.fromJson(h as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'lat': lat,
        'lng': lng,
        'hours': hours.map((h) => h.toJson()).toList(),
      };
}

class GribBounds {
  const GribBounds({
    required this.north,
    required this.south,
    required this.east,
    required this.west,
  });

  final double north;
  final double south;
  final double east;
  final double west;

  @override
  String toString() =>
      'GribBounds(n:$north, s:$south, e:$east, w:$west)';
}

// ── State ────────────────────────────────────────────────────────────────────

class WeatherGribState {
  const WeatherGribState({
    this.isLoading = false,
    this.grid = const [],
    this.model = 'gfs',
    this.fetchedAt,
    this.bounds,
    this.forecastHour = 0,
    this.error,
    this.showWind = true,
    this.showPressure = false,
    this.showWaves = false,
    this.isAnimating = false,
    this.isOfflineCapable = false,
  });

  final bool isLoading;
  final List<WeatherGribEntry> grid;
  final String model;
  final DateTime? fetchedAt;
  final GribBounds? bounds;
  final int forecastHour; // 0–72 in steps of 3
  final String? error;
  final bool showWind;
  final bool showPressure;
  final bool showWaves;
  final bool isAnimating;
  final bool isOfflineCapable;

  /// All available hour indices that have data (0, 3, 6 … 72)
  List<int> get availableHours {
    if (grid.isEmpty) return List.generate(25, (i) => i * 3);
    final maxHours = grid.first.hours.length;
    final result = <int>[];
    for (var h = 0; h < maxHours; h += 3) {
      result.add(h);
    }
    return result;
  }

  WeatherGribState copyWith({
    bool? isLoading,
    List<WeatherGribEntry>? grid,
    String? model,
    DateTime? fetchedAt,
    GribBounds? bounds,
    int? forecastHour,
    String? error,
    bool? showWind,
    bool? showPressure,
    bool? showWaves,
    bool? isAnimating,
    bool? isOfflineCapable,
  }) {
    return WeatherGribState(
      isLoading: isLoading ?? this.isLoading,
      grid: grid ?? this.grid,
      model: model ?? this.model,
      fetchedAt: fetchedAt ?? this.fetchedAt,
      bounds: bounds ?? this.bounds,
      forecastHour: forecastHour ?? this.forecastHour,
      error: error,
      showWind: showWind ?? this.showWind,
      showPressure: showPressure ?? this.showPressure,
      showWaves: showWaves ?? this.showWaves,
      isAnimating: isAnimating ?? this.isAnimating,
      isOfflineCapable: isOfflineCapable ?? this.isOfflineCapable,
    );
  }
}

// ── Notifier ─────────────────────────────────────────────────────────────────

class WeatherGribNotifier extends StateNotifier<WeatherGribState> {
  WeatherGribNotifier() : super(const WeatherGribState());

  static const _prefsKey = 'weather_grib_offline_v1';

  // ── Fetch ────────────────────────────────────────────────────────────────

  /// Fetch weather grid directly from Open-Meteo (no server proxy needed).
  Future<void> fetchGrid(GribBounds bounds, String model) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      // Sample grid points every 0.5° within bounds
      const step = 0.5;
      final points = <({double lat, double lng})>[];
      for (double lat = bounds.south; lat <= bounds.north + 0.01; lat += step) {
        for (double lng = bounds.west; lng <= bounds.east + 0.01; lng += step) {
          points.add((lat: _round(lat), lng: _round(lng)));
        }
      }
      if (points.isEmpty) throw Exception('No grid points in bounds');

      // Map model name to Open-Meteo model param
      final modelParam = switch (model.toLowerCase()) {
        'ecmwf' => 'ecmwf_ifs025',
        'icon'  => 'icon_seamless',
        _       => 'gfs_seamless',
      };

      // Fetch all points in batches of 10
      final entries = <WeatherGribEntry>[];
      for (int i = 0; i < points.length; i += 10) {
        final batch = points.sublist(i, (i + 10).clamp(0, points.length));
        final results = await Future.wait(batch.map((p) => _fetchPoint(p.lat, p.lng, modelParam)));
        entries.addAll(results.whereType<WeatherGribEntry>());
      }

      if (entries.isEmpty) throw Exception('No data returned from Open-Meteo');

      state = state.copyWith(
        isLoading: false,
        grid: entries,
        model: model,
        bounds: bounds,
        fetchedAt: DateTime.now(),
        forecastHour: 0,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  double _round(double v) => (v * 10).round() / 10;

  Future<WeatherGribEntry?> _fetchPoint(double lat, double lng, String modelParam) async {
    try {
      final uri = Uri.parse('https://api.open-meteo.com/v1/forecast').replace(
        queryParameters: {
          'latitude': lat.toStringAsFixed(1),
          'longitude': lng.toStringAsFixed(1),
          'hourly': 'wind_speed_10m,wind_direction_10m,pressure_msl',
          'wind_speed_unit': 'kn',
          'forecast_days': '3',
          'models': modelParam,
        },
      );
      final resp = await http.get(uri).timeout(const Duration(seconds: 30));
      if (resp.statusCode != 200) return null;
      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      final hourly = json['hourly'] as Map<String, dynamic>?;
      if (hourly == null) return null;

      final times = (hourly['time'] as List?)?.cast<String>() ?? [];
      final speeds = (hourly['wind_speed_10m'] as List?)?.cast<num>() ?? [];
      final dirs = (hourly['wind_direction_10m'] as List?)?.cast<num>() ?? [];
      final pressures = (hourly['pressure_msl'] as List?)?.cast<num?>() ?? [];

      final hours = <WeatherHourlyEntry>[];
      for (int i = 0; i < times.length; i++) {
        hours.add(WeatherHourlyEntry(
          time: DateTime.parse(times[i]),
          windSpeed: (speeds.length > i ? speeds[i] : 0).toDouble(),
          windDir: (dirs.length > i ? dirs[i] : 0).toDouble(),
          pressure: pressures.length > i ? pressures[i]?.toDouble() : null,
        ));
      }
      return WeatherGribEntry(lat: lat, lng: lng, hours: hours);
    } catch (_) {
      return null;
    }
  }

  // ── Forecast hour ────────────────────────────────────────────────────────

  void setForecastHour(int hour) {
    state = state.copyWith(forecastHour: hour.clamp(0, 72));
  }

  // ── Layer toggles ────────────────────────────────────────────────────────

  void toggleWind() =>
      state = state.copyWith(showWind: !state.showWind);
  void togglePressure() =>
      state = state.copyWith(showPressure: !state.showPressure);
  void toggleWaves() =>
      state = state.copyWith(showWaves: !state.showWaves);

  // ── Animation ────────────────────────────────────────────────────────────

  Future<void> startAnimation() async {
    if (state.isAnimating || state.grid.isEmpty) return;
    state = state.copyWith(isAnimating: true);

    final hours = state.availableHours;
    for (final h in hours) {
      if (!state.isAnimating) break;
      state = state.copyWith(forecastHour: h);
      await Future<void>.delayed(const Duration(seconds: 1));
    }

    state = state.copyWith(isAnimating: false);
  }

  void stopAnimation() {
    state = state.copyWith(isAnimating: false);
  }

  // ── Offline persistence ──────────────────────────────────────────────────

  Future<void> saveOffline() async {
    if (state.grid.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final payload = jsonEncode({
        'model': state.model,
        'fetchedAt': state.fetchedAt?.toIso8601String(),
        'bounds': state.bounds == null
            ? null
            : {
                'n': state.bounds!.north,
                's': state.bounds!.south,
                'e': state.bounds!.east,
                'w': state.bounds!.west,
              },
        'grid': state.grid.map((e) => e.toJson()).toList(),
      });
      await prefs.setString(_prefsKey, payload);
      state = state.copyWith(isOfflineCapable: true);
    } catch (e) {
      debugPrint('saveOffline error: $e');
    }
  }

  Future<void> loadOffline() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null) return;
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final rawGrid = (json['grid'] as List<dynamic>?) ?? [];
      final grid = rawGrid
          .map((e) => WeatherGribEntry.fromJson(e as Map<String, dynamic>))
          .toList();
      final boundsJson = json['bounds'] as Map<String, dynamic>?;
      state = state.copyWith(
        grid: grid,
        model: json['model'] as String? ?? 'gfs',
        fetchedAt: json['fetchedAt'] != null
            ? DateTime.tryParse(json['fetchedAt'] as String)
            : null,
        bounds: boundsJson == null
            ? null
            : GribBounds(
                north: (boundsJson['n'] as num).toDouble(),
                south: (boundsJson['s'] as num).toDouble(),
                east: (boundsJson['e'] as num).toDouble(),
                west: (boundsJson['w'] as num).toDouble(),
              ),
        isOfflineCapable: true,
      );
    } catch (e) {
      debugPrint('loadOffline error: $e');
    }
  }
}

// ── Provider ─────────────────────────────────────────────────────────────────

final weatherGribProvider =
    StateNotifierProvider<WeatherGribNotifier, WeatherGribState>(
  (ref) => WeatherGribNotifier(),
);
