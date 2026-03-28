import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:path/path.dart' as path_pkg;
import 'package:sqflite/sqflite.dart';
import 'floatilla_service.dart';

// ── Events ──────────────────────────────────────────────────────────────────

abstract class VoyageEvent {}

class VoyageStartedEvent extends VoyageEvent {
  final String voyageId;
  final DateTime startTime;
  VoyageStartedEvent({required this.voyageId, required this.startTime});
}

class VoyageEntryEvent extends VoyageEvent {
  final VoyageLogEntry entry;
  VoyageEntryEvent(this.entry);
}

class VoyageEndedEvent extends VoyageEvent {
  final String voyageId;
  final VoyageStats stats;
  VoyageEndedEvent({required this.voyageId, required this.stats});
}

// ── Models ───────────────────────────────────────────────────────────────────

class VoyageLogEntry {
  final int? id;
  final String voyageId;
  final DateTime timestamp;
  final double? lat;
  final double? lng;
  final double? cog;
  final double? sog;
  final double? tws;
  final double? twd;
  final double? awa;
  final double? aws;
  final double? depth;
  final double? heading;
  final double? engineRpm;
  final double? batteryVoltage;

  const VoyageLogEntry({
    this.id,
    required this.voyageId,
    required this.timestamp,
    this.lat,
    this.lng,
    this.cog,
    this.sog,
    this.tws,
    this.twd,
    this.awa,
    this.aws,
    this.depth,
    this.heading,
    this.engineRpm,
    this.batteryVoltage,
  });

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'voyage_id': voyageId,
        'timestamp': timestamp.millisecondsSinceEpoch,
        if (lat != null) 'lat': lat,
        if (lng != null) 'lng': lng,
        if (cog != null) 'cog': cog,
        if (sog != null) 'sog': sog,
        if (tws != null) 'tws': tws,
        if (twd != null) 'twd': twd,
        if (awa != null) 'awa': awa,
        if (aws != null) 'aws': aws,
        if (depth != null) 'depth': depth,
        if (heading != null) 'heading': heading,
        if (engineRpm != null) 'engine_rpm': engineRpm,
        if (batteryVoltage != null) 'battery_voltage': batteryVoltage,
      };

  factory VoyageLogEntry.fromMap(Map<String, dynamic> m) => VoyageLogEntry(
        id: m['id'] as int?,
        voyageId: m['voyage_id'] as String,
        timestamp: DateTime.fromMillisecondsSinceEpoch(m['timestamp'] as int),
        lat: (m['lat'] as num?)?.toDouble(),
        lng: (m['lng'] as num?)?.toDouble(),
        cog: (m['cog'] as num?)?.toDouble(),
        sog: (m['sog'] as num?)?.toDouble(),
        tws: (m['tws'] as num?)?.toDouble(),
        twd: (m['twd'] as num?)?.toDouble(),
        awa: (m['awa'] as num?)?.toDouble(),
        aws: (m['aws'] as num?)?.toDouble(),
        depth: (m['depth'] as num?)?.toDouble(),
        heading: (m['heading'] as num?)?.toDouble(),
        engineRpm: (m['engine_rpm'] as num?)?.toDouble(),
        batteryVoltage: (m['battery_voltage'] as num?)?.toDouble(),
      );

  Map<String, dynamic> toJson() => toMap();
}

class VoyageRecord {
  final String voyageId;
  final DateTime startTime;
  DateTime? endTime;
  final List<VoyageLogEntry> entries;

  VoyageRecord({
    required this.voyageId,
    required this.startTime,
    this.endTime,
    List<VoyageLogEntry>? entries,
  }) : entries = entries ?? [];

  Map<String, dynamic> toMap() => {
        'voyage_id': voyageId,
        'start_time': startTime.millisecondsSinceEpoch,
        if (endTime != null) 'end_time': endTime!.millisecondsSinceEpoch,
      };

  factory VoyageRecord.fromMap(Map<String, dynamic> m) => VoyageRecord(
        voyageId: m['voyage_id'] as String,
        startTime:
            DateTime.fromMillisecondsSinceEpoch(m['start_time'] as int),
        endTime: m['end_time'] != null
            ? DateTime.fromMillisecondsSinceEpoch(m['end_time'] as int)
            : null,
      );
}

class VoyageStats {
  final String voyageId;
  final DateTime startTime;
  final DateTime? endTime;
  final double distanceNm;
  final double avgSog;
  final double maxSog;
  final double? avgTws;
  final int entryCount;
  final LatLng? startPosition;
  final LatLng? endPosition;

  const VoyageStats({
    required this.voyageId,
    required this.startTime,
    this.endTime,
    required this.distanceNm,
    required this.avgSog,
    required this.maxSog,
    this.avgTws,
    required this.entryCount,
    this.startPosition,
    this.endPosition,
  });

  Duration get duration {
    final end = endTime ?? DateTime.now();
    return end.difference(startTime);
  }
}

// ── Settings ─────────────────────────────────────────────────────────────────

enum LogInterval { thirtySeconds, oneMinute, fiveMinutes }

enum DetectionSensitivity { slow, normal, fast }

class VoyageLoggerSettings {
  final LogInterval interval;
  final DetectionSensitivity sensitivity;
  final bool autoDetect;

  const VoyageLoggerSettings({
    this.interval = LogInterval.oneMinute,
    this.sensitivity = DetectionSensitivity.normal,
    this.autoDetect = true,
  });

  Duration get intervalDuration {
    switch (interval) {
      case LogInterval.thirtySeconds:
        return const Duration(seconds: 30);
      case LogInterval.oneMinute:
        return const Duration(minutes: 1);
      case LogInterval.fiveMinutes:
        return const Duration(minutes: 5);
    }
  }

  /// Consecutive high-SOG readings needed to START a voyage.
  int get startThreshold {
    switch (sensitivity) {
      case DetectionSensitivity.slow:
        return 5;
      case DetectionSensitivity.normal:
        return 3;
      case DetectionSensitivity.fast:
        return 2;
    }
  }

  /// Consecutive low-SOG readings needed to END a voyage.
  int get stopThreshold {
    switch (sensitivity) {
      case DetectionSensitivity.slow:
        return 15;
      case DetectionSensitivity.normal:
        return 10;
      case DetectionSensitivity.fast:
        return 5;
    }
  }

  VoyageLoggerSettings copyWith({
    LogInterval? interval,
    DetectionSensitivity? sensitivity,
    bool? autoDetect,
  }) =>
      VoyageLoggerSettings(
        interval: interval ?? this.interval,
        sensitivity: sensitivity ?? this.sensitivity,
        autoDetect: autoDetect ?? this.autoDetect,
      );
}

// ── State ─────────────────────────────────────────────────────────────────────

class VoyageLoggerState {
  final bool isVoyageActive;
  final String? currentVoyageId;
  final VoyageStats? currentVoyageStats;
  final List<VoyageRecord> pastVoyages;
  final VoyageLoggerSettings settings;
  final bool isRunning;
  final double? currentSog;

  const VoyageLoggerState({
    this.isVoyageActive = false,
    this.currentVoyageId,
    this.currentVoyageStats,
    this.pastVoyages = const [],
    this.settings = const VoyageLoggerSettings(),
    this.isRunning = false,
    this.currentSog,
  });

  VoyageLoggerState copyWith({
    bool? isVoyageActive,
    String? currentVoyageId,
    VoyageStats? currentVoyageStats,
    List<VoyageRecord>? pastVoyages,
    VoyageLoggerSettings? settings,
    bool? isRunning,
    double? currentSog,
    bool clearCurrentVoyage = false,
  }) =>
      VoyageLoggerState(
        isVoyageActive: isVoyageActive ?? this.isVoyageActive,
        currentVoyageId:
            clearCurrentVoyage ? null : (currentVoyageId ?? this.currentVoyageId),
        currentVoyageStats: clearCurrentVoyage
            ? null
            : (currentVoyageStats ?? this.currentVoyageStats),
        pastVoyages: pastVoyages ?? this.pastVoyages,
        settings: settings ?? this.settings,
        isRunning: isRunning ?? this.isRunning,
        currentSog: currentSog ?? this.currentSog,
      );
}

// ── Service ───────────────────────────────────────────────────────────────────

/// Captures vessel data at regular intervals and auto-detects voyage start/end.
///
/// Voyage start: SOG > 2 kn for [settings.startThreshold] consecutive readings.
/// Voyage end:   SOG < 0.5 kn for [settings.stopThreshold] consecutive readings.
class VoyageLoggerService {
  VoyageLoggerService._();
  static final instance = VoyageLoggerService._();

  static const double _startSogKn = 2.0;
  static const double _stopSogKn = 0.5;

  // ── Internal state ──────────────────────────────────────────────────────

  final _controller = StreamController<VoyageEvent>.broadcast();
  Stream<VoyageEvent> get events => _controller.stream;

  Database? _db;
  Timer? _timer;

  bool _running = false;
  VoyageLoggerSettings _settings = const VoyageLoggerSettings();

  // Auto-detect counters
  int _highSogCount = 0;
  int _lowSogCount = 0;

  // Current voyage tracking
  String? _currentVoyageId;
  DateTime? _voyageStartTime;
  final List<VoyageLogEntry> _currentEntries = [];

  // Data callback — injected by provider
  Future<VesselSnapshot> Function()? _snapshotCallback;

  bool get isVoyageActive => _currentVoyageId != null;
  String? get currentVoyageId => _currentVoyageId;
  VoyageLoggerSettings get settings => _settings;

  // ── Initialise DB ────────────────────────────────────────────────────────

  Future<void> init({
    required Future<VesselSnapshot> Function() snapshotCallback,
  }) async {
    _snapshotCallback = snapshotCallback;
    await _openDatabase();
  }

  Future<void> _openDatabase() async {
    final dbPath = await getDatabasesPath();
    final fullPath = path_pkg.join(dbPath, 'voyage_logger.db');
    _db = await openDatabase(
      fullPath,
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE voyages (
            voyage_id TEXT PRIMARY KEY,
            start_time INTEGER NOT NULL,
            end_time INTEGER
          )
        ''');
        await db.execute('''
          CREATE TABLE voyage_entries (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            voyage_id TEXT NOT NULL,
            timestamp INTEGER NOT NULL,
            lat REAL,
            lng REAL,
            cog REAL,
            sog REAL,
            tws REAL,
            twd REAL,
            awa REAL,
            aws REAL,
            depth REAL,
            heading REAL,
            engine_rpm REAL,
            battery_voltage REAL,
            FOREIGN KEY(voyage_id) REFERENCES voyages(voyage_id)
          )
        ''');
      },
    );
  }

  // ── Start / Stop logger ──────────────────────────────────────────────────

  void start({VoyageLoggerSettings? settings}) {
    if (_running) return;
    if (settings != null) _settings = settings;
    _running = true;
    _scheduleTimer();
  }

  void stop() {
    _running = false;
    _timer?.cancel();
    _timer = null;
  }

  void updateSettings(VoyageLoggerSettings settings) {
    _settings = settings;
    if (_running) {
      _timer?.cancel();
      _scheduleTimer();
    }
  }

  void _scheduleTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(_settings.intervalDuration, (_) => _tick());
  }

  // ── Manual override ──────────────────────────────────────────────────────

  Future<void> forceStartVoyage() async {
    if (_currentVoyageId != null) return;
    await _beginVoyage();
  }

  Future<void> forceEndVoyage() async {
    if (_currentVoyageId == null) return;
    await _endVoyage();
  }

  // ── Core tick ────────────────────────────────────────────────────────────

  Future<void> _tick() async {
    if (_snapshotCallback == null) return;

    final snapshot = await _snapshotCallback!();
    final sog = snapshot.sog ?? 0.0;

    // Auto-detect
    if (_settings.autoDetect && _currentVoyageId == null) {
      if (sog > _startSogKn) {
        _highSogCount++;
        _lowSogCount = 0;
        if (_highSogCount >= _settings.startThreshold) {
          await _beginVoyage();
          _highSogCount = 0;
        }
      } else {
        _highSogCount = 0;
      }
    }

    if (_currentVoyageId != null) {
      if (_settings.autoDetect) {
        if (sog < _stopSogKn) {
          _lowSogCount++;
          if (_lowSogCount >= _settings.stopThreshold) {
            await _endVoyage();
            _lowSogCount = 0;
            return;
          }
        } else {
          _lowSogCount = 0;
        }
      }

      // Log the entry
      final entry = VoyageLogEntry(
        voyageId: _currentVoyageId!,
        timestamp: snapshot.timestamp,
        lat: snapshot.lat,
        lng: snapshot.lng,
        cog: snapshot.cog,
        sog: snapshot.sog,
        tws: snapshot.tws,
        twd: snapshot.twd,
        awa: snapshot.awa,
        aws: snapshot.aws,
        depth: snapshot.depth,
        heading: snapshot.heading,
        engineRpm: snapshot.engineRpm,
        batteryVoltage: snapshot.batteryVoltage,
      );

      await _insertEntry(entry);
      _currentEntries.add(entry);
      _controller.add(VoyageEntryEvent(entry));
    }
  }

  // ── Voyage lifecycle ──────────────────────────────────────────────────────

  Future<void> _beginVoyage() async {
    final id = _generateUuid();
    final now = DateTime.now();
    _currentVoyageId = id;
    _voyageStartTime = now;
    _currentEntries.clear();
    _highSogCount = 0;
    _lowSogCount = 0;

    await _db?.insert('voyages', {
      'voyage_id': id,
      'start_time': now.millisecondsSinceEpoch,
    });

    _controller.add(VoyageStartedEvent(voyageId: id, startTime: now));
  }

  Future<void> _endVoyage() async {
    final id = _currentVoyageId;
    if (id == null) return;

    final now = DateTime.now();
    await _db?.update(
      'voyages',
      {'end_time': now.millisecondsSinceEpoch},
      where: 'voyage_id = ?',
      whereArgs: [id],
    );

    final stats = _computeStats(id, _voyageStartTime!, now, _currentEntries);

    _currentVoyageId = null;
    _voyageStartTime = null;
    _currentEntries.clear();

    // Cloud sync if logbook_pro
    _syncToCloud(id);

    _controller.add(VoyageEndedEvent(voyageId: id, stats: stats));
  }

  VoyageStats _computeStats(
    String voyageId,
    DateTime start,
    DateTime end,
    List<VoyageLogEntry> entries,
  ) {
    double distNm = 0;
    double sogSum = 0;
    double maxSog = 0;
    double twsSum = 0;
    int twsCount = 0;
    LatLng? first;
    LatLng? last;

    LatLng? prev;
    for (final e in entries) {
      if (e.lat != null && e.lng != null) {
        final pos = LatLng(e.lat!, e.lng!);
        first ??= pos;
        last = pos;
        if (prev != null) {
          distNm += _haversineNm(prev, pos);
        }
        prev = pos;
      }
      if (e.sog != null) {
        sogSum += e.sog!;
        if (e.sog! > maxSog) maxSog = e.sog!;
      }
      if (e.tws != null) {
        twsSum += e.tws!;
        twsCount++;
      }
    }

    return VoyageStats(
      voyageId: voyageId,
      startTime: start,
      endTime: end,
      distanceNm: distNm,
      avgSog: entries.isEmpty ? 0 : sogSum / entries.length,
      maxSog: maxSog,
      avgTws: twsCount > 0 ? twsSum / twsCount : null,
      entryCount: entries.length,
      startPosition: first,
      endPosition: last,
    );
  }

  // ── DB helpers ────────────────────────────────────────────────────────────

  Future<void> _insertEntry(VoyageLogEntry entry) async {
    await _db?.insert('voyage_entries', entry.toMap());
  }

  Future<List<VoyageRecord>> loadPastVoyages() async {
    if (_db == null) return [];
    final rows = await _db!.query('voyages', orderBy: 'start_time DESC');
    final voyages = rows.map(VoyageRecord.fromMap).toList();
    return voyages;
  }

  Future<List<VoyageLogEntry>> loadEntriesForVoyage(String voyageId) async {
    if (_db == null) return [];
    final rows = await _db!.query(
      'voyage_entries',
      where: 'voyage_id = ?',
      whereArgs: [voyageId],
      orderBy: 'timestamp ASC',
    );
    return rows.map(VoyageLogEntry.fromMap).toList();
  }

  VoyageStats statsFromEntries(
      VoyageRecord voyage, List<VoyageLogEntry> entries) {
    return _computeStats(
      voyage.voyageId,
      voyage.startTime,
      voyage.endTime ?? DateTime.now(),
      entries,
    );
  }

  Future<void> deleteVoyage(String voyageId) async {
    await _db?.delete('voyage_entries',
        where: 'voyage_id = ?', whereArgs: [voyageId]);
    await _db?.delete('voyages',
        where: 'voyage_id = ?', whereArgs: [voyageId]);
  }

  // ── Cloud sync ────────────────────────────────────────────────────────────

  Future<void> _syncToCloud(String voyageId) async {
    if (!FloatillaService.instance.isLoggedIn()) return;
    final entries = await loadEntriesForVoyage(voyageId);
    if (entries.isEmpty) return;

    try {
      final payload = entries.map((e) {
        return {
          'voyage_id': e.voyageId,
          'logged_at': e.timestamp.millisecondsSinceEpoch ~/ 1000,
          if (e.lat != null) 'position_lat': e.lat,
          if (e.lng != null) 'position_lng': e.lng,
          if (e.cog != null) 'course': e.cog,
          if (e.sog != null) 'speed': e.sog,
          if (e.tws != null) 'wind_speed': e.tws,
          if (e.twd != null) 'wind_direction': e.twd,
          if (e.depth != null) 'depth': e.depth,
          if (e.engineRpm != null) 'engine_rpm': e.engineRpm,
          if (e.batteryVoltage != null) 'battery_voltage': e.batteryVoltage,
        };
      }).toList();

      await http.post(
        Uri.parse('${FloatillaService.instance.baseUrl}/ships-log/batch'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${FloatillaService.instance.token}',
        },
        body: jsonEncode({'entries': payload}),
      );
    } catch (_) {
      // Offline — entries are stored locally, sync can be retried later
    }
  }

  // ── Utils ─────────────────────────────────────────────────────────────────

  String _generateUuid() {
    final rand = Random.secure();
    final bytes = List<int>.generate(16, (_) => rand.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    String hex(int b) => b.toRadixString(16).padLeft(2, '0');
    return '${bytes.sublist(0, 4).map(hex).join()}'
        '-${bytes.sublist(4, 6).map(hex).join()}'
        '-${bytes.sublist(6, 8).map(hex).join()}'
        '-${bytes.sublist(8, 10).map(hex).join()}'
        '-${bytes.sublist(10, 16).map(hex).join()}';
  }

  double _haversineNm(LatLng a, LatLng b) {
    const r = 6371000.0;
    const nm = 1852.0;
    final dLat = _d2r(b.latitude - a.latitude);
    final dLon = _d2r(b.longitude - a.longitude);
    final sinDLat = sin(dLat / 2);
    final sinDLon = sin(dLon / 2);
    final h = sinDLat * sinDLat +
        cos(_d2r(a.latitude)) * cos(_d2r(b.latitude)) * sinDLon * sinDLon;
    return 2 * r * asin(sqrt(h)) / nm;
  }

  double _d2r(double d) => d * 3.141592653589793 / 180;

  void dispose() {
    _timer?.cancel();
    _controller.close();
    _db?.close();
  }
}

/// Snapshot of vessel data at a point in time — passed by the provider callback.
class VesselSnapshot {
  final DateTime timestamp;
  final double? lat;
  final double? lng;
  final double? cog;
  final double? sog;
  final double? tws;
  final double? twd;
  final double? awa;
  final double? aws;
  final double? depth;
  final double? heading;
  final double? engineRpm;
  final double? batteryVoltage;

  const VesselSnapshot({
    required this.timestamp,
    this.lat,
    this.lng,
    this.cog,
    this.sog,
    this.tws,
    this.twd,
    this.awa,
    this.aws,
    this.depth,
    this.heading,
    this.engineRpm,
    this.batteryVoltage,
  });
}
