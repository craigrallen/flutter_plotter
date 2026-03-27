import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../../core/floatilla/floatilla_models.dart';
import '../../core/floatilla/floatilla_service.dart';
import '../../data/models/route_model.dart';
import '../../data/models/waypoint.dart';
import 'route_provider.dart';
import 'vessel_provider.dart';

// ── Service singleton ───────────────────────────────────────

final floatillaServiceProvider = Provider<FloatillaService>((ref) {
  return FloatillaService.instance;
});

// ── Auth state ──────────────────────────────────────────────

final isLoggedInProvider = StateProvider<bool>((ref) {
  return ref.watch(floatillaServiceProvider).isLoggedIn();
});

// ── Friends ─────────────────────────────────────────────────

class FriendsNotifier extends StateNotifier<AsyncValue<List<FloatillaUser>>> {
  final FloatillaService _service;

  FriendsNotifier(this._service) : super(const AsyncValue.loading()) {
    _load();
  }

  Future<void> _load() async {
    if (!_service.isLoggedIn()) {
      state = const AsyncValue.data([]);
      return;
    }
    try {
      final friends = await _service.getFriends();
      state = AsyncValue.data(friends);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> refresh() => _load();

  void updateFromWs(FloatillaUser updated) {
    final current = state.valueOrNull ?? [];
    final idx = current.indexWhere((f) => f.id == updated.id);
    if (idx >= 0) {
      final list = [...current];
      list[idx] = updated;
      state = AsyncValue.data(list);
    } else {
      state = AsyncValue.data([...current, updated]);
    }
  }
}

final friendsProvider =
    StateNotifierProvider<FriendsNotifier, AsyncValue<List<FloatillaUser>>>(
        (ref) {
  return FriendsNotifier(ref.watch(floatillaServiceProvider));
});

// ── Messages ────────────────────────────────────────────────

class MessagesNotifier
    extends StateNotifier<AsyncValue<List<FloatillaMessage>>> {
  final FloatillaService _service;

  MessagesNotifier(this._service) : super(const AsyncValue.loading()) {
    _load();
  }

  Future<void> _load() async {
    if (!_service.isLoggedIn()) {
      state = const AsyncValue.data([]);
      return;
    }
    try {
      final msgs = await _service.getMessages();
      state = AsyncValue.data(msgs);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> refresh() => _load();

  void prepend(FloatillaMessage msg) {
    final current = state.valueOrNull ?? [];
    state = AsyncValue.data([msg, ...current]);
  }
}

final messagesProvider = StateNotifierProvider<MessagesNotifier,
    AsyncValue<List<FloatillaMessage>>>((ref) {
  return MessagesNotifier(ref.watch(floatillaServiceProvider));
});

// ── MoB Alert ───────────────────────────────────────────────

final mobAlertProvider = StateProvider<MobAlert?>((ref) => null);

// ── Pending Waypoints ───────────────────────────────────────

final pendingWaypointsProvider =
    StateProvider<List<FloatillaWaypoint>>((ref) => []);

// ── Cloud Sync ──────────────────────────────────────────────

enum CloudSyncStatus { idle, syncing, success, error }

class CloudSyncState {
  final CloudSyncStatus status;
  final String? message;
  const CloudSyncState({this.status = CloudSyncStatus.idle, this.message});
}

class CloudSyncNotifier extends StateNotifier<CloudSyncState> {
  final FloatillaService _service;
  final Ref _ref;

  CloudSyncNotifier(this._service, this._ref)
      : super(const CloudSyncState());

  Future<void> backup() async {
    if (!_service.isLoggedIn()) {
      state = const CloudSyncState(
          status: CloudSyncStatus.error,
          message: 'Sign in to Floatilla to backup');
      return;
    }
    state = const CloudSyncState(status: CloudSyncStatus.syncing);

    // Serialise routes
    final routes = _ref.read(routesProvider);
    final routePayload = routes.map((r) => {
          'name': r.name,
          'isActive': r.isActive,
          'createdAt': r.createdAt.toIso8601String(),
          'waypoints': r.waypoints
              .map((w) => {
                    'name': w.name,
                    'lat': w.position.latitude,
                    'lng': w.position.longitude,
                    'notes': w.notes,
                    'createdAt': w.createdAt.toIso8601String(),
                  })
              .toList(),
        }).toList();

    // Serialise standalone waypoints
    final waypoints = _ref.read(waypointsProvider);
    final waypointPayload = waypoints
        .map((w) => {
              'name': w.name,
              'lat': w.position.latitude,
              'lng': w.position.longitude,
              'notes': w.notes,
              'createdAt': w.createdAt.toIso8601String(),
            })
        .toList();

    final ok1 = await _service.uploadRoutes(routePayload);
    final ok2 = await _service.uploadWaypoints(waypointPayload);

    if (ok1 && ok2) {
      state = CloudSyncState(
          status: CloudSyncStatus.success,
          message:
              'Backed up ${routes.length} routes, ${waypoints.length} waypoints');
    } else {
      state = const CloudSyncState(
          status: CloudSyncStatus.error, message: 'Backup failed');
    }
  }

  Future<void> restore() async {
    if (!_service.isLoggedIn()) {
      state = const CloudSyncState(
          status: CloudSyncStatus.error,
          message: 'Sign in to Floatilla to restore');
      return;
    }
    state = const CloudSyncState(status: CloudSyncStatus.syncing);

    final routeData = await _service.downloadRoutes();
    final waypointData = await _service.downloadWaypoints();

    if (routeData == null || waypointData == null) {
      state = const CloudSyncState(
          status: CloudSyncStatus.error, message: 'Restore failed');
      return;
    }

    // Restore standalone waypoints first
    final rawWps = (waypointData['waypoints'] as List?) ?? [];
    var wpCount = 0;
    for (final raw in rawWps) {
      final m = raw as Map<String, dynamic>;
      try {
        await _ref.read(waypointsProvider.notifier).add(Waypoint(
              name: m['name'] as String? ?? 'Waypoint',
              position: LatLng(
                (m['lat'] as num).toDouble(),
                (m['lng'] as num).toDouble(),
              ),
              notes: m['notes'] as String?,
              createdAt: DateTime.tryParse(m['createdAt'] as String? ?? '') ??
                  DateTime.now(),
            ));
        wpCount++;
      } catch (_) {}
    }

    // Restore routes (each route's waypoints are embedded)
    final rawRoutes = (routeData['routes'] as List?) ?? [];
    var routeCount = 0;
    for (final raw in rawRoutes) {
      final m = raw as Map<String, dynamic>;
      try {
        final rawRouteWps = (m['waypoints'] as List?) ?? [];
        final savedWps = <Waypoint>[];
        for (final rwp in rawRouteWps) {
          final wm = rwp as Map<String, dynamic>;
          final saved =
              await _ref.read(waypointsProvider.notifier).add(Waypoint(
                    name: wm['name'] as String? ?? 'WP',
                    position: LatLng(
                      (wm['lat'] as num).toDouble(),
                      (wm['lng'] as num).toDouble(),
                    ),
                    notes: wm['notes'] as String?,
                    createdAt:
                        DateTime.tryParse(wm['createdAt'] as String? ?? '') ??
                            DateTime.now(),
                  ));
          savedWps.add(saved);
        }
        await _ref.read(routesProvider.notifier).add(RouteModel(
              name: m['name'] as String? ?? 'Route',
              waypoints: savedWps,
              createdAt: DateTime.tryParse(m['createdAt'] as String? ?? '') ??
                  DateTime.now(),
            ));
        routeCount++;
      } catch (_) {}
    }

    state = CloudSyncState(
        status: CloudSyncStatus.success,
        message: 'Restored $routeCount routes, $wpCount waypoints');
  }

  void reset() {
    state = const CloudSyncState();
  }
}

final cloudSyncProvider =
    StateNotifierProvider<CloudSyncNotifier, CloudSyncState>((ref) {
  return CloudSyncNotifier(ref.watch(floatillaServiceProvider), ref);
});

// ── Floatilla settings ──────────────────────────────────────

final floatillaAutoShareProvider = StateProvider<bool>((ref) => false);
final floatillaServerUrlProvider =
    StateProvider<String>((ref) => 'https://fleet.floatilla.app');

// ── Background location sharing ─────────────────────────────

final floatillaLocationSharingProvider = Provider<void>((ref) {
  final autoShare = ref.watch(floatillaAutoShareProvider);
  final service = ref.watch(floatillaServiceProvider);
  if (!autoShare || !service.isLoggedIn()) return;

  Timer? timer;
  timer = Timer.periodic(const Duration(seconds: 60), (_) {
    final vessel = ref.read(vesselProvider);
    if (vessel.position != null &&
        vessel.sog != null &&
        vessel.sog! > 0.5) {
      service.updateLocation(
        vessel.position!,
        vessel.sog!,
        vessel.cog ?? 0,
      );
    }
  });

  ref.onDispose(() => timer?.cancel());
});

// ── WebSocket event wiring ──────────────────────────────────

final floatillaWsWiringProvider = Provider<void>((ref) {
  final service = ref.watch(floatillaServiceProvider);
  if (!service.isLoggedIn()) return;

  service.onMessage = (json) {
    try {
      final data = json['data'] as Map<String, dynamic>? ?? json;
      final msg = FloatillaMessage.fromJson(data);
      ref.read(messagesProvider.notifier).prepend(msg);
    } catch (_) {}
  };

  service.onFriendUpdate = (json) {
    try {
      final data = json['data'] as Map<String, dynamic>? ?? json;
      final user = FloatillaUser.fromJson(data);
      ref.read(friendsProvider.notifier).updateFromWs(user);
    } catch (_) {}
  };

  service.onWaypointShared = (json) {
    try {
      final data = json['data'] as Map<String, dynamic>? ?? json;
      final wp = FloatillaWaypoint.fromJson(data);
      final current = ref.read(pendingWaypointsProvider);
      ref.read(pendingWaypointsProvider.notifier).state = [...current, wp];
    } catch (_) {}
  };

  service.onMobAlert = (json) {
    try {
      final data = json['data'] as Map<String, dynamic>? ?? json;
      final alert = MobAlert.fromJson(data);
      ref.read(mobAlertProvider.notifier).state = alert;
    } catch (_) {}
  };

  ref.onDispose(() {
    service.onMessage = null;
    service.onFriendUpdate = null;
    service.onWaypointShared = null;
    service.onMobAlert = null;
  });
});
