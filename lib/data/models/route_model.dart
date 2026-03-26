import 'waypoint.dart';

class RouteModel {
  final int? id;
  final String name;
  final List<Waypoint> waypoints;
  final bool isActive;
  final DateTime createdAt;

  const RouteModel({
    this.id,
    required this.name,
    this.waypoints = const [],
    this.isActive = false,
    required this.createdAt,
  });

  RouteModel copyWith({
    int? id,
    String? name,
    List<Waypoint>? waypoints,
    bool? isActive,
    DateTime? createdAt,
  }) {
    return RouteModel(
      id: id ?? this.id,
      name: name ?? this.name,
      waypoints: waypoints ?? this.waypoints,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'is_active': isActive ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory RouteModel.fromMap(Map<String, dynamic> map, List<Waypoint> waypoints) {
    return RouteModel(
      id: map['id'] as int,
      name: map['name'] as String,
      waypoints: waypoints,
      isActive: (map['is_active'] as int) == 1,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
