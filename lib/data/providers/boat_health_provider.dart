import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../core/signalk/signalk_source.dart';
import '../../data/models/signalk_state.dart';
import 'signalk_provider.dart';

// ── Enums & Models ──────────────────────────────────────────────────────────

enum SensorStatus { online, stale, offline, warning, critical }

enum ComparisonOp { greaterThan, lessThan, equalTo }

class AlertRule {
  final String id;
  final String path;
  final double threshold;
  final ComparisonOp op;
  final String message;
  final bool enabled;

  const AlertRule({
    required this.id,
    required this.path,
    required this.threshold,
    required this.op,
    required this.message,
    this.enabled = true,
  });

  AlertRule copyWith({
    String? id,
    String? path,
    double? threshold,
    ComparisonOp? op,
    String? message,
    bool? enabled,
  }) {
    return AlertRule(
      id: id ?? this.id,
      path: path ?? this.path,
      threshold: threshold ?? this.threshold,
      op: op ?? this.op,
      message: message ?? this.message,
      enabled: enabled ?? this.enabled,
    );
  }

  bool matches(double value) {
    switch (op) {
      case ComparisonOp.greaterThan:
        return value > threshold;
      case ComparisonOp.lessThan:
        return value < threshold;
      case ComparisonOp.equalTo:
        return value == threshold;
    }
  }
}

class TriggeredAlert {
  final String ruleId;
  final String path;
  final String message;
  final double value;
  final DateTime triggeredAt;

  const TriggeredAlert({
    required this.ruleId,
    required this.path,
    required this.message,
    required this.value,
    required this.triggeredAt,
  });
}

class SensorReading {
  final double value;
  final DateTime timestamp;

  const SensorReading({required this.value, required this.timestamp});
}

class SensorData {
  final String path;
  final String unit;
  final double? currentValue;
  final DateTime? lastSeen;
  final SensorStatus status;
  // Ring buffer — max 120 entries
  final List<SensorReading> history;

  const SensorData({
    required this.path,
    this.unit = '',
    this.currentValue,
    this.lastSeen,
    this.status = SensorStatus.offline,
    this.history = const [],
  });

  SensorData copyWith({
    String? unit,
    double? currentValue,
    DateTime? lastSeen,
    SensorStatus? status,
    List<SensorReading>? history,
  }) {
    return SensorData(
      path: path,
      unit: unit ?? this.unit,
      currentValue: currentValue ?? this.currentValue,
      lastSeen: lastSeen ?? this.lastSeen,
      status: status ?? this.status,
      history: history ?? this.history,
    );
  }
}

class BoatHealthState {
  final Map<String, SensorData> sensors;
  final List<AlertRule> rules;
  final List<TriggeredAlert> alertHistory;

  const BoatHealthState({
    this.sensors = const {},
    this.rules = const [],
    this.alertHistory = const [],
  });

  int get onlineCount =>
      sensors.values.where((s) => s.status == SensorStatus.online).length;
  int get warningCount => sensors.values
      .where((s) =>
          s.status == SensorStatus.warning || s.status == SensorStatus.stale)
      .length;
  int get offlineCount => sensors.values
      .where((s) =>
          s.status == SensorStatus.offline || s.status == SensorStatus.critical)
      .length;

  BoatHealthState copyWith({
    Map<String, SensorData>? sensors,
    List<AlertRule>? rules,
    List<TriggeredAlert>? alertHistory,
  }) {
    return BoatHealthState(
      sensors: sensors ?? this.sensors,
      rules: rules ?? this.rules,
      alertHistory: alertHistory ?? this.alertHistory,
    );
  }
}

// ── Default Rules ────────────────────────────────────────────────────────────

final _defaultRules = <AlertRule>[
  AlertRule(
    id: 'battery_12v_warn',
    path: 'electrical.batteries.0.voltage',
    threshold: 12.2,
    op: ComparisonOp.lessThan,
    message: 'Battery voltage low (12V system)',
  ),
  AlertRule(
    id: 'battery_24v_warn',
    path: 'electrical.batteries.0.voltage',
    threshold: 24.4,
    op: ComparisonOp.lessThan,
    message: 'Battery voltage low (24V system)',
    enabled: false, // user enables if 24V
  ),
  AlertRule(
    id: 'coolant_temp_warn',
    path: 'propulsion.0.coolantTemp',
    threshold: 90.0,
    op: ComparisonOp.greaterThan,
    message: 'Engine coolant temperature high (>90°C)',
  ),
  AlertRule(
    id: 'fuel_level_warn',
    path: 'tanks.fuel.0.currentLevel',
    threshold: 0.20,
    op: ComparisonOp.lessThan,
    message: 'Fuel level below 20%',
  ),
  AlertRule(
    id: 'bilge_runtime_warn',
    path: 'electrical.bilgePump.0.runtime',
    threshold: 5.0,
    op: ComparisonOp.greaterThan,
    message: 'Bilge pump running >5 min (possible ingress)',
  ),
];

// ── Notifications helper ─────────────────────────────────────────────────────

FlutterLocalNotificationsPlugin? _notificationsPlugin;
bool _notificationsInitialized = false;

Future<void> _ensureNotificationsReady() async {
  if (_notificationsInitialized) return;
  _notificationsPlugin = FlutterLocalNotificationsPlugin();
  const initAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
  const initDarwin = DarwinInitializationSettings();
  const initSettings = InitializationSettings(
    android: initAndroid,
    iOS: initDarwin,
    macOS: initDarwin,
  );
  await _notificationsPlugin!.initialize(initSettings);
  _notificationsInitialized = true;
}

Future<void> _sendNotification(String title, String body, int id) async {
  try {
    await _ensureNotificationsReady();
    if (_notificationsPlugin == null) return;
    const androidDetails = AndroidNotificationDetails(
      'boat_health',
      'Boat Health Alerts',
      channelDescription: 'Critical boat system alerts',
      importance: Importance.high,
      priority: Priority.high,
    );
    const darwinDetails = DarwinNotificationDetails();
    const details = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
      macOS: darwinDetails,
    );
    await _notificationsPlugin!.show(id, title, body, details);
  } catch (_) {
    // Notifications not available — fail silently
  }
}

// ── Provider ────────────────────────────────────────────────────────────────

class BoatHealthNotifier extends StateNotifier<BoatHealthState> {
  // ignore: unused_field
  final Ref _ref;
  Timer? _ruleCheckTimer;
  final _alertStreamController = StreamController<TriggeredAlert>.broadcast();
  final _recentlyAlerted = <String, DateTime>{};

  BoatHealthNotifier(this._ref) : super(BoatHealthState(rules: _defaultRules)) {
    _ruleCheckTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _checkRules(),
    );
  }

  Stream<TriggeredAlert> get alertStream => _alertStreamController.stream;

  /// Called when new Signal K state arrives — update all sensor tracking.
  void onSignalKUpdate(SignalKState skState) {
    if (skState.connectionState != SignalKConnectionState.connected) {
      _markAllStale();
      return;
    }

    final now = DateTime.now();
    final sensors = Map<String, SensorData>.from(state.sensors);
    final vessel = skState.ownVessel;

    // ── Extract flat sensor readings from structured SK state ──────────────
    final rawValues = <String, _SensorRaw>{};

    // Navigation
    final nav = vessel.navigation;
    if (nav.sog != null) {
      rawValues['navigation.speedOverGround'] =
          _SensorRaw(nav.sog!, 'kn');
    }
    if (nav.cog != null) {
      rawValues['navigation.courseOverGroundTrue'] =
          _SensorRaw(nav.cog!, '°');
    }
    if (nav.headingTrue != null) {
      rawValues['navigation.headingTrue'] =
          _SensorRaw(nav.headingTrue!, '°');
    }
    if (nav.rateOfTurn != null) {
      rawValues['navigation.rateOfTurn'] =
          _SensorRaw(nav.rateOfTurn!, '°/min');
    }

    // Environment
    final env = vessel.environment;
    if (env.depthBelowKeel != null) {
      rawValues['environment.depth.belowKeel'] =
          _SensorRaw(env.depthBelowKeel!, 'm');
    }
    if (env.depthBelowTransducer != null) {
      rawValues['environment.depth.belowTransducer'] =
          _SensorRaw(env.depthBelowTransducer!, 'm');
    }
    if (env.windSpeedApparent != null) {
      rawValues['environment.wind.speedApparent'] =
          _SensorRaw(env.windSpeedApparent!, 'kn');
    }
    if (env.windSpeedTrue != null) {
      rawValues['environment.wind.speedTrue'] =
          _SensorRaw(env.windSpeedTrue!, 'kn');
    }
    if (env.windAngleApparent != null) {
      rawValues['environment.wind.angleApparent'] =
          _SensorRaw(env.windAngleApparent!, '°');
    }
    if (env.waterTemp != null) {
      rawValues['environment.water.temperature'] =
          _SensorRaw(env.waterTemp!, '°C');
    }
    if (env.airTemp != null) {
      rawValues['environment.outside.temperature'] =
          _SensorRaw(env.airTemp!, '°C');
    }
    if (env.pressure != null) {
      rawValues['environment.outside.pressure'] =
          _SensorRaw(env.pressure!, 'hPa');
    }
    if (env.humidity != null) {
      rawValues['environment.outside.humidity'] =
          _SensorRaw(env.humidity! * 100, '%');
    }

    // Propulsion engines
    for (final entry in vessel.propulsion.engines.entries) {
      final id = entry.key;
      final e = entry.value;
      if (e.rpm != null) {
        rawValues['propulsion.$id.rpm'] = _SensorRaw(e.rpm!, 'rpm');
      }
      if (e.coolantTemp != null) {
        rawValues['propulsion.$id.coolantTemp'] =
            _SensorRaw(e.coolantTemp!, '°C');
      }
      if (e.oilPressure != null) {
        rawValues['propulsion.$id.oilPressure'] =
            _SensorRaw(e.oilPressure! / 1000, 'kPa');
      }
      if (e.temperature != null) {
        rawValues['propulsion.$id.temperature'] =
            _SensorRaw(e.temperature!, '°C');
      }
      if (e.fuelRate != null) {
        rawValues['propulsion.$id.fuelRate'] =
            _SensorRaw(e.fuelRate!, 'L/h');
      }
      if (e.exhaustTemp != null) {
        rawValues['propulsion.$id.exhaustTemp'] =
            _SensorRaw(e.exhaustTemp!, '°C');
      }
    }

    // Tanks
    for (final entry in vessel.tanks.tanks.entries) {
      final id = entry.key;
      final t = entry.value;
      if (t.currentLevel != null) {
        rawValues['tanks.$id.currentLevel'] =
            _SensorRaw(t.currentLevel! * 100, '%');
      }
    }

    // Electrical batteries
    for (final entry in vessel.electrical.batteries.entries) {
      final id = entry.key;
      final b = entry.value;
      if (b.voltage != null) {
        rawValues['electrical.batteries.$id.voltage'] =
            _SensorRaw(b.voltage!, 'V');
      }
      if (b.current != null) {
        rawValues['electrical.batteries.$id.current'] =
            _SensorRaw(b.current!, 'A');
      }
      if (b.stateOfCharge != null) {
        rawValues['electrical.batteries.$id.stateOfCharge'] =
            _SensorRaw(b.stateOfCharge! * 100, '%');
      }
      if (b.temperature != null) {
        rawValues['electrical.batteries.$id.temperature'] =
            _SensorRaw(b.temperature!, '°C');
      }
    }

    // Update sensor map
    for (final entry in rawValues.entries) {
      final path = entry.key;
      final raw = entry.value;
      final existing = sensors[path];
      final history = existing != null
          ? List<SensorReading>.from(existing.history)
          : <SensorReading>[];

      history.add(SensorReading(value: raw.value, timestamp: now));
      // Ring buffer: keep last 120
      if (history.length > 120) {
        history.removeRange(0, history.length - 120);
      }

      sensors[path] = SensorData(
        path: path,
        unit: raw.unit,
        currentValue: raw.value,
        lastSeen: now,
        status: SensorStatus.online,
        history: history,
      );
    }

    // Update staleness for sensors not in this update
    for (final path in sensors.keys.toList()) {
      if (!rawValues.containsKey(path)) {
        final s = sensors[path]!;
        if (s.lastSeen == null) continue;
        final age = now.difference(s.lastSeen!);
        SensorStatus newStatus;
        if (age.inMinutes >= 30) {
          newStatus = SensorStatus.offline;
        } else if (age.inMinutes >= 5) {
          newStatus = SensorStatus.stale;
        } else {
          newStatus = s.status;
        }
        if (newStatus != s.status) {
          sensors[path] = s.copyWith(status: newStatus);
        }
      }
    }

    state = state.copyWith(sensors: sensors);
  }

  void _markAllStale() {
    final now = DateTime.now();
    final sensors = Map<String, SensorData>.from(state.sensors);
    bool changed = false;
    for (final path in sensors.keys.toList()) {
      final s = sensors[path]!;
      if (s.lastSeen == null) continue;
      final age = now.difference(s.lastSeen!);
      SensorStatus newStatus;
      if (age.inMinutes >= 30) {
        newStatus = SensorStatus.offline;
      } else if (age.inMinutes >= 5) {
        newStatus = SensorStatus.stale;
      } else {
        continue;
      }
      if (newStatus != s.status) {
        sensors[path] = s.copyWith(status: newStatus);
        changed = true;
      }
    }
    if (changed) state = state.copyWith(sensors: sensors);
  }

  void _checkRules() {
    final now = DateTime.now();
    final sensors = state.sensors;
    final alerts = List<TriggeredAlert>.from(state.alertHistory);
    bool stateChanged = false;
    final updatedSensors = Map<String, SensorData>.from(sensors);

    for (final rule in state.rules) {
      if (!rule.enabled) continue;

      final sensor = sensors[rule.path];
      if (sensor == null || sensor.currentValue == null) continue;
      if (sensor.status == SensorStatus.offline) continue;

      final value = sensor.currentValue!;
      if (!rule.matches(value)) {
        // Clear warning/critical if no longer triggered
        if (sensor.status == SensorStatus.warning ||
            sensor.status == SensorStatus.critical) {
          updatedSensors[rule.path] =
              sensor.copyWith(status: SensorStatus.online);
          stateChanged = true;
        }
        continue;
      }

      // Determine severity
      final isCritical = _isCriticalRule(rule.id);
      final newStatus =
          isCritical ? SensorStatus.critical : SensorStatus.warning;

      if (updatedSensors[rule.path]?.status != newStatus) {
        updatedSensors[rule.path] = sensor.copyWith(status: newStatus);
        stateChanged = true;
      }

      // Debounce: don't re-alert within 10 minutes
      final lastAlert = _recentlyAlerted[rule.id];
      if (lastAlert != null &&
          now.difference(lastAlert).inMinutes < 10) {
        continue;
      }

      _recentlyAlerted[rule.id] = now;
      final alert = TriggeredAlert(
        ruleId: rule.id,
        path: rule.path,
        message: rule.message,
        value: value,
        triggeredAt: now,
      );
      alerts.add(alert);
      _alertStreamController.add(alert);

      if (isCritical) {
        _sendNotification(
          'Boat Alert: ${rule.message}',
          'Value: ${value.toStringAsFixed(2)} on ${rule.path}',
          rule.id.hashCode.abs(),
        );
      }
    }

    // RPM drop-to-zero alert (engine was running, now 0)
    _checkEngineRpmDrop(updatedSensors, alerts, now);

    if (stateChanged || alerts.length != state.alertHistory.length) {
      state = state.copyWith(
        sensors: stateChanged ? updatedSensors : sensors,
        alertHistory: alerts.length > 200
            ? alerts.sublist(alerts.length - 200)
            : alerts,
      );
    }
  }

  void _checkEngineRpmDrop(
    Map<String, SensorData> sensors,
    List<TriggeredAlert> alerts,
    DateTime now,
  ) {
    for (final path in sensors.keys) {
      if (!path.contains('.rpm')) continue;
      final sensor = sensors[path]!;
      if (sensor.currentValue == null || sensor.history.length < 3) continue;

      final current = sensor.currentValue!;
      // Check if RPM was above 200 in the last 3 readings but is now 0
      final recentNonZero = sensor.history.reversed
          .skip(1)
          .take(3)
          .any((r) => r.value > 200);
      if (recentNonZero && current < 10) {
        final ruleId = 'engine_rpm_drop_$path';
        final lastAlert = _recentlyAlerted[ruleId];
        if (lastAlert == null || now.difference(lastAlert).inMinutes >= 10) {
          _recentlyAlerted[ruleId] = now;
          final alert = TriggeredAlert(
            ruleId: ruleId,
            path: path,
            message: 'Engine RPM dropped to 0 (engine stalled/stopped)',
            value: current,
            triggeredAt: now,
          );
          alerts.add(alert);
          _alertStreamController.add(alert);
          _sendNotification(
            'Engine Alert',
            'Engine RPM dropped to 0 on $path',
            ruleId.hashCode.abs(),
          );
        }
      }
    }
  }

  bool _isCriticalRule(String ruleId) {
    const criticalIds = {
      'battery_12v_warn',
      'battery_24v_warn',
      'bilge_runtime_warn',
    };
    return criticalIds.contains(ruleId);
  }

  void addRule(AlertRule rule) {
    state = state.copyWith(rules: [...state.rules, rule]);
  }

  void updateRule(AlertRule rule) {
    final rules = state.rules.map((r) => r.id == rule.id ? rule : r).toList();
    state = state.copyWith(rules: rules);
  }

  void removeRule(String ruleId) {
    final rules = state.rules.where((r) => r.id != ruleId).toList();
    state = state.copyWith(rules: rules);
  }

  void clearAlertHistory() {
    state = state.copyWith(alertHistory: []);
  }

  @override
  void dispose() {
    _ruleCheckTimer?.cancel();
    _alertStreamController.close();
    super.dispose();
  }
}

// ── Helper ───────────────────────────────────────────────────────────────────

class _SensorRaw {
  final double value;
  final String unit;
  const _SensorRaw(this.value, this.unit);
}

// ── Providers ────────────────────────────────────────────────────────────────

final boatHealthProvider =
    StateNotifierProvider<BoatHealthNotifier, BoatHealthState>((ref) {
  final notifier = BoatHealthNotifier(ref);

  // Watch Signal K state and push updates into health notifier
  ref.listen<SignalKState>(signalKProvider, (_, next) {
    notifier.onSignalKUpdate(next);
  });

  return notifier;
});

/// Sorted list of sensor paths for display.
final sensorListProvider = Provider<List<SensorData>>((ref) {
  final sensors = ref.watch(boatHealthProvider).sensors;
  final list = sensors.values.toList();
  list.sort((a, b) {
    // Critical/warning first, then by path name
    final sa = _statusSortKey(a.status);
    final sb = _statusSortKey(b.status);
    if (sa != sb) return sa.compareTo(sb);
    return a.path.compareTo(b.path);
  });
  return list;
});

int _statusSortKey(SensorStatus s) {
  switch (s) {
    case SensorStatus.critical:
      return 0;
    case SensorStatus.warning:
      return 1;
    case SensorStatus.offline:
      return 2;
    case SensorStatus.stale:
      return 3;
    case SensorStatus.online:
      return 4;
  }
}
