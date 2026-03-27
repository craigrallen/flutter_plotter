import 'package:latlong2/latlong.dart';

class TideStation {
  final String id;
  final String name;
  final LatLng position;
  final String type; // "R" reference, "S" subordinate

  const TideStation({
    required this.id,
    required this.name,
    required this.position,
    required this.type,
  });

  factory TideStation.fromJson(Map<String, dynamic> json) {
    return TideStation(
      id: json['id'] as String,
      name: json['name'] as String,
      position: LatLng(
        double.parse(json['lat'] as String),
        double.parse(json['lng'] as String),
      ),
      type: (json['type'] as String?) ?? 'R',
    );
  }
}
