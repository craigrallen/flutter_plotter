import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/models/tide_prediction.dart';
import '../../core/nav/geo.dart';
import 'tide_station.dart';

class TideService {
  static const _stationsUrl =
      'https://api.tidesandcurrents.noaa.gov/mdapi/prod/webapi/stations.json'
      '?type=tidepredictions&units=metric';

  static const _predictionsBase =
      'https://api.tidesandcurrents.noaa.gov/api/prod/datagetter';

  List<TideStation>? _stationsCache;
  DateTime? _stationsCacheTime;

  /// Fetch all NOAA tide prediction stations, cached in memory for 24h.
  Future<List<TideStation>> fetchStations() async {
    if (_stationsCache != null &&
        _stationsCacheTime != null &&
        DateTime.now().difference(_stationsCacheTime!).inHours < 24) {
      return _stationsCache!;
    }

    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString('tide_stations_json');
    final cachedAt = prefs.getInt('tide_stations_at');

    if (cached != null &&
        cachedAt != null &&
        DateTime.now().millisecondsSinceEpoch - cachedAt < 86400000) {
      _stationsCache = _parseStations(cached);
      _stationsCacheTime =
          DateTime.fromMillisecondsSinceEpoch(cachedAt);
      return _stationsCache!;
    }

    final resp = await http.get(Uri.parse(_stationsUrl));
    if (resp.statusCode != 200) {
      throw Exception('Failed to fetch tide stations: ${resp.statusCode}');
    }

    _stationsCache = _parseStations(resp.body);
    _stationsCacheTime = DateTime.now();

    await prefs.setString('tide_stations_json', resp.body);
    await prefs.setInt(
        'tide_stations_at', DateTime.now().millisecondsSinceEpoch);

    return _stationsCache!;
  }

  List<TideStation> _parseStations(String body) {
    final json = jsonDecode(body) as Map<String, dynamic>;
    final list = json['stations'] as List<dynamic>;
    return list
        .map((e) => TideStation.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Find the N nearest tide stations to a position.
  Future<List<TideStation>> nearestStations(LatLng position,
      {int count = 5}) async {
    final stations = await fetchStations();
    stations.sort((a, b) {
      final da = haversineDistanceM(position, a.position);
      final db = haversineDistanceM(position, b.position);
      return da.compareTo(db);
    });
    return stations.take(count).toList();
  }

  /// Fetch hi/lo predictions for a station. Cached 24h in SharedPreferences.
  Future<List<TidePrediction>> fetchPredictions(String stationId) async {
    final prefs = await SharedPreferences.getInstance();
    final cacheKey = 'tide_pred_$stationId';
    final cacheTimeKey = 'tide_pred_at_$stationId';

    final cached = prefs.getString(cacheKey);
    final cachedAt = prefs.getInt(cacheTimeKey);

    if (cached != null &&
        cachedAt != null &&
        DateTime.now().millisecondsSinceEpoch - cachedAt < 86400000) {
      return _parsePredictions(cached);
    }

    final now = DateTime.now().toUtc();
    final begin = '${now.year}${_pad(now.month)}${_pad(now.day)}';
    final end = now.add(const Duration(days: 2));
    final endStr = '${end.year}${_pad(end.month)}${_pad(end.day)}';

    final url = '$_predictionsBase'
        '?station=$stationId'
        '&product=predictions'
        '&datum=MLLW'
        '&time_zone=gmt'
        '&interval=hilo'
        '&units=metric'
        '&application=flutter_plotter'
        '&format=json'
        '&begin_date=$begin'
        '&end_date=$endStr';

    final resp = await http.get(Uri.parse(url));
    if (resp.statusCode != 200) {
      throw Exception('Failed to fetch predictions: ${resp.statusCode}');
    }

    await prefs.setString(cacheKey, resp.body);
    await prefs.setInt(cacheTimeKey, DateTime.now().millisecondsSinceEpoch);

    return _parsePredictions(resp.body);
  }

  List<TidePrediction> _parsePredictions(String body) {
    final json = jsonDecode(body) as Map<String, dynamic>;
    final list = json['predictions'] as List<dynamic>?;
    if (list == null) return [];
    return list
        .map((e) => TidePrediction.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  String _pad(int n) => n.toString().padLeft(2, '0');
}
