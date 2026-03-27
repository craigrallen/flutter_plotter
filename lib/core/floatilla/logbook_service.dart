import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'floatilla_service.dart';

/// Voyage logbook — auto-logs GPS position every minute when underway.
class LogbookService {
  LogbookService._();
  static final instance = LogbookService._();

  Timer? _autoLogTimer;
  bool _isLogging = false;
  LatLng? _lastPos;
  int _entriesThisSession = 0;

  bool get isLogging => _isLogging;
  int get entriesThisSession => _entriesThisSession;

  void startAutoLog({
    required Stream<({LatLng pos, double sog, double cog, double? depth, double? windSpeed, double? windAngle})> dataStream,
    Duration interval = const Duration(minutes: 1),
  }) {
    if (_isLogging) return;
    _isLogging = true;
    _entriesThisSession = 0;

    _autoLogTimer = Timer.periodic(interval, (_) async {
      // Actual position comes from the data stream via latest values
    });

    dataStream.listen((data) async {
      // Only log if moving (>0.5 kn) or every 5 min regardless
      final moving = data.sog > 0.5;
      final farEnough = _lastPos == null ||
          const Distance().distance(_lastPos!, data.pos) > 20;

      if (moving && farEnough) {
        _lastPos = data.pos;
        await _postEntry(
          pos: data.pos,
          sog: data.sog,
          cog: data.cog,
          depth: data.depth,
          windSpeed: data.windSpeed,
          windAngle: data.windAngle,
          entryType: 'auto',
        );
      }
    });
  }

  void stopAutoLog() {
    _autoLogTimer?.cancel();
    _autoLogTimer = null;
    _isLogging = false;
  }

  Future<void> addManualEntry({
    required LatLng pos,
    String? note,
    double? sog,
    double? cog,
  }) async {
    await _postEntry(
      pos: pos,
      sog: sog ?? 0,
      cog: cog ?? 0,
      note: note,
      entryType: 'manual',
    );
  }

  Future<void> _postEntry({
    required LatLng pos,
    double sog = 0,
    double cog = 0,
    double? depth,
    double? windSpeed,
    double? windAngle,
    String? note,
    String entryType = 'auto',
  }) async {
    if (!FloatillaService.instance.isLoggedIn()) return;
    try {
      final headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${FloatillaService.instance.token}',
      };
      final body = <String, dynamic>{
        'lat': pos.latitude,
        'lng': pos.longitude,
        'sog': sog,
        'cog': cog,
        'entryType': entryType,
      };
      if (depth != null) body['depth'] = depth;
      if (windSpeed != null) body['windSpeed'] = windSpeed;
      if (windAngle != null) body['windAngle'] = windAngle;
      if (note != null) body['note'] = note;

      await http.post(
        Uri.parse('${FloatillaService.instance.baseUrl}/logbook/entry'),
        headers: headers,
        body: jsonEncode(body),
      );
      _entriesThisSession++;
    } catch (_) {}
  }

  /// Returns URL to download GPX for the last N days.
  String gpxUrl({int days = 7}) {
    final since = (DateTime.now()
            .subtract(Duration(days: days))
            .millisecondsSinceEpoch ~/
        1000);
    return '${FloatillaService.instance.baseUrl}/logbook/gpx?since=$since';
  }
}
