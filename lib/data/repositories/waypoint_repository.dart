import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import '../models/waypoint.dart';

class WaypointRepository {
  static Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'flutter_plotter.db');
    return openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE waypoints (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            latitude REAL NOT NULL,
            longitude REAL NOT NULL,
            notes TEXT,
            created_at TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE routes (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            is_active INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE route_waypoints (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            route_id INTEGER NOT NULL,
            waypoint_id INTEGER NOT NULL,
            sort_order INTEGER NOT NULL,
            FOREIGN KEY (route_id) REFERENCES routes(id) ON DELETE CASCADE,
            FOREIGN KEY (waypoint_id) REFERENCES waypoints(id) ON DELETE CASCADE
          )
        ''');
      },
    );
  }

  Future<List<Waypoint>> getAll() async {
    final db = await database;
    final maps = await db.query('waypoints', orderBy: 'created_at DESC');
    return maps.map((m) => Waypoint.fromMap(m)).toList();
  }

  Future<Waypoint?> getById(int id) async {
    final db = await database;
    final maps = await db.query('waypoints', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    return Waypoint.fromMap(maps.first);
  }

  Future<Waypoint> insert(Waypoint waypoint) async {
    final db = await database;
    final id = await db.insert('waypoints', waypoint.toMap());
    return waypoint.copyWith(id: id);
  }

  Future<void> update(Waypoint waypoint) async {
    final db = await database;
    await db.update(
      'waypoints',
      waypoint.toMap(),
      where: 'id = ?',
      whereArgs: [waypoint.id],
    );
  }

  Future<void> delete(int id) async {
    final db = await database;
    await db.delete('waypoints', where: 'id = ?', whereArgs: [id]);
  }
}
