import 'package:sqflite/sqflite.dart';
import '../models/route_model.dart';
import '../models/waypoint.dart';
import 'waypoint_repository.dart';

class RouteRepository {
  final WaypointRepository _waypointRepo;

  RouteRepository(this._waypointRepo);

  Future<Database> get _db => _waypointRepo.database;

  Future<List<RouteModel>> getAll() async {
    final db = await _db;
    final routeMaps = await db.query('routes', orderBy: 'created_at DESC');
    final routes = <RouteModel>[];
    for (final map in routeMaps) {
      final waypoints = await _getRouteWaypoints(db, map['id'] as int);
      routes.add(RouteModel.fromMap(map, waypoints));
    }
    return routes;
  }

  Future<RouteModel?> getById(int id) async {
    final db = await _db;
    final maps = await db.query('routes', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    final waypoints = await _getRouteWaypoints(db, id);
    return RouteModel.fromMap(maps.first, waypoints);
  }

  Future<RouteModel?> getActive() async {
    final db = await _db;
    final maps = await db.query(
      'routes',
      where: 'is_active = 1',
      limit: 1,
    );
    if (maps.isEmpty) return null;
    final id = maps.first['id'] as int;
    final waypoints = await _getRouteWaypoints(db, id);
    return RouteModel.fromMap(maps.first, waypoints);
  }

  Future<RouteModel> insert(RouteModel route) async {
    final db = await _db;
    final id = await db.insert('routes', route.toMap());
    // Insert waypoint associations
    for (var i = 0; i < route.waypoints.length; i++) {
      await db.insert('route_waypoints', {
        'route_id': id,
        'waypoint_id': route.waypoints[i].id,
        'sort_order': i,
      });
    }
    return route.copyWith(id: id);
  }

  Future<void> update(RouteModel route) async {
    final db = await _db;
    await db.update(
      'routes',
      route.toMap(),
      where: 'id = ?',
      whereArgs: [route.id],
    );
    // Rebuild waypoint associations
    await db.delete(
      'route_waypoints',
      where: 'route_id = ?',
      whereArgs: [route.id],
    );
    for (var i = 0; i < route.waypoints.length; i++) {
      await db.insert('route_waypoints', {
        'route_id': route.id,
        'waypoint_id': route.waypoints[i].id,
        'sort_order': i,
      });
    }
  }

  Future<void> delete(int id) async {
    final db = await _db;
    await db.delete('route_waypoints', where: 'route_id = ?', whereArgs: [id]);
    await db.delete('routes', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> setActive(int routeId) async {
    final db = await _db;
    await db.transaction((txn) async {
      // Deactivate all routes
      await txn.update('routes', {'is_active': 0});
      // Activate the selected route
      await txn.update(
        'routes',
        {'is_active': 1},
        where: 'id = ?',
        whereArgs: [routeId],
      );
    });
  }

  Future<void> deactivateAll() async {
    final db = await _db;
    await db.update('routes', {'is_active': 0});
  }

  Future<List<Waypoint>> _getRouteWaypoints(Database db, int routeId) async {
    final maps = await db.rawQuery('''
      SELECT w.* FROM waypoints w
      INNER JOIN route_waypoints rw ON rw.waypoint_id = w.id
      WHERE rw.route_id = ?
      ORDER BY rw.sort_order ASC
    ''', [routeId]);
    return maps.map((m) => Waypoint.fromMap(m)).toList();
  }
}
