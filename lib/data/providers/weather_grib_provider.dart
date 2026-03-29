import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ── Server base URL ──────────────────────────────────────────────────────────

const _kServerBase = 'https://floatilla.app'; // override in debug with env

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

  Future<void> fetchGrid(GribBounds bounds, String model) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final uri = Uri.parse('$_kServerBase/weather/grib').replace(
        queryParameters: {
          'n': bounds.north.toStringAsFixed(4),
          's': bounds.south.toStringAsFixed(4),
          'e': bounds.east.toStringAsFixed(4),
          'w': bounds.west.toStringAsFixed(4),
          'model': model,
        },
      );
      final resp = await http.get(uri).timeout(const Duration(seconds: 60));
      if (resp.statusCode != 200) {
        throw Exception('Server returned ${resp.statusCode}');
      }
      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      final rawGrid = (json['grid'] as List<dynamic>?) ?? [];
      final grid = rawGrid
          .map((e) => WeatherGribEntry.fromJson(e as Map<String, dynamic>))
          .toList();

      state = state.copyWith(
        isLoading: false,
        grid: grid,
        model: model,
        bounds: bounds,
        fetchedAt: DateTime.now(),
        forecastHour: 0,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
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
