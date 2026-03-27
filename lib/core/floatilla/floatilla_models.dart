import 'package:latlong2/latlong.dart';

class FloatillaUser {
  final String id;
  final String username;
  final String vesselName;
  final LatLng? position;
  final DateTime? lastSeen;
  final bool isOnline;

  const FloatillaUser({
    required this.id,
    required this.username,
    required this.vesselName,
    this.position,
    this.lastSeen,
    this.isOnline = false,
  });

  factory FloatillaUser.fromJson(Map<String, dynamic> json) {
    return FloatillaUser(
      id: json['id'].toString(),
      username: json['username'] as String,
      vesselName: (json['vesselName'] ?? json['vessel_name'] ?? '') as String,
      position: json['lat'] != null && json['lng'] != null
          ? LatLng(
              (json['lat'] as num).toDouble(),
              (json['lng'] as num).toDouble(),
            )
          : null,
      lastSeen: json['lastSeen'] != null
          ? DateTime.tryParse(json['lastSeen'] as String)
          : null,
      isOnline: json['isOnline'] as bool? ?? false,
    );
  }
}

class FloatillaMessage {
  final String id;
  final String authorId;
  final String authorUsername;
  final String text;
  final LatLng? position;
  final DateTime createdAt;

  const FloatillaMessage({
    required this.id,
    required this.authorId,
    required this.authorUsername,
    required this.text,
    this.position,
    required this.createdAt,
  });

  factory FloatillaMessage.fromJson(Map<String, dynamic> json) {
    return FloatillaMessage(
      id: json['id'].toString(),
      authorId: json['authorId'] as String,
      authorUsername: json['authorUsername'] as String,
      text: json['text'] as String,
      position: json['lat'] != null && json['lng'] != null
          ? LatLng(
              (json['lat'] as num).toDouble(),
              (json['lng'] as num).toDouble(),
            )
          : null,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}

class FloatillaWaypoint {
  final String id;
  final String fromUserId;
  final String fromUsername;
  final LatLng position;
  final String name;
  final String? description;
  final DateTime createdAt;

  const FloatillaWaypoint({
    required this.id,
    required this.fromUserId,
    required this.fromUsername,
    required this.position,
    required this.name,
    this.description,
    required this.createdAt,
  });

  factory FloatillaWaypoint.fromJson(Map<String, dynamic> json) {
    return FloatillaWaypoint(
      id: json['id'].toString(),
      fromUserId: json['fromUserId'] as String,
      fromUsername: json['fromUsername'] as String,
      position: LatLng(
        (json['lat'] as num).toDouble(),
        (json['lng'] as num).toDouble(),
      ),
      name: json['name'] as String,
      description: json['description'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}

class MobAlert {
  final String userId;
  final String username;
  final String vesselName;
  final LatLng position;
  final DateTime triggeredAt;

  const MobAlert({
    required this.userId,
    required this.username,
    required this.vesselName,
    required this.position,
    required this.triggeredAt,
  });

  factory MobAlert.fromJson(Map<String, dynamic> json) {
    return MobAlert(
      userId: json['userId'] as String,
      username: json['username'] as String,
      vesselName: (json['vesselName'] ?? json['vessel_name'] ?? '') as String,
      position: LatLng(
        (json['lat'] as num).toDouble(),
        (json['lng'] as num).toDouble(),
      ),
      triggeredAt: DateTime.parse(json['triggeredAt'] as String),
    );
  }
}

// ── Friend request ────────────────────────────────────────

class FloatillaFriendRequest {
  final int friendshipId;
  final String userId;
  final String username;
  final String vesselName;

  const FloatillaFriendRequest({
    required this.friendshipId,
    required this.userId,
    required this.username,
    required this.vesselName,
  });

  factory FloatillaFriendRequest.fromJson(Map<String, dynamic> json) {
    return FloatillaFriendRequest(
      friendshipId: json['friendship_id'] is int
          ? json['friendship_id'] as int
          : int.parse(json['friendship_id'].toString()),
      userId: json['id'].toString(),
      username: json['username'] as String,
      vesselName: json['vessel_name'] as String? ?? '',
    );
  }
}
