import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/route_model.dart';
import '../models/waypoint.dart';
import '../repositories/waypoint_repository.dart';
import '../repositories/route_repository.dart';
import '../../core/nav/xte.dart';
import '../../core/nav/route_nav.dart';
import 'vessel_provider.dart';

final waypointRepositoryProvider = Provider<WaypointRepository>((ref) {
  return WaypointRepository();
});

final routeRepositoryProvider = Provider<RouteRepository>((ref) {
  return RouteRepository(ref.read(waypointRepositoryProvider));
});

/// All waypoints from the database.
final waypointsProvider =
    StateNotifierProvider<WaypointListNotifier, List<Waypoint>>((ref) {
  return WaypointListNotifier(ref.read(waypointRepositoryProvider));
});

class WaypointListNotifier extends StateNotifier<List<Waypoint>> {
  final WaypointRepository _repo;

  WaypointListNotifier(this._repo) : super([]) {
    load();
  }

  Future<void> load() async {
    state = await _repo.getAll();
  }

  Future<Waypoint> add(Waypoint waypoint) async {
    final saved = await _repo.insert(waypoint);
    state = [saved, ...state];
    return saved;
  }

  Future<void> update(Waypoint waypoint) async {
    await _repo.update(waypoint);
    state = [
      for (final wp in state)
        if (wp.id == waypoint.id) waypoint else wp,
    ];
  }

  Future<void> remove(int id) async {
    await _repo.delete(id);
    state = state.where((wp) => wp.id != id).toList();
  }
}

/// All routes from the database.
final routesProvider =
    StateNotifierProvider<RouteListNotifier, List<RouteModel>>((ref) {
  return RouteListNotifier(ref.read(routeRepositoryProvider));
});

class RouteListNotifier extends StateNotifier<List<RouteModel>> {
  final RouteRepository _repo;

  RouteListNotifier(this._repo) : super([]) {
    load();
  }

  Future<void> load() async {
    state = await _repo.getAll();
  }

  Future<RouteModel> add(RouteModel route) async {
    final saved = await _repo.insert(route);
    state = [saved, ...state];
    return saved;
  }

  Future<void> update(RouteModel route) async {
    await _repo.update(route);
    state = [
      for (final r in state)
        if (r.id == route.id) route else r,
    ];
  }

  Future<void> remove(int id) async {
    await _repo.delete(id);
    state = state.where((r) => r.id != id).toList();
  }

  Future<void> setActive(int routeId) async {
    await _repo.setActive(routeId);
    state = [
      for (final r in state)
        r.copyWith(isActive: r.id == routeId),
    ];
  }

  Future<void> deactivateAll() async {
    await _repo.deactivateAll();
    state = [
      for (final r in state) r.copyWith(isActive: false),
    ];
  }
}

/// The currently active route (null if none).
final activeRouteProvider = Provider<RouteModel?>((ref) {
  final routes = ref.watch(routesProvider);
  try {
    return routes.firstWhere((r) => r.isActive);
  } catch (_) {
    return null;
  }
});

/// Index of the next waypoint the vessel is heading toward.
final nextWaypointIndexProvider = StateProvider<int>((ref) => 0);

/// Navigation data for the active route leg.
final routeNavProvider = Provider<RouteNavData?>((ref) {
  final route = ref.watch(activeRouteProvider);
  final vessel = ref.watch(vesselProvider);
  final nextIdx = ref.watch(nextWaypointIndexProvider);

  if (route == null || route.waypoints.isEmpty || vessel.position == null) {
    return null;
  }

  final wps = route.waypoints;
  final idx = nextIdx.clamp(0, wps.length - 1);
  final currentPos = vessel.position!;
  final nextWp = wps[idx];

  // XTE: from previous waypoint (or start) to next waypoint
  final fromWp = idx > 0 ? wps[idx - 1].position : currentPos;
  final xteNm = crossTrackErrorNm(fromWp, nextWp.position, currentPos);

  final bearing = bearingToWaypoint(currentPos, nextWp.position);
  final distNm = distanceToWaypointNm(currentPos, nextWp.position);
  final eta = etaToWaypoint(currentPos, nextWp.position, vessel.sog ?? 0);

  final remainingNm = remainingRouteDistanceNm(
    currentPos,
    wps.map((w) => w.position).toList(),
    idx,
  );

  return RouteNavData(
    xteNm: xteNm,
    bearingToNextDeg: bearing,
    distanceToNextNm: distNm,
    etaToNext: eta,
    remainingDistanceNm: remainingNm,
    nextWaypointIndex: idx,
    nextWaypointName: nextWp.name,
  );
});

class RouteNavData {
  final double xteNm;
  final double bearingToNextDeg;
  final double distanceToNextNm;
  final Duration? etaToNext;
  final double remainingDistanceNm;
  final int nextWaypointIndex;
  final String nextWaypointName;

  const RouteNavData({
    required this.xteNm,
    required this.bearingToNextDeg,
    required this.distanceToNextNm,
    this.etaToNext,
    required this.remainingDistanceNm,
    required this.nextWaypointIndex,
    required this.nextWaypointName,
  });
}
