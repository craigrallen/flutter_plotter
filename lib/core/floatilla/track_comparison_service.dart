import 'dart:convert';
import 'dart:math' as math;
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:xml/xml.dart';
import 'floatilla_service.dart';

// ── Data models ───────────────────────────────────────────────────────────────

class TrackPoint {
  final LatLng position;
  final DateTime timestamp;
  final double? sog; // knots

  const TrackPoint({
    required this.position,
    required this.timestamp,
    this.sog,
  });
}

class ComparisonTrack {
  final String id;
  final String label; // vessel name or username
  final String? username; // friend's username if remote
  final String source; // 'local', 'friend', 'gpx'
  final List<TrackPoint> points;
  final DateTime? startTime;
  final DateTime? endTime;
  final double distanceNm;
  bool enabled;

  ComparisonTrack({
    required this.id,
    required this.label,
    this.username,
    required this.source,
    required this.points,
    this.startTime,
    this.endTime,
    required this.distanceNm,
    this.enabled = true,
  });

  Duration? get elapsed {
    if (startTime == null || endTime == null) return null;
    return endTime!.difference(startTime!);
  }

  double? get avgSog {
    final speeds = points.where((p) => p.sog != null).map((p) => p.sog!).toList();
    if (speeds.isEmpty) return null;
    return speeds.reduce((a, b) => a + b) / speeds.length;
  }

  double? get maxSog {
    final speeds = points.where((p) => p.sog != null).map((p) => p.sog!).toList();
    if (speeds.isEmpty) return null;
    return speeds.reduce((a, b) => a > b ? a : b);
  }
}

class DivergencePoint {
  final LatLng position;
  final double separationNm;
  final DateTime timestamp;

  const DivergencePoint({
    required this.position,
    required this.separationNm,
    required this.timestamp,
  });
}

// ── Local voyage summary ──────────────────────────────────────────────────────

class LocalVoyageSummary {
  final String voyageId;
  final DateTime startTime;
  final DateTime endTime;
  final double distanceNm;
  final List<TrackPoint> points;

  const LocalVoyageSummary({
    required this.voyageId,
    required this.startTime,
    required this.endTime,
    required this.distanceNm,
    required this.points,
  });
}

// ── Service ───────────────────────────────────────────────────────────────────

class TrackComparisonService {
  TrackComparisonService._();
  static final instance = TrackComparisonService._();

  static const double _divergenceThresholdNm = 0.5;

  // ── Load local voyages from logbook entries via server ────────────────────

  Future<List<LocalVoyageSummary>> loadLocalTracks() async {
    final svc = FloatillaService.instance;
    if (!svc.isLoggedIn()) return [];

    try {
      // Fetch ship log voyages
      final voyagesResp = await http.get(
        Uri.parse('${svc.baseUrl}/ships-log/voyages'),
        headers: {'Authorization': 'Bearer ${svc.token}'},
      );
      if (voyagesResp.statusCode != 200) return [];

      final voyagesList = jsonDecode(voyagesResp.body) as List;
      final summaries = <LocalVoyageSummary>[];

      for (final v in voyagesList.take(10)) {
        final voyageId = v['voyage_id'] as String? ?? '';
        if (voyageId.isEmpty) continue;

        // Fetch entries for this voyage
        final entriesResp = await http.get(
          Uri.parse(
              '${svc.baseUrl}/ships-log?voyage_id=${Uri.encodeComponent(voyageId)}&limit=500'),
          headers: {'Authorization': 'Bearer ${svc.token}'},
        );
        if (entriesResp.statusCode != 200) continue;

        final entries = (jsonDecode(entriesResp.body) as List)
            .cast<Map<String, dynamic>>();

        final points = _entriestoPoints(entries);
        if (points.isEmpty) continue;

        final distNm = _calcDistanceNm(points.map((p) => p.position).toList());
        summaries.add(LocalVoyageSummary(
          voyageId: voyageId,
          startTime: points.first.timestamp,
          endTime: points.last.timestamp,
          distanceNm: distNm,
          points: points,
        ));
      }
      return summaries;
    } catch (e) {
      return [];
    }
  }

  /// Also load from the simple logbook entries (voyage_id-grouped)
  Future<List<LocalVoyageSummary>> loadLocalLogbookTracks() async {
    final svc = FloatillaService.instance;
    if (!svc.isLoggedIn()) return [];

    try {
      final since = DateTime.now()
              .subtract(const Duration(days: 90))
              .millisecondsSinceEpoch ~/
          1000;
      final resp = await http.get(
        Uri.parse('${svc.baseUrl}/logbook?since=$since&limit=1000'),
        headers: {'Authorization': 'Bearer ${svc.token}'},
      );
      if (resp.statusCode != 200) return [];

      final entries = (jsonDecode(resp.body) as List).cast<Map<String, dynamic>>();

      // Group by date (day = voyage proxy since logbook has no voyage_id)
      final Map<String, List<Map<String, dynamic>>> grouped = {};
      for (final e in entries) {
        if (e['lat'] == null || e['lng'] == null) continue;
        final ts = (e['created_at'] as num).toInt();
        final day = DateTime.fromMillisecondsSinceEpoch(ts * 1000)
            .toLocal()
            .toString()
            .substring(0, 10);
        grouped.putIfAbsent(day, () => []).add(e);
      }

      final summaries = <LocalVoyageSummary>[];
      for (final entry in grouped.entries) {
        final sorted = entry.value
          ..sort((a, b) => (a['created_at'] as num)
              .compareTo(b['created_at'] as num));
        final points = _entriestoPoints(sorted);
        if (points.length < 2) continue;
        final distNm = _calcDistanceNm(points.map((p) => p.position).toList());
        summaries.add(LocalVoyageSummary(
          voyageId: entry.key,
          startTime: points.first.timestamp,
          endTime: points.last.timestamp,
          distanceNm: distNm,
          points: points,
        ));
      }
      summaries.sort((a, b) => b.startTime.compareTo(a.startTime));
      return summaries;
    } catch (e) {
      return [];
    }
  }

  List<TrackPoint> _entriestoPoints(List<Map<String, dynamic>> entries) {
    final points = <TrackPoint>[];
    for (final e in entries) {
      final lat = (e['position_lat'] ?? e['lat']) as num?;
      final lng = (e['position_lng'] ?? e['lng']) as num?;
      if (lat == null || lng == null) continue;

      final tsRaw = (e['logged_at'] ?? e['created_at']) as num?;
      if (tsRaw == null) continue;
      final ts = DateTime.fromMillisecondsSinceEpoch(tsRaw.toInt() * 1000);

      final sog = (e['speed'] ?? e['sog']) as num?;
      points.add(TrackPoint(
        position: LatLng(lat.toDouble(), lng.toDouble()),
        timestamp: ts,
        sog: sog?.toDouble(),
      ));
    }
    points.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return points;
  }

  // ── Load friend tracks from server ─────────────────────────────────────────

  Future<List<ComparisonTrack>> loadFriendTracks(String username) async {
    final svc = FloatillaService.instance;
    if (!svc.isLoggedIn()) return [];

    try {
      final resp = await http.get(
        Uri.parse(
            '${svc.baseUrl}/friends/${Uri.encodeComponent(username)}/tracks'),
        headers: {'Authorization': 'Bearer ${svc.token}'},
      );
      if (resp.statusCode != 200) return [];

      final list = jsonDecode(resp.body) as List;
      final tracks = <ComparisonTrack>[];

      for (final v in list) {
        final rawPoints = v['track_points'] as List? ?? [];
        final points = rawPoints.map((p) {
          final arr = p as List;
          return TrackPoint(
            position: LatLng(
              (arr[0] as num).toDouble(),
              (arr[1] as num).toDouble(),
            ),
            timestamp: arr.length > 2 && arr[2] != null
                ? DateTime.fromMillisecondsSinceEpoch(
                    (arr[2] as num).toInt() * 1000)
                : DateTime.now(),
          );
        }).toList();

        if (points.isEmpty) continue;

        final startTime = v['start_time'] != null
            ? DateTime.fromMillisecondsSinceEpoch(
                (v['start_time'] as num).toInt() * 1000)
            : points.first.timestamp;
        final endTime = v['end_time'] != null
            ? DateTime.fromMillisecondsSinceEpoch(
                (v['end_time'] as num).toInt() * 1000)
            : points.last.timestamp;
        final distNm =
            (v['distance_nm'] as num?)?.toDouble() ??
                _calcDistanceNm(points.map((p) => p.position).toList());

        tracks.add(ComparisonTrack(
          id: v['id']?.toString() ?? v['voyage_id'] as String? ?? 'friend_$username',
          label: username,
          username: username,
          source: 'friend',
          points: points,
          startTime: startTime,
          endTime: endTime,
          distanceNm: distNm,
        ));
      }
      return tracks;
    } catch (e) {
      return [];
    }
  }

  // ── Load GPX file ─────────────────────────────────────────────────────────

  Future<ComparisonTrack?> loadGpxFile(String path) async {
    try {
      final bytes = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['gpx'],
        withData: true,
      );
      if (bytes == null || bytes.files.isEmpty) return null;

      final file = bytes.files.first;
      final content = utf8.decode(file.bytes!);
      return _parseGpx(content, file.name);
    } catch (e) {
      return null;
    }
  }

  Future<ComparisonTrack?> loadGpxFromBytes(
      List<int> bytes, String filename) async {
    try {
      final content = utf8.decode(bytes);
      return _parseGpx(content, filename);
    } catch (e) {
      return null;
    }
  }

  ComparisonTrack? _parseGpx(String content, String filename) {
    try {
      final doc = XmlDocument.parse(content);
      final points = <TrackPoint>[];

      // Try track points first
      for (final trkpt in doc.findAllElements('trkpt')) {
        final lat = double.tryParse(trkpt.getAttribute('lat') ?? '');
        final lon = double.tryParse(trkpt.getAttribute('lon') ?? '');
        if (lat == null || lon == null) continue;

        final timeEl = trkpt.findElements('time').firstOrNull;
        final ts = timeEl != null
            ? DateTime.tryParse(timeEl.innerText) ?? DateTime.now()
            : DateTime.now();

        final speedEl = trkpt.findElements('speed').firstOrNull;
        double? sogKnots;
        if (speedEl != null) {
          final mps = double.tryParse(speedEl.innerText);
          if (mps != null) sogKnots = mps / 0.514444;
        }

        points.add(TrackPoint(
          position: LatLng(lat, lon),
          timestamp: ts,
          sog: sogKnots,
        ));
      }

      // Fall back to waypoints
      if (points.isEmpty) {
        for (final wpt in doc.findAllElements('wpt')) {
          final lat = double.tryParse(wpt.getAttribute('lat') ?? '');
          final lon = double.tryParse(wpt.getAttribute('lon') ?? '');
          if (lat == null || lon == null) continue;
          final timeEl = wpt.findElements('time').firstOrNull;
          final ts = timeEl != null
              ? DateTime.tryParse(timeEl.innerText) ?? DateTime.now()
              : DateTime.now();
          points.add(TrackPoint(
              position: LatLng(lat, lon), timestamp: ts));
        }
      }

      if (points.isEmpty) return null;
      points.sort((a, b) => a.timestamp.compareTo(b.timestamp));

      final label = filename.replaceAll('.gpx', '');
      final distNm = _calcDistanceNm(points.map((p) => p.position).toList());

      return ComparisonTrack(
        id: 'gpx_${DateTime.now().millisecondsSinceEpoch}',
        label: label,
        source: 'gpx',
        points: points,
        startTime: points.first.timestamp,
        endTime: points.last.timestamp,
        distanceNm: distNm,
      );
    } catch (e) {
      return null;
    }
  }

  // ── Divergence analysis ──────────────────────────────────────────────────

  List<DivergencePoint> calculateDivergencePoints(
      ComparisonTrack track1, ComparisonTrack track2) {
    if (track1.points.isEmpty || track2.points.isEmpty) return [];

    final divergences = <DivergencePoint>[];
    bool wasDiverged = false;

    // For each point in track1, find nearest point in track2 by time
    for (final p1 in track1.points) {
      final nearest = _nearestPointByTime(p1.timestamp, track2.points);
      if (nearest == null) continue;

      final distNm = _haversineNm(
        p1.position.latitude,
        p1.position.longitude,
        nearest.position.latitude,
        nearest.position.longitude,
      );

      if (distNm > _divergenceThresholdNm && !wasDiverged) {
        wasDiverged = true;
        divergences.add(DivergencePoint(
          position: p1.position,
          separationNm: distNm,
          timestamp: p1.timestamp,
        ));
      } else if (distNm <= _divergenceThresholdNm) {
        wasDiverged = false;
      }
    }

    return divergences;
  }

  TrackPoint? _nearestPointByTime(DateTime ts, List<TrackPoint> points) {
    if (points.isEmpty) return null;
    TrackPoint? nearest;
    int minDiff = 999999999;
    for (final p in points) {
      final diff = (p.timestamp.millisecondsSinceEpoch -
              ts.millisecondsSinceEpoch)
          .abs();
      if (diff < minDiff) {
        minDiff = diff;
        nearest = p;
      }
    }
    return nearest;
  }

  // ── Time alignment ─────────────────────────────────────────────────────────

  /// Shift all tracks so T=0 is the first point of each track.
  List<ComparisonTrack> alignByTime(List<ComparisonTrack> tracks) {
    return tracks.map((t) {
      if (t.points.isEmpty) return t;
      final t0 = t.points.first.timestamp;
      final epoch = DateTime.fromMillisecondsSinceEpoch(0);
      final shifted = t.points.map((p) {
        final offsetMs =
            p.timestamp.millisecondsSinceEpoch - t0.millisecondsSinceEpoch;
        return TrackPoint(
          position: p.position,
          timestamp: epoch.add(Duration(milliseconds: offsetMs)),
          sog: p.sog,
        );
      }).toList();
      return ComparisonTrack(
        id: t.id,
        label: t.label,
        username: t.username,
        source: t.source,
        points: shifted,
        startTime: epoch,
        endTime: shifted.last.timestamp,
        distanceNm: t.distanceNm,
        enabled: t.enabled,
      );
    }).toList();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  double _haversineNm(
      double lat1, double lng1, double lat2, double lng2) {
    const r = 3440.065;
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLng = (lng2 - lng1) * math.pi / 180;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180) *
            math.cos(lat2 * math.pi / 180) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return r * 2 * math.asin(math.sqrt(a));
  }

  double _calcDistanceNm(List<LatLng> points) {
    double total = 0;
    for (int i = 1; i < points.length; i++) {
      total += _haversineNm(
        points[i - 1].latitude,
        points[i - 1].longitude,
        points[i].latitude,
        points[i].longitude,
      );
    }
    return total;
  }
}
