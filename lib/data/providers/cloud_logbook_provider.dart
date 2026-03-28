import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/floatilla/floatilla_service.dart';

// ── Models ─────────────────────────────────────────────────────────────────

class CaptainLogEntry {
  final int? id;
  final String entryDate;
  final double? positionLat;
  final double? positionLng;
  final String? weather;
  final String? crew;
  final String notes;
  final int? createdAt;
  final int? updatedAt;
  final bool deleted;
  // Local-only fields for offline queue
  final bool isLocal;
  final String? localId;

  const CaptainLogEntry({
    this.id,
    required this.entryDate,
    this.positionLat,
    this.positionLng,
    this.weather,
    this.crew,
    this.notes = '',
    this.createdAt,
    this.updatedAt,
    this.deleted = false,
    this.isLocal = false,
    this.localId,
  });

  factory CaptainLogEntry.fromJson(Map<String, dynamic> j) => CaptainLogEntry(
        id: j['id'] as int?,
        entryDate: j['entry_date'] as String? ?? '',
        positionLat: (j['position_lat'] as num?)?.toDouble(),
        positionLng: (j['position_lng'] as num?)?.toDouble(),
        weather: j['weather'] as String?,
        crew: j['crew'] as String?,
        notes: j['notes'] as String? ?? '',
        createdAt: (j['created_at'] as num?)?.toInt(),
        updatedAt: (j['updated_at'] as num?)?.toInt(),
        deleted: j['deleted'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'entry_date': entryDate,
        if (positionLat != null) 'position_lat': positionLat,
        if (positionLng != null) 'position_lng': positionLng,
        if (weather != null) 'weather': weather,
        if (crew != null) 'crew': crew,
        'notes': notes,
        if (createdAt != null) 'created_at': createdAt,
        if (updatedAt != null) 'updated_at': updatedAt,
        'deleted': deleted,
        'is_local': isLocal,
        if (localId != null) 'local_id': localId,
      };

  CaptainLogEntry copyWith({
    int? id,
    String? entryDate,
    double? positionLat,
    double? positionLng,
    String? weather,
    String? crew,
    String? notes,
    int? createdAt,
    int? updatedAt,
    bool? deleted,
    bool? isLocal,
    String? localId,
  }) =>
      CaptainLogEntry(
        id: id ?? this.id,
        entryDate: entryDate ?? this.entryDate,
        positionLat: positionLat ?? this.positionLat,
        positionLng: positionLng ?? this.positionLng,
        weather: weather ?? this.weather,
        crew: crew ?? this.crew,
        notes: notes ?? this.notes,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        deleted: deleted ?? this.deleted,
        isLocal: isLocal ?? this.isLocal,
        localId: localId ?? this.localId,
      );
}

class ShipLogEntry {
  final int? id;
  final int loggedAt;
  final double? positionLat;
  final double? positionLng;
  final double? course;
  final double? speed;
  final double? windSpeed;
  final double? windDirection;
  final double? depth;
  final double? barometer;
  final double? engineHours;
  final double? fuelRemaining;
  final String? notes;
  final String? voyageId;
  final int? createdAt;
  final bool deleted;
  final bool isLocal;

  const ShipLogEntry({
    this.id,
    required this.loggedAt,
    this.positionLat,
    this.positionLng,
    this.course,
    this.speed,
    this.windSpeed,
    this.windDirection,
    this.depth,
    this.barometer,
    this.engineHours,
    this.fuelRemaining,
    this.notes,
    this.voyageId,
    this.createdAt,
    this.deleted = false,
    this.isLocal = false,
  });

  factory ShipLogEntry.fromJson(Map<String, dynamic> j) => ShipLogEntry(
        id: j['id'] as int?,
        loggedAt: (j['logged_at'] as num).toInt(),
        positionLat: (j['position_lat'] as num?)?.toDouble(),
        positionLng: (j['position_lng'] as num?)?.toDouble(),
        course: (j['course'] as num?)?.toDouble(),
        speed: (j['speed'] as num?)?.toDouble(),
        windSpeed: (j['wind_speed'] as num?)?.toDouble(),
        windDirection: (j['wind_direction'] as num?)?.toDouble(),
        depth: (j['depth'] as num?)?.toDouble(),
        barometer: (j['barometer'] as num?)?.toDouble(),
        engineHours: (j['engine_hours'] as num?)?.toDouble(),
        fuelRemaining: (j['fuel_remaining'] as num?)?.toDouble(),
        notes: j['notes'] as String?,
        voyageId: j['voyage_id'] as String?,
        createdAt: (j['created_at'] as num?)?.toInt(),
        deleted: j['deleted'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'logged_at': loggedAt,
        if (positionLat != null) 'position_lat': positionLat,
        if (positionLng != null) 'position_lng': positionLng,
        if (course != null) 'course': course,
        if (speed != null) 'speed': speed,
        if (windSpeed != null) 'wind_speed': windSpeed,
        if (windDirection != null) 'wind_direction': windDirection,
        if (depth != null) 'depth': depth,
        if (barometer != null) 'barometer': barometer,
        if (engineHours != null) 'engine_hours': engineHours,
        if (fuelRemaining != null) 'fuel_remaining': fuelRemaining,
        if (notes != null) 'notes': notes,
        if (voyageId != null) 'voyage_id': voyageId,
        if (createdAt != null) 'created_at': createdAt,
        'deleted': deleted,
      };
}

class VoyageSummary {
  final String voyageId;
  final int startTime;
  final int endTime;
  final int entryCount;
  final double? distanceNm;

  const VoyageSummary({
    required this.voyageId,
    required this.startTime,
    required this.endTime,
    required this.entryCount,
    this.distanceNm,
  });

  factory VoyageSummary.fromJson(Map<String, dynamic> j) => VoyageSummary(
        voyageId: j['voyage_id'] as String? ?? '',
        startTime: (j['start_time'] as num).toInt(),
        endTime: (j['end_time'] as num).toInt(),
        entryCount: (j['entry_count'] as num).toInt(),
      );
}

// ── Sync State ─────────────────────────────────────────────────────────────

enum SyncStatus { idle, syncing, success, error }

class LogbookSyncState {
  final SyncStatus status;
  final String? message;
  final int? lastSyncedAt;
  final bool logbookPro;
  final List<CaptainLogEntry> captainsLog;
  final List<ShipLogEntry> shipsLog;
  final List<VoyageSummary> voyages;

  const LogbookSyncState({
    this.status = SyncStatus.idle,
    this.message,
    this.lastSyncedAt,
    this.logbookPro = false,
    this.captainsLog = const [],
    this.shipsLog = const [],
    this.voyages = const [],
  });

  LogbookSyncState copyWith({
    SyncStatus? status,
    String? message,
    int? lastSyncedAt,
    bool? logbookPro,
    List<CaptainLogEntry>? captainsLog,
    List<ShipLogEntry>? shipsLog,
    List<VoyageSummary>? voyages,
  }) =>
      LogbookSyncState(
        status: status ?? this.status,
        message: message ?? this.message,
        lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
        logbookPro: logbookPro ?? this.logbookPro,
        captainsLog: captainsLog ?? this.captainsLog,
        shipsLog: shipsLog ?? this.shipsLog,
        voyages: voyages ?? this.voyages,
      );
}

// ── Notifier ───────────────────────────────────────────────────────────────

class CloudLogbookNotifier extends StateNotifier<LogbookSyncState> {
  static const _prefsCaptainsKey = 'logbook_captains_cache';
  static const _prefsShipsKey = 'logbook_ships_cache';
  static const _prefsOfflineQueueKey = 'logbook_offline_queue';
  static const _prefsLastSyncKey = 'logbook_last_sync';

  Timer? _syncTimer;
  final List<Map<String, dynamic>> _offlineQueue = [];

  CloudLogbookNotifier() : super(const LogbookSyncState()) {
    _init();
  }

  Future<void> _init() async {
    await _loadFromCache();
    await checkStatus();
  }

  String get _baseUrl => FloatillaService.instance.baseUrl;
  String? get _token => FloatillaService.instance.token;
  bool get _loggedIn => FloatillaService.instance.isLoggedIn();

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_token',
      };

  Future<void> _loadFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastSync = prefs.getInt(_prefsLastSyncKey);

      final captainsRaw = prefs.getString(_prefsCaptainsKey);
      final shipsRaw = prefs.getString(_prefsShipsKey);

      final captains = captainsRaw != null
          ? (jsonDecode(captainsRaw) as List)
              .map((e) => CaptainLogEntry.fromJson(e as Map<String, dynamic>))
              .toList()
          : <CaptainLogEntry>[];

      final ships = shipsRaw != null
          ? (jsonDecode(shipsRaw) as List)
              .map((e) => ShipLogEntry.fromJson(e as Map<String, dynamic>))
              .toList()
          : <ShipLogEntry>[];

      final queueRaw = prefs.getString(_prefsOfflineQueueKey);
      if (queueRaw != null) {
        _offlineQueue.addAll(
            (jsonDecode(queueRaw) as List).cast<Map<String, dynamic>>());
      }

      state = state.copyWith(
        captainsLog: captains,
        shipsLog: ships,
        lastSyncedAt: lastSync,
      );
    } catch (_) {}
  }

  Future<void> _saveToCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _prefsCaptainsKey,
        jsonEncode(state.captainsLog.map((e) => e.toJson()).toList()),
      );
      await prefs.setString(
        _prefsShipsKey,
        jsonEncode(state.shipsLog.map((e) => e.toJson()).toList()),
      );
      if (state.lastSyncedAt != null) {
        await prefs.setInt(_prefsLastSyncKey, state.lastSyncedAt!);
      }
    } catch (_) {}
  }

  Future<void> checkStatus() async {
    if (!_loggedIn) return;
    try {
      final resp = await http.get(
        Uri.parse('$_baseUrl/logbook/status'),
        headers: _headers,
      );
      if (resp.statusCode == 200) {
        final body = jsonDecode(resp.body) as Map<String, dynamic>;
        final isPro = body['logbook_pro'] as bool? ?? false;
        state = state.copyWith(logbookPro: isPro);
        if (isPro) {
          await syncAll();
          _startPeriodicSync();
        }
      }
    } catch (_) {}
  }

  void _startPeriodicSync() {
    _syncTimer?.cancel();
    if (!state.logbookPro) return;
    _syncTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      syncAll();
    });
  }

  Future<void> syncAll() async {
    await Future.wait([syncCaptainsLog(), syncShipsLog()]);
  }

  Future<void> syncCaptainsLog() async {
    if (!_loggedIn || !state.logbookPro) return;
    state = state.copyWith(status: SyncStatus.syncing);
    try {
      final since = state.lastSyncedAt ?? 0;
      final resp = await http.get(
        Uri.parse('$_baseUrl/captains-log/sync?since=$since'),
        headers: _headers,
      );
      if (resp.statusCode == 200) {
        final raw = jsonDecode(resp.body) as List;
        final incoming = raw
            .map((e) => CaptainLogEntry.fromJson(e as Map<String, dynamic>))
            .toList();

        // Merge: incoming entries override local by id
        final map = <int, CaptainLogEntry>{};
        for (final e in state.captainsLog) {
          if (e.id != null) map[e.id!] = e;
        }
        for (final e in incoming) {
          if (e.id != null) map[e.id!] = e;
        }

        final merged = map.values
            .where((e) => !e.deleted)
            .toList()
          ..sort((a, b) => (b.entryDate).compareTo(a.entryDate));

        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        state = state.copyWith(
          captainsLog: merged,
          status: SyncStatus.success,
          lastSyncedAt: now,
        );
        await _saveToCache();

        // Flush offline queue
        await _flushOfflineQueue();
      } else if (resp.statusCode == 402) {
        state = state.copyWith(
          status: SyncStatus.error,
          message: 'Logbook Pro required',
          logbookPro: false,
        );
      } else {
        state = state.copyWith(status: SyncStatus.error);
      }
    } catch (_) {
      state = state.copyWith(status: SyncStatus.error, message: 'Offline');
    }
  }

  Future<void> syncShipsLog() async {
    if (!_loggedIn || !state.logbookPro) return;
    try {
      final since = state.lastSyncedAt ?? 0;
      final resp = await http.get(
        Uri.parse('$_baseUrl/ships-log/sync?since=$since'),
        headers: _headers,
      );
      if (resp.statusCode == 200) {
        final raw = jsonDecode(resp.body) as List;
        final incoming = raw
            .map((e) => ShipLogEntry.fromJson(e as Map<String, dynamic>))
            .toList();

        final map = <int, ShipLogEntry>{};
        for (final e in state.shipsLog) {
          if (e.id != null) map[e.id!] = e;
        }
        for (final e in incoming) {
          if (e.id != null) map[e.id!] = e;
        }

        final merged = map.values
            .where((e) => !e.deleted)
            .toList()
          ..sort((a, b) => b.loggedAt.compareTo(a.loggedAt));

        state = state.copyWith(shipsLog: merged);
        await _saveToCache();
        await _refreshVoyages();
      }
    } catch (_) {}
  }

  Future<void> _refreshVoyages() async {
    if (!_loggedIn || !state.logbookPro) return;
    try {
      final resp = await http.get(
        Uri.parse('$_baseUrl/ships-log/voyages'),
        headers: _headers,
      );
      if (resp.statusCode == 200) {
        final raw = jsonDecode(resp.body) as List;
        final voyages = raw
            .map((e) => VoyageSummary.fromJson(e as Map<String, dynamic>))
            .toList();
        state = state.copyWith(voyages: voyages);
      }
    } catch (_) {}
  }

  // ── Captain's Log CRUD ─────────────────────────────────────────────────

  Future<bool> addCaptainEntry(CaptainLogEntry entry) async {
    if (!_loggedIn) return false;
    if (!state.logbookPro) {
      // Add to local list and offline queue
      final local = entry.copyWith(
        isLocal: true,
        localId: DateTime.now().millisecondsSinceEpoch.toString(),
      );
      state = state.copyWith(
        captainsLog: [local, ...state.captainsLog],
      );
      _queueOffline('captain', 'create', entry.toJson());
      await _saveToCache();
      return true;
    }
    try {
      final resp = await http.post(
        Uri.parse('$_baseUrl/captains-log'),
        headers: _headers,
        body: jsonEncode(entry.toJson()),
      );
      if (resp.statusCode == 201) {
        final created =
            CaptainLogEntry.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
        state = state.copyWith(
          captainsLog: [created, ...state.captainsLog],
        );
        await _saveToCache();
        return true;
      }
    } catch (_) {
      _queueOffline('captain', 'create', entry.toJson());
    }
    return false;
  }

  Future<bool> updateCaptainEntry(CaptainLogEntry entry) async {
    if (!_loggedIn || entry.id == null) return false;
    try {
      final resp = await http.put(
        Uri.parse('$_baseUrl/captains-log/${entry.id}'),
        headers: _headers,
        body: jsonEncode(entry.toJson()),
      );
      if (resp.statusCode == 200) {
        final updated =
            CaptainLogEntry.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
        final list = state.captainsLog.map((e) => e.id == updated.id ? updated : e).toList();
        state = state.copyWith(captainsLog: list);
        await _saveToCache();
        return true;
      }
    } catch (_) {}
    return false;
  }

  Future<bool> deleteCaptainEntry(int id) async {
    if (!_loggedIn) return false;
    // Optimistic local remove
    state = state.copyWith(
      captainsLog: state.captainsLog.where((e) => e.id != id).toList(),
    );
    await _saveToCache();
    try {
      await http.delete(
        Uri.parse('$_baseUrl/captains-log/$id'),
        headers: _headers,
      );
    } catch (_) {}
    return true;
  }

  // ── Ship's Log ─────────────────────────────────────────────────────────

  Future<bool> addShipEntry(ShipLogEntry entry) async {
    if (!_loggedIn) return false;
    if (!state.logbookPro) {
      _queueOffline('ship', 'create', entry.toJson());
      return false;
    }
    try {
      final resp = await http.post(
        Uri.parse('$_baseUrl/ships-log'),
        headers: _headers,
        body: jsonEncode(entry.toJson()),
      );
      if (resp.statusCode == 201) {
        final created =
            ShipLogEntry.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
        state = state.copyWith(
          shipsLog: [created, ...state.shipsLog],
        );
        await _saveToCache();
        return true;
      }
    } catch (_) {
      _queueOffline('ship', 'create', entry.toJson());
    }
    return false;
  }

  Future<String> getSubscribeUrl() async {
    try {
      final resp = await http.post(
        Uri.parse('$_baseUrl/logbook/subscribe'),
        headers: _headers,
      );
      if (resp.statusCode == 200) {
        final body = jsonDecode(resp.body) as Map<String, dynamic>;
        return body['url'] as String? ?? '';
      }
    } catch (_) {}
    return '';
  }

  // ── Offline Queue ──────────────────────────────────────────────────────

  void _queueOffline(String type, String action, Map<String, dynamic> data) {
    _offlineQueue.add({'type': type, 'action': action, 'data': data});
    _saveOfflineQueue();
  }

  Future<void> _saveOfflineQueue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsOfflineQueueKey, jsonEncode(_offlineQueue));
    } catch (_) {}
  }

  Future<void> _flushOfflineQueue() async {
    if (_offlineQueue.isEmpty || !_loggedIn || !state.logbookPro) return;
    final toFlush = List<Map<String, dynamic>>.from(_offlineQueue);
    _offlineQueue.clear();
    await _saveOfflineQueue();

    for (final item in toFlush) {
      try {
        if (item['type'] == 'captain' && item['action'] == 'create') {
          final entry = CaptainLogEntry.fromJson(item['data'] as Map<String, dynamic>);
          await addCaptainEntry(entry);
        } else if (item['type'] == 'ship' && item['action'] == 'create') {
          final entry = ShipLogEntry.fromJson(item['data'] as Map<String, dynamic>);
          await addShipEntry(entry);
        }
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    super.dispose();
  }
}

// ── Provider ───────────────────────────────────────────────────────────────

final cloudLogbookProvider =
    StateNotifierProvider<CloudLogbookNotifier, LogbookSyncState>(
        (ref) => CloudLogbookNotifier());
