import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'floatilla_service.dart';

class AnchorageInfo {
  final String id;
  final double lat;
  final double lng;
  final String name;
  final int boatCount;
  final List<AnchoredBoat> boats;
  final AnchorageReview? lastReview;

  const AnchorageInfo({
    required this.id,
    required this.lat,
    required this.lng,
    required this.name,
    required this.boatCount,
    required this.boats,
    this.lastReview,
  });

  LatLng get position => LatLng(lat, lng);

  factory AnchorageInfo.fromJson(Map<String, dynamic> j) => AnchorageInfo(
        id: j['id'].toString(),
        lat: (j['lat'] as num).toDouble(),
        lng: (j['lng'] as num).toDouble(),
        name: (j['name'] as String?) ?? 'Anchorage',
        boatCount: (j['boat_count'] as num?)?.toInt() ?? 0,
        boats: (j['boats'] as List<dynamic>? ?? [])
            .map((e) => AnchoredBoat.fromJson(e as Map<String, dynamic>))
            .toList(),
        lastReview: j['last_review'] != null
            ? AnchorageReview.fromJson(j['last_review'] as Map<String, dynamic>)
            : null,
      );
}

class AnchoredBoat {
  final String username;
  final String vesselName;
  final DateTime checkedInAt;

  const AnchoredBoat({
    required this.username,
    required this.vesselName,
    required this.checkedInAt,
  });

  factory AnchoredBoat.fromJson(Map<String, dynamic> j) => AnchoredBoat(
        username: (j['username'] as String?) ?? '',
        vesselName: (j['vessel_name'] ?? j['vesselName'] ?? '') as String,
        checkedInAt: DateTime.fromMillisecondsSinceEpoch(
          ((j['checked_in_at'] as num?) ?? 0).toInt() * 1000,
        ),
      );
}

class AnchorageReview {
  final String text;
  final double rating;
  final DateTime timestamp;

  const AnchorageReview({
    required this.text,
    required this.rating,
    required this.timestamp,
  });

  factory AnchorageReview.fromJson(Map<String, dynamic> j) => AnchorageReview(
        text: (j['text'] as String?) ?? '',
        rating: (j['rating'] as num?)?.toDouble() ?? 0,
        timestamp: DateTime.fromMillisecondsSinceEpoch(
          ((j['timestamp'] as num?) ?? 0).toInt() * 1000,
        ),
      );
}

class HazardReport {
  final String id;
  final double lat;
  final double lng;
  final String type;
  final String? description;
  final String? reporterUsername;
  final DateTime createdAt;
  final int confirmedCount;

  const HazardReport({
    required this.id,
    required this.lat,
    required this.lng,
    required this.type,
    this.description,
    this.reporterUsername,
    required this.createdAt,
    required this.confirmedCount,
  });

  LatLng get position => LatLng(lat, lng);

  Duration get age => DateTime.now().difference(createdAt);

  String get ageLabel {
    final h = age.inHours;
    if (h < 1) return '${age.inMinutes}min ago';
    if (h < 24) return '${h}h ago';
    return '${age.inDays}d ago';
  }

  factory HazardReport.fromJson(Map<String, dynamic> j) => HazardReport(
        id: j['id'].toString(),
        lat: (j['lat'] as num).toDouble(),
        lng: (j['lng'] as num).toDouble(),
        type: (j['type'] as String?) ?? 'other',
        description: j['description'] as String?,
        reporterUsername: j['username'] as String?,
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          ((j['created_at'] as num?) ?? 0).toInt() * 1000,
        ),
        confirmedCount: (j['confirmed_count'] as num?)?.toInt() ?? 0,
      );
}

class AnchorageService {
  AnchorageService._();
  static final instance = AnchorageService._();

  String get _base => FloatillaService.instance.baseUrl;
  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (FloatillaService.instance.token != null)
          'Authorization': 'Bearer ${FloatillaService.instance.token}',
      };

  Future<List<AnchorageInfo>> nearbyAnchorages(
    LatLng center, {
    double radiusNm = 5,
  }) async {
    try {
      final uri = Uri.parse('$_base/anchorages/nearby').replace(
        queryParameters: {
          'lat': center.latitude.toString(),
          'lng': center.longitude.toString(),
          'radiusNm': radiusNm.toString(),
        },
      );
      final resp = await http.get(uri, headers: _headers);
      if (resp.statusCode != 200) return [];
      final list = jsonDecode(resp.body) as List;
      return list
          .map((e) => AnchorageInfo.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<bool> checkin(LatLng pos, {String? name}) async {
    try {
      final resp = await http.post(
        Uri.parse('$_base/anchorages/checkin'),
        headers: _headers,
        body: jsonEncode({
          'lat': pos.latitude,
          'lng': pos.longitude,
          if (name != null) 'name': name,
        }),
      );
      return resp.statusCode == 200 || resp.statusCode == 201;
    } catch (_) {
      return false;
    }
  }

  Future<bool> checkout() async {
    try {
      final resp = await http.post(
        Uri.parse('$_base/anchorages/checkout'),
        headers: _headers,
        body: jsonEncode({}),
      );
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<List<HazardReport>> nearbyHazards(
    LatLng center, {
    double radiusNm = 20,
  }) async {
    try {
      final uri = Uri.parse('$_base/hazards/nearby').replace(
        queryParameters: {
          'lat': center.latitude.toString(),
          'lng': center.longitude.toString(),
          'radiusNm': radiusNm.toString(),
        },
      );
      final resp = await http.get(uri, headers: _headers);
      if (resp.statusCode != 200) return [];
      final list = jsonDecode(resp.body) as List;
      return list
          .map((e) => HazardReport.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<bool> reportHazard({
    required LatLng pos,
    required String type,
    String? description,
  }) async {
    try {
      final resp = await http.post(
        Uri.parse('$_base/hazards'),
        headers: _headers,
        body: jsonEncode({
          'lat': pos.latitude,
          'lng': pos.longitude,
          'type': type,
          if (description != null && description.isNotEmpty)
            'description': description,
        }),
      );
      return resp.statusCode == 200 || resp.statusCode == 201;
    } catch (_) {
      return false;
    }
  }

  Future<bool> confirmHazard(String hazardId) async {
    try {
      final resp = await http.post(
        Uri.parse('$_base/hazards/$hazardId/confirm'),
        headers: _headers,
        body: jsonEncode({}),
      );
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
