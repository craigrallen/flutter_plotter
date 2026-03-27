import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/models/weather_forecast.dart';

class WeatherService {
  static const _baseUrl = 'https://api.open-meteo.com/v1/forecast';

  final Map<String, _CacheEntry> _memCache = {};

  /// Fetch weather for a 3x3 grid (~0.5° spacing) around [center].
  /// Each grid point is cached for 3 hours.
  Future<List<WeatherForecast>> fetchGrid(LatLng center) async {
    final forecasts = <WeatherForecast>[];
    const spacing = 0.5; // degrees

    for (int dy = -1; dy <= 1; dy++) {
      for (int dx = -1; dx <= 1; dx++) {
        final lat = center.latitude + dy * spacing;
        final lon = center.longitude + dx * spacing;
        final pos = LatLng(lat, lon);
        final fc = await _fetchPoint(pos);
        if (fc != null) forecasts.add(fc);
      }
    }
    return forecasts;
  }

  /// Fetch a single point, with 3h mem+disk cache.
  Future<WeatherForecast?> _fetchPoint(LatLng pos) async {
    final key = '${pos.latitude.toStringAsFixed(2)}_${pos.longitude.toStringAsFixed(2)}';

    // Memory cache.
    final mem = _memCache[key];
    if (mem != null &&
        DateTime.now().difference(mem.fetchedAt).inHours < 3) {
      return mem.forecast;
    }

    // Disk cache.
    final prefs = await SharedPreferences.getInstance();
    final diskKey = 'weather_$key';
    final diskTimeKey = 'weather_at_$key';
    final cached = prefs.getString(diskKey);
    final cachedAt = prefs.getInt(diskTimeKey);

    if (cached != null &&
        cachedAt != null &&
        DateTime.now().millisecondsSinceEpoch - cachedAt < 10800000) {
      final fc = _parseResponse(pos, cached);
      if (fc != null) {
        _memCache[key] = _CacheEntry(fc, DateTime.fromMillisecondsSinceEpoch(cachedAt));
        return fc;
      }
    }

    // Fetch from API.
    final url = '$_baseUrl'
        '?latitude=${pos.latitude.toStringAsFixed(4)}'
        '&longitude=${pos.longitude.toStringAsFixed(4)}'
        '&hourly=windspeed_10m,winddirection_10m,precipitation,wave_height'
        '&windspeed_unit=kn'
        '&forecast_days=2';

    try {
      final resp = await http.get(Uri.parse(url));
      if (resp.statusCode != 200) return null;

      final fc = _parseResponse(pos, resp.body);
      if (fc != null) {
        _memCache[key] = _CacheEntry(fc, DateTime.now());
        await prefs.setString(diskKey, resp.body);
        await prefs.setInt(diskTimeKey, DateTime.now().millisecondsSinceEpoch);
      }
      return fc;
    } catch (_) {
      return null;
    }
  }

  WeatherForecast? _parseResponse(LatLng pos, String body) {
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      final hourly = json['hourly'] as Map<String, dynamic>;
      final times = (hourly['time'] as List<dynamic>).cast<String>();
      final windSpeeds = (hourly['windspeed_10m'] as List<dynamic>);
      final windDirs = (hourly['winddirection_10m'] as List<dynamic>);
      final precip = (hourly['precipitation'] as List<dynamic>);
      final waves = hourly['wave_height'] as List<dynamic>?;

      final points = <WeatherPoint>[];
      for (int i = 0; i < times.length; i++) {
        points.add(WeatherPoint(
          position: pos,
          time: DateTime.parse(times[i]),
          windSpeedKn: (windSpeeds[i] as num?)?.toDouble() ?? 0,
          windDirectionDeg: (windDirs[i] as num?)?.toDouble() ?? 0,
          precipitationMm: (precip[i] as num?)?.toDouble() ?? 0,
          waveHeightM: (waves?[i] as num?)?.toDouble(),
        ));
      }

      return WeatherForecast(
        position: pos,
        hourly: points,
        fetchedAt: DateTime.now(),
      );
    } catch (_) {
      return null;
    }
  }
}

class _CacheEntry {
  final WeatherForecast forecast;
  final DateTime fetchedAt;
  _CacheEntry(this.forecast, this.fetchedAt);
}
