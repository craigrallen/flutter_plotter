import 'package:latlong2/latlong.dart';

class Waypoint {
  final int? id;
  final String name;
  final LatLng position;
  final String? notes;
  final DateTime createdAt;

  const Waypoint({
    this.id,
    required this.name,
    required this.position,
    this.notes,
    required this.createdAt,
  });

  Waypoint copyWith({
    int? id,
    String? name,
    LatLng? position,
    String? notes,
    DateTime? createdAt,
  }) {
    return Waypoint(
      id: id ?? this.id,
      name: name ?? this.name,
      position: position ?? this.position,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'latitude': position.latitude,
      'longitude': position.longitude,
      'notes': notes,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory Waypoint.fromMap(Map<String, dynamic> map) {
    return Waypoint(
      id: map['id'] as int,
      name: map['name'] as String,
      position: LatLng(
        map['latitude'] as double,
        map['longitude'] as double,
      ),
      notes: map['notes'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
